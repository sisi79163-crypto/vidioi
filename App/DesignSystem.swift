import SwiftUI
import AVFoundation

// Shared rhythm and contrast across studio, editor and tool sheets.
enum VTheme {
    static let background = Color(hex: "#080A0D")
    static let surface = Color(hex: "#12161B")
    static let elevated = Color(hex: "#1C222A")
    static let line = Color.white.opacity(0.08)
    static let mint = Color(hex: "#C6FA73")
    static let cyan = Color(hex: "#68DDE5")
    static let lavender = Color(hex: "#B8A4F7")
    static let muted = Color(hex: "#89929F")
    static let ink = Color(hex: "#0B1008")
}
extension Color {
    init(hex: String) {
        let n = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0xFFFFFF
        self.init(red: Double((n >> 16) & 255) / 255, green: Double((n >> 8) & 255) / 255, blue: Double(n & 255) / 255)
    }
}
struct VButton: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 18).frame(minHeight: 48)
            .foregroundStyle(prominent ? VTheme.ink : .white)
            .background(prominent ? VTheme.mint : VTheme.elevated, in: RoundedRectangle(cornerRadius: 15))
            .opacity(configuration.isPressed ? 0.75 : 1).scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
struct IconButton: View {
    var symbol: String
    var label: String
    var tint: Color = .white
    var action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 17, weight: .medium)).foregroundStyle(tint).frame(width: 44, height: 44).background(VTheme.surface, in: Circle()) }
            .accessibilityLabel(label)
    }
}
struct SectionHeading: View {
    var title: String
    var detail: String = ""
    var body: some View {
        HStack(alignment: .firstTextBaseline) { Text(title).font(.system(size: 19, weight: .bold)); Spacer(); Text(detail).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(VTheme.muted) }
    }
}
struct TinyBadge: View {
    var text: String
    var color: Color = VTheme.mint
    var body: some View { Text(text).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1).padding(.horizontal, 9).padding(.vertical, 5).foregroundStyle(color).background(color.opacity(0.12), in: Capsule()) }
}
struct SheetHeader: View {
    var title: String
    var subtitle: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        HStack { VStack(alignment: .leading, spacing: 5) { Text(title).font(.system(size: 25, weight: .bold)); Text(subtitle).font(.caption).foregroundStyle(VTheme.muted) }; Spacer(); IconButton(symbol: "xmark", label: "إغلاق") { dismiss() } }.padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 16)
    }
}
struct BusyOverlay: View {
    var title: String
    var body: some View { ZStack { Color.black.opacity(0.55).ignoresSafeArea(); VStack(spacing: 20) { ProgressView().tint(VTheme.mint).scaleEffect(1.3); Text(title).font(.headline) }.padding(34).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28)) } }
}
struct MediaThumbnail: View {
    var url: URL?
    var symbol = "film"
    @State private var image: UIImage?
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VTheme.elevated
                if let image { Image(uiImage: image).resizable().scaledToFill() }
                else { Image(systemName: symbol).font(.system(size: 24, weight: .light)).foregroundStyle(VTheme.muted.opacity(0.5)) }
            }.frame(width:geometry.size.width,height:geometry.size.height).clipped()
        }.task(id: url) {
            image = nil
            guard let url else { return }
            if ["jpg","jpeg","png","heic","webp"].contains(url.pathExtension.lowercased()) {
                image = UIImage(contentsOfFile: url.path); return
            }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: 420, height: 420)
            if let frame = try? await generator.image(at: CMTime(seconds: 0.1, preferredTimescale: 600)) { if !Task.isCancelled { image = UIImage(cgImage: frame.image) } }
        }
    }
}
extension MediaKind {
    var icon: String { switch self { case .video: return "film"; case .audio: return "waveform"; case .image: return "photo"; case .text: return "textformat" } }
    var tint: Color { switch self { case .video: return VTheme.cyan; case .audio: return VTheme.mint; case .image: return .orange; case .text: return VTheme.lavender } }
}
extension MotionPreset {
    var title: String { switch self { case .none: return "ثابت"; case .fade: return "تلاشي"; case .pop: return "Pop"; case .slide: return "انزلاق" } }
}
func clockLabel(_ value: Double) -> String { String(format: "%02d:%02d", max(0,Int(value)) / 60, max(0,Int(value)) % 60) }
