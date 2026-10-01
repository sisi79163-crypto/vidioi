import Foundation

enum MediaKind: String, Codable, CaseIterable { case video, audio, image, text }
enum MotionPreset: String, Codable, CaseIterable { case none, fade, pop, slide }
enum AnimatedProperty: String, Codable, CaseIterable, Hashable { case x, y, scale, stretch, rotation, opacity }

struct MotionKey: Codable, Identifiable, Equatable {
    var id = UUID()
    var time: Double
    var property: AnimatedProperty
    var value: Double
}
struct LayerStyle: Codable, Equatable {
    var x = 0.5
    var y = 0.5
    var scale = 1.0
    var stretch = 1.0
    var rotation = 0.0
    var opacity = 1.0
    var fontSize = 84.0
    var fontName = "Arial-BoldMT"
    var color = "#FFFFFF"
    var motion = MotionPreset.none
    var brightness = 0.0
    var contrast = 1.0
    var saturation = 1.0
}
struct Clip: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: MediaKind
    var name: String
    var asset: String? = nil
    var text = ""
    var start = 0.0
    var sourceIn = 0.0
    var duration = 3.0 // Timeline seconds; source duration is duration * speed.
    var speed = 1.0
    var lane = 0 // Higher lanes render above lower lanes.
    var volume = 1.0
    var style = LayerStyle()
    var keys: [MotionKey] = []
    var end: Double { start + duration }
    func value(_ property: AnimatedProperty, at localTime: Double) -> Double {
        let base: Double
        switch property {
        case .x: base = style.x
        case .y: base = style.y
        case .scale: base = style.scale
        case .stretch: base = style.stretch
        case .rotation: base = style.rotation
        case .opacity: base = style.opacity
        }
        let points = keys.filter { $0.property == property }.sorted { $0.time < $1.time }
        guard let first = points.first else { return base }
        if localTime <= first.time { return first.value }
        for pair in zip(points, points.dropFirst()) where localTime <= pair.1.time {
            let t = (localTime - pair.0.time) / max(0.000001, pair.1.time - pair.0.time)
            let eased = t * t * (3 - 2 * t)
            return pair.0.value + (pair.1.value - pair.0.value) * eased
        }
        return points.last!.value
    }
}
struct EditProject: Codable, Equatable {
    var version = 1
    var id = UUID()
    var title = "مشروع جديد"
    var width = 1080
    var height = 1920
    var fps = 30
    var clips: [Clip] = []
    var length: Double { max(0.1, clips.map(\.end).max() ?? 0.1) }
    func validate() throws {
        guard version == 1, title.count <= 2000, width >= 128, width <= 3840, height >= 128, height <= 3840,
              [24, 25, 30, 60].contains(fps), clips.count <= 500, length <= 3600 else {
            throw EditError.invalid("إعدادات المشروع غير صالحة")
        }
        guard Set(clips.map(\.id)).count == clips.count else { throw EditError.invalid("معرّفات مكررة") }
        for c in clips {
            guard [c.start, c.sourceIn, c.duration, c.speed, c.volume].allSatisfy(\.isFinite),
                  c.start >= 0, c.sourceIn >= 0, c.duration >= 0.05, (0.25...4).contains(c.speed),
                  (0...4).contains(c.volume), (0...31).contains(c.lane), c.text.count <= 10000,
                  c.keys.count <= 500 else { throw EditError.invalid("توقيت أو طبقة غير صالحة: \(c.name)") }
            if c.kind != .text {
                guard let asset = c.asset, !asset.isEmpty, asset == URL(fileURLWithPath: asset).lastPathComponent,
                      !asset.contains(".."), !asset.contains("\\"), !asset.contains("/") else {
                    throw EditError.invalid("مسار وسيط غير صالح")
                }
            }
            let s = c.style
            guard [s.x, s.y, s.scale, s.stretch, s.rotation, s.opacity, s.fontSize, s.brightness, s.contrast, s.saturation].allSatisfy(\.isFinite),
                  (-2...3).contains(s.x), (-2...3).contains(s.y), (0.05...8).contains(s.scale),
                  (0.1...5).contains(s.stretch), (-3600...3600).contains(s.rotation),
                  (0...1).contains(s.opacity), (8...400).contains(s.fontSize),
                  (-1...1).contains(s.brightness), (0...4).contains(s.contrast), (0...4).contains(s.saturation),
                  s.color.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil else {
                throw EditError.invalid("خصائص طبقة غير صالحة")
            }
            for k in c.keys {
                guard k.time.isFinite, k.value.isFinite, (0...c.duration).contains(k.time) else {
                    throw EditError.invalid("Keyframe خارج مدة الطبقة")
                }
                let range: ClosedRange<Double>
                switch k.property {
                case .x, .y: range = -2...3
                case .scale: range = 0.05...8
                case .stretch: range = 0.1...5
                case .rotation: range = -3600...3600
                case .opacity: range = 0...1
                }
                guard range.contains(k.value) else { throw EditError.invalid("قيمة حركة غير صالحة") }
            }
        }
    }
}
enum EditError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}

struct EditOperation: Codable {
    var action: String
    var clipID: String?
    var property: String?
    var number: Double?
    var text: String?
    var time: Double?
}
struct EditPlan: Codable {
    var summary: String
    var operations: [EditOperation]
    func applying(to original: EditProject) throws -> EditProject {
        guard operations.count <= 100 else { throw EditError.invalid("عدد تعديلات كبير") }
        var result = original
        for op in operations {
            if op.action == "addText" {
                guard let text = op.text, !text.isEmpty, let start = op.time, let duration = op.number else {
                    throw EditError.invalid("النص يحتاج وقتًا ومدة")
                }
                var c = Clip(kind: .text, name: String(text.prefix(30)))
                c.text = text; c.start = start; c.duration = duration
                c.lane = min(31, (result.clips.map(\.lane).max() ?? 0) + 1)
                c.style.y = 0.75; c.style.motion = .pop
                result.clips.append(c); continue
            }
            guard let id = op.clipID.flatMap(UUID.init(uuidString:)),
                  let index = result.clips.firstIndex(where: { $0.id == id }) else {
                throw EditError.invalid("طبقة غير موجودة")
            }
            if op.action == "remove" { result.clips.remove(at: index); continue }
            if op.action == "keyframe" {
                guard let property = op.property.flatMap(AnimatedProperty.init(rawValue:)),
                      let time = op.time, let value = op.number else { throw EditError.invalid("حركة غير صالحة") }
                result.clips[index].keys.removeAll { $0.property == property && abs($0.time - time) < 0.000001 }
                result.clips[index].keys.append(MotionKey(time: time, property: property, value: value))
                continue
            }
            guard op.action == "set", let property = op.property else { throw EditError.invalid("أمر غير مدعوم") }
            if ["text", "color", "motion", "fontName"].contains(property) {
                guard let text = op.text else { throw EditError.invalid("قيمة نصية مفقودة") }
                switch property {
                case "text": result.clips[index].text = text
                case "color": result.clips[index].style.color = text
                case "fontName": result.clips[index].style.fontName = text
                case "motion":
                    guard let motion = MotionPreset(rawValue: text) else { throw EditError.invalid("قالب حركة غير موجود") }
                    result.clips[index].style.motion = motion
                default: break
                }
            } else {
                guard let n = op.number, n.isFinite else { throw EditError.invalid("قيمة رقمية مفقودة") }
                switch property {
                case "start": result.clips[index].start = n
                case "sourceIn": result.clips[index].sourceIn = n
                case "duration": result.clips[index].duration = n
                case "speed": result.clips[index].speed = n
                case "lane": guard n.rounded() == n, (0...31).contains(n) else { throw EditError.invalid("الطبقة تحتاج عددًا صحيحًا من 0 إلى 31") }; result.clips[index].lane = Int(n)
                case "volume": result.clips[index].volume = n
                case "x": result.clips[index].style.x = n
                case "y": result.clips[index].style.y = n
                case "scale": result.clips[index].style.scale = n
                case "stretch": result.clips[index].style.stretch = n
                case "rotation": result.clips[index].style.rotation = n
                case "opacity": result.clips[index].style.opacity = n
                case "fontSize": result.clips[index].style.fontSize = n
                case "brightness": result.clips[index].style.brightness = n
                case "contrast": result.clips[index].style.contrast = n
                case "saturation": result.clips[index].style.saturation = n
                default: throw EditError.invalid("خاصية غير مدعومة: \(property)")
                }
            }
        }
        try result.validate()
        return result // Atomic: original is untouched if any operation fails.
    }
}
