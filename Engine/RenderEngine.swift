import AVFoundation
import CoreImage
import UIKit

final class RenderInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing = true
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let project: EditProject
    let trackMap: [UUID: CMPersistentTrackID]
    let transforms: [UUID: CGAffineTransform]
    let images: [UUID: CIImage]
    init(project: EditProject, trackMap: [UUID: CMPersistentTrackID], transforms: [UUID: CGAffineTransform], images: [UUID: CIImage]) {
        self.project = project; self.trackMap = trackMap; self.transforms = transforms; self.images = images
        self.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: project.length, preferredTimescale: 600))
        self.requiredSourceTrackIDs = trackMap.values.map { NSNumber(value: $0) }
        super.init()
    }
}

// The same compositor renders preview and export, including motion and text.
final class LayerCompositor: NSObject, AVVideoCompositing {
    var sourcePixelBufferAttributes: [String: Any]? {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    }
    var requiredPixelBufferAttributesForRenderContext: [String: Any] {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
         kCVPixelBufferMetalCompatibilityKey as String: true]
    }
    private let queue = DispatchQueue(label: "vidioi.render", qos: .userInitiated)
    private let context = CIContext(options: [.cacheIntermediates: false])
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}
    func cancelAllPendingVideoCompositionRequests() { queue.sync {} }
    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        queue.async { [self] in
            autoreleasepool {
                guard let instruction = request.videoCompositionInstruction as? RenderInstruction,
                      let output = request.renderContext.newPixelBuffer() else {
                    request.finish(with: EditError.invalid("تعذّر إنشاء إطار")); return
                }
                let p = instruction.project
                let bounds = CGRect(x: 0, y: 0, width: CGFloat(p.width), height: CGFloat(p.height))
                let now = request.compositionTime.seconds
                var canvas = CIImage(color: .black).cropped(to: bounds)
                for clip in p.clips.sorted(by: { $0.lane == $1.lane ? $0.start < $1.start : $0.lane < $1.lane })
                    where clip.kind != .audio && now >= clip.start && now < clip.end {
                    var image: CIImage?
                    if clip.kind == .video, let id = instruction.trackMap[clip.id], let buffer = request.sourceFrame(byTrackID: id) {
                        image = CIImage(cvPixelBuffer: buffer).transformed(by: instruction.transforms[clip.id] ?? .identity)
                    } else { image = instruction.images[clip.id] }
                    guard var layer = image else { continue }
                    if clip.kind == .video || clip.kind == .image {
                        layer = layer.applyingFilter("CIColorControls", parameters: [
                            kCIInputBrightnessKey: clip.style.brightness,
                            kCIInputContrastKey: clip.style.contrast,
                            kCIInputSaturationKey: clip.style.saturation])
                    }
                    let extent = layer.extent
                    guard extent.width > 0, extent.height > 0 else { continue }
                    let t = now - clip.start
                    var scale = clip.value(.scale, at: t)
                    var x = clip.value(.x, at: t)
                    let y = clip.value(.y, at: t)
                    var alpha = clip.value(.opacity, at: t)
                    let intro = min(1, t / 0.32)
                    let outro = min(1, (clip.duration - t) / 0.2)
                    switch clip.style.motion {
                    case .none: break
                    case .fade: alpha *= min(intro, outro)
                    case .pop: scale *= 0.75 + 0.25 * (1 - pow(1 - intro, 3)); alpha *= intro
                    case .slide: x += 0.15 * pow(1 - intro, 3); alpha *= intro
                    }
                    let fit = clip.kind == .text ? 1 : min(bounds.width / extent.width, bounds.height / extent.height)
                    let transform = CGAffineTransform(translationX: bounds.width * x, y: bounds.height * (1 - y))
                        .rotated(by: -clip.value(.rotation, at: t) * .pi / 180)
                        .scaledBy(x: fit * scale * clip.value(.stretch, at: t), y: fit * scale)
                        .translatedBy(x: -extent.midX, y: -extent.midY)
                    layer = layer.transformed(by: transform).applyingFilter("CIColorMatrix", parameters: [
                        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)])
                    canvas = layer.composited(over: canvas).cropped(to: bounds)
                }
                context.render(canvas, to: output, bounds: bounds, colorSpace: CGColorSpaceCreateDeviceRGB())
                request.finish(withComposedVideoFrame: output)
            }
        }
    }
}

struct RenderProduct {
    let composition: AVMutableComposition
    let video: AVMutableVideoComposition
    let audio: AVMutableAudioMix
    func playerItem() -> AVPlayerItem {
        let item = AVPlayerItem(asset: composition)
        item.videoComposition = video; item.audioMix = audio
        return item
    }
}
enum RenderEngine {
    static func build(_ project: EditProject, assets: URL) async throws -> RenderProduct {
        try project.validate()
        let composition = AVMutableComposition()
        var map: [UUID: CMPersistentTrackID] = [:]
        var transforms: [UUID: CGAffineTransform] = [:]
        var images: [UUID: CIImage] = [:]
        var audioParameters: [AVMutableAudioMixInputParameters] = []
        for clip in project.clips {
            if clip.kind == .text {
                images[clip.id] = await MainActor.run { textImage(clip, width: project.width) }
                continue
            }
            guard let filename = clip.asset else { continue }
            let url = assets.appendingPathComponent(filename)
            guard FileManager.default.fileExists(atPath: url.path) else { throw EditError.invalid("ملف مفقود: \(clip.name)") }
            if clip.kind == .image {
                guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else { throw EditError.invalid("صورة غير مدعومة") }
                images[clip.id] = image; continue
            }
            let asset = AVURLAsset(url: url)
            let sourceDuration = try await asset.load(.duration).seconds
            let requested = clip.duration * clip.speed
            guard sourceDuration.isFinite, clip.sourceIn + requested <= sourceDuration + 0.03 else {
                throw EditError.invalid("المقطع يتجاوز مدة الملف: \(clip.name)")
            }
            let source = CMTimeRange(start: time(clip.sourceIn), duration: time(min(requested, sourceDuration - clip.sourceIn)))
            let inserted = CMTimeRange(start: time(clip.start), duration: source.duration)
            if clip.kind == .video {
                guard let track = try await asset.loadTracks(withMediaType: .video).first,
                      let target = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                    throw EditError.invalid("مسار فيديو غير متاح")
                }
                try target.insertTimeRange(source, of: track, at: time(clip.start))
                target.scaleTimeRange(inserted, toDuration: time(clip.duration))
                map[clip.id] = target.trackID
                transforms[clip.id] = try await track.load(.preferredTransform)
            }
            if let track = try await asset.loadTracks(withMediaType: .audio).first,
               let target = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                try target.insertTimeRange(source, of: track, at: time(clip.start))
                target.scaleTimeRange(inserted, toDuration: time(clip.duration))
                let params = AVMutableAudioMixInputParameters(track: target)
                params.setVolume(Float(clip.volume), at: time(clip.start))
                audioParameters.append(params)
            }
        }
        // Empty video track makes title-only and image-only projects renderable.
        let clock = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        clock?.insertEmptyTimeRange(CMTimeRange(start: .zero, duration: time(project.length)))
        let video = AVMutableVideoComposition()
        video.customVideoCompositorClass = LayerCompositor.self
        video.renderSize = CGSize(width: CGFloat(project.width), height: CGFloat(project.height))
        video.frameDuration = CMTime(value: 1, timescale: Int32(project.fps))
        video.instructions = [RenderInstruction(project: project, trackMap: map, transforms: transforms, images: images)]
        let audio = AVMutableAudioMix(); audio.inputParameters = audioParameters
        return RenderProduct(composition: composition, video: video, audio: audio)
    }
    static func export(_ product: RenderProduct, to url: URL, highResolution: Bool) async throws {
        try? FileManager.default.removeItem(at: url)
        let preset = highResolution ? AVAssetExportPresetHEVCHighestQuality : AVAssetExportPresetHighestQuality
        guard let session = AVAssetExportSession(asset: product.composition, presetName: preset) else {
            throw EditError.invalid("التصدير غير مدعوم")
        }
        session.outputURL = url; session.outputFileType = .mp4
        session.videoComposition = product.video; session.audioMix = product.audio
        session.shouldOptimizeForNetworkUse = true
        await session.export()
        if session.status != .completed { throw session.error ?? EditError.invalid("فشل التصدير") }
    }
    private static func time(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 600) }
    @MainActor private static func textImage(_ clip: Clip, width: Int) -> CIImage? {
        let font = UIFont(name: clip.style.fontName, size: clip.style.fontSize) ?? UIFont.boldSystemFont(ofSize: clip.style.fontSize)
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.baseWritingDirection = .natural
        let hex = UInt32(clip.style.color.dropFirst(), radix: 16) ?? 0xFFFFFF
        let color = UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph,
            .strokeColor: UIColor.black.withAlphaComponent(0.7), .strokeWidth: -2]
        let text = NSAttributedString(string: clip.text, attributes: attributes)
        let maxWidth = CGFloat(width) * 0.9
        let rect = text.boundingRect(with: CGSize(width: maxWidth, height: 6000), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        let size = CGSize(width: maxWidth + 32, height: ceil(rect.height) + 32)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            text.draw(with: CGRect(x: 16, y: 16, width: maxWidth, height: size.height - 32), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        }
        return CIImage(image: image)
    }
}
