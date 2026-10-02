import SwiftUI
import AVKit
import PhotosUI
import UniformTypeIdentifiers

@main struct VidioiApp: App {
    @StateObject private var store = EditorStore()
    @StateObject private var account = ChatGPTAccount()
    var body: some Scene { WindowGroup {
        StudioView().environmentObject(store).environmentObject(account)
            .preferredColorScheme(.dark).tint(VTheme.mint)
    } }
}
struct StudioView: View {
    @EnvironmentObject var store: EditorStore
    @EnvironmentObject var account: ChatGPTAccount
    @State private var editor = false
    @State private var connection = false
    @State private var search = ""
    private var projects: [ProjectEntry] { store.entries.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 27) {
                HStack(alignment: .center) {
                    HStack(spacing: 3) { Text("vidioi").font(.system(size: 34, weight: .black, design: .rounded)).tracking(-2); Circle().fill(VTheme.mint).frame(width: 7, height: 7).offset(y: 10) }
                    Spacer()
                    Button { connection = true } label: { ZStack(alignment: .bottomTrailing) { Circle().fill(VTheme.elevated).frame(width: 43, height: 43).overlay(Image(systemName: "person.crop.circle").font(.system(size: 25, weight: .light))); Circle().fill(account.isConnected ? VTheme.mint : VTheme.muted).frame(width: 9, height: 9).overlay(Circle().stroke(VTheme.background, lineWidth: 2)) } }.foregroundStyle(.white).accessibilityIdentifier("connectionButton")
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("مساحتك الإبداعية").font(.system(size: 30, weight: .bold))
                    Text("من أول لقطة إلى آخر تفصيل.").font(.system(size: 14)).foregroundStyle(VTheme.muted)
                }
                Button { store.newProject(); editor = true } label: { newProjectCard }.buttonStyle(.plain).accessibilityIdentifier("newProjectButton")
                HStack(spacing: 10) {
                    quickAction("مونتاج بالذكاء", subtitle: "ChatGPT", symbol: "sparkles", color: VTheme.lavender) { connection = true }
                    quickAction("موشن جاهز", subtitle: "TITLE STUDIO", symbol: "textformat.size", color: VTheme.cyan) { store.newProject(); store.addText("كل لحظة تستحق"); editor = true }
                }
                SectionHeading(title: "مشاريعك", detail: "\(store.entries.count) PROJECTS")
                if store.entries.count > 4 { HStack { Image(systemName: "magnifyingglass").foregroundStyle(VTheme.muted); TextField("ابحث عن مشروع", text: $search) }.padding(14).background(VTheme.surface, in: RoundedRectangle(cornerRadius: 14)) }
                if projects.isEmpty {
                    HStack(spacing: 15) { Image(systemName: "square.stack.3d.up").font(.system(size: 25, weight: .ultraLight)).foregroundStyle(VTheme.muted); VStack(alignment: .leading, spacing: 5) { Text("مساحة لقصتك القادمة").font(.system(size: 14, weight: .medium)); Text("مشاريعك تُحفظ تلقائيًا وتظهر هنا.").font(.system(size: 11)).foregroundStyle(VTheme.muted) }; Spacer() }.padding(20).background(VTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 22) {
                    ForEach(projects) { entry in
                        Button { store.open(entry.id); editor = true } label: { ProjectCard(entry: entry) }.buttonStyle(.plain)
                    }
                }
                HStack { Rectangle().fill(VTheme.line).frame(height: 1); Text("MADE TO CREATE").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(3).foregroundStyle(VTheme.muted); Rectangle().fill(VTheme.line).frame(height: 1) }.padding(.vertical, 10)
            }.padding(.horizontal, 22).padding(.top, 15).padding(.bottom, 25)
        }.background(VTheme.background).fullScreenCover(isPresented: $editor, onDismiss: { store.refreshEntries() }) { EditorView() }
            .sheet(isPresented: $connection) { ConnectionPanel() }
            .onAppear { store.refreshEntries(); if ProcessInfo.processInfo.arguments.contains("--screenshot-editor") { store.loadShowcase(); editor = true }; if ProcessInfo.processInfo.arguments.contains("--screenshot-ai") { connection = true } }
    }
    private var newProjectCard: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 27).fill(VTheme.mint)
            GeometryReader { geo in
                ZStack {
                    RoundedRectangle(cornerRadius: 15).stroke(VTheme.ink.opacity(0.15), lineWidth: 1).frame(width: 112, height: 164).rotationEffect(.degrees(18)).offset(x: 47, y: -7)
                    RoundedRectangle(cornerRadius: 15).fill(VTheme.ink).frame(width: 112, height: 164).overlay(Image(systemName: "play.fill").font(.system(size: 34)).foregroundStyle(VTheme.mint)).rotationEffect(.degrees(9))
                    Capsule().fill(VTheme.ink.opacity(0.25)).frame(width: 84, height: 4).offset(y: 65).rotationEffect(.degrees(9))
                }.position(x: geo.size.width - 64, y: 97)
            }.clipped()
            VStack(alignment: .leading, spacing: 12) {
                Text("YOUR NEXT CUT").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(2)
                Text("اصنع شيئًا\nيستحق المشاهدة.").font(.system(size: 26, weight: .bold)).lineSpacing(1)
                HStack(spacing: 9) { Image(systemName: "plus").font(.system(size: 15, weight: .semibold)); Text("مشروع جديد").font(.system(size: 14, weight: .bold)) }.padding(.horizontal, 15).padding(.vertical, 12).background(VTheme.ink, in: Capsule()).foregroundStyle(.white)
            }.foregroundStyle(VTheme.ink).padding(23)
        }.frame(height: 222)
    }
    private func quickAction(_ title: String, subtitle: String, symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) { VStack(alignment: .leading, spacing: 14) {
            HStack { Image(systemName: symbol).foregroundStyle(color).font(.system(size: 21)); Spacer(); Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(VTheme.muted) }
            VStack(alignment: .leading, spacing: 5) { Text(title).font(.system(size: 14, weight: .semibold)); Text(subtitle).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(VTheme.muted) }
        }.padding(17).frame(maxWidth: .infinity, alignment: .leading).background(VTheme.surface, in: RoundedRectangle(cornerRadius: 20)).overlay(RoundedRectangle(cornerRadius: 20).stroke(VTheme.line)) }.buttonStyle(.plain)
    }
}
struct ProjectCard: View {
    var entry: ProjectEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                MediaThumbnail(url: entry.coverURL, symbol: "square.stack.3d.up").frame(height: 128)
                LinearGradient(colors: [.clear,.black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                HStack { Text(clockLabel(entry.duration)).font(.system(size: 10, weight: .medium, design: .monospaced)); Spacer(); Image(systemName: "arrow.up.right").font(.system(size: 12)) }.padding(12)
            }.frame(height: 128).clipShape(RoundedRectangle(cornerRadius: 17))
            Text(entry.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
            Text(entry.updated, style: .relative).font(.system(size: 11)).foregroundStyle(VTheme.muted)
        }
    }
}
enum EditorSheet: String, Identifiable {
    case inspector, motion, titles, assistant, connection, export, project
    var id: String { rawValue }
}
struct EditorView: View {
    @EnvironmentObject var store: EditorStore
    @EnvironmentObject var account: ChatGPTAccount
    @Environment(\.dismiss) private var dismiss
    @State private var sheet: EditorSheet?
    @State private var importer = false
    @State private var picked: [PhotosPickerItem] = []
    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                topBar
                preview.frame(maxHeight: .infinity).padding(.horizontal, 14).padding(.top, 4)
                transport.padding(.horizontal, 20).padding(.vertical, 11)
                EditorTimeline().frame(height: min(220, max(148, geo.size.height * 0.26)))
                if store.selectedClip != nil { selectionBar }
                toolsDock
            }.background(VTheme.background)
        }.onAppear {
            if ProcessInfo.processInfo.arguments.contains("--screenshot-motion") { sheet = .motion }
            if ProcessInfo.processInfo.arguments.contains("--render-smoke") {
                Task {
                    await store.export()
                    let output: [String: Any] = ["success": store.exportURL != nil, "error": store.error ?? "", "path": store.exportURL?.path ?? ""]
                    if let bytes = try? JSONSerialization.data(withJSONObject: output) {try? bytes.write(to: store.directory.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("smoke-result.json"))}
                }
            }
        }.sheet(item: $sheet) { item in
            Group {
                switch item {
                case .inspector: InspectorPanel()
                case .motion: MotionPanel()
                case .titles: TitleStudio()
                case .assistant: AssistantPanel()
                case .connection: ConnectionPanel()
                case .export: ExportPanel()
                case .project: SettingsPanel()
                }
            }.presentationDetents([.medium,.large]).presentationDragIndicator(.visible).presentationCornerRadius(28)
        }
        .fileImporter(isPresented: $importer, allowedContentTypes: [.movie,.audio,.image,.data], allowsMultipleSelection: true) { result in
            switch result { case .success(let urls): Task { await store.importFiles(urls) }; case .failure(let e): store.error = e.localizedDescription }
        }
        .onChange(of: picked) { _, items in Task { await importPhotos(items); picked = [] } }
        .onChange(of: store.pendingPlan?.summary) { _, summary in if summary != nil { sheet = .assistant } }
        .overlay { if store.isBusy && sheet == nil { BusyOverlay(title: store.status) } }
        .alert("vidioi", isPresented: Binding(get: { store.error != nil && sheet == nil }, set: { if !$0 { store.error = nil } })) { Button("حسنًا") { store.error = nil } } message: { Text(store.error ?? "") }
    }
    private var topBar: some View {
        HStack(spacing: 12) {
            IconButton(symbol: "chevron.left", label: "العودة للمشاريع") { store.player.pause(); dismiss() }
            VStack(alignment: .leading, spacing: 3) { Text(store.project.title).font(.system(size: 14, weight: .semibold)).lineLimit(1); Text("\(store.project.width) × \(store.project.height)   ·   \(store.project.fps) FPS").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(VTheme.muted) }
            Spacer(minLength: 3)
            Button { sheet = .export } label: { HStack(spacing: 7) { Text("تصدير"); Image(systemName: "arrow.up.right") }.font(.system(size: 12, weight: .bold)).padding(.horizontal, 16).frame(height: 39).foregroundStyle(VTheme.ink).background(VTheme.mint, in: Capsule()) }.disabled(store.project.clips.isEmpty).accessibilityIdentifier("exportButton")
        }.padding(.horizontal, 15).padding(.vertical, 10)
    }
    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20).fill(Color.black)
            if store.project.clips.isEmpty {
                VStack(spacing: 17) {
                    ZStack { RoundedRectangle(cornerRadius: 20).stroke(VTheme.line, lineWidth: 1).frame(width: 82,height: 103).rotationEffect(.degrees(-9)); Image(systemName: "plus.rectangle.on.rectangle").font(.system(size: 36, weight: .ultraLight)).foregroundStyle(VTheme.mint) }
                    Text("ابدأ بلقطة").font(.system(size: 22, weight: .bold))
                    Text("أضف فيديو أو صورة لتبدأ المونتاج").font(.system(size: 12)).foregroundStyle(VTheme.muted)
                    PhotosPicker(selection: $picked, maxSelectionCount: 20, matching: .any(of: [.videos,.images])) { Text("من الصور") }.buttonStyle(VButton(prominent: true))
                    Button("استيراد من الملفات") { importer = true }.font(.caption).foregroundStyle(VTheme.muted)
                }
            } else { CleanPlayer(player: store.player).clipShape(RoundedRectangle(cornerRadius: 18)) }
        }.overlay(alignment: .topTrailing) {
            if !store.project.clips.isEmpty { Button { sheet = .project } label: { Text(store.project.width > store.project.height ? "16:9" : store.project.width == store.project.height ? "1:1" : "9:16").font(.system(size: 10, weight: .bold, design: .monospaced)).padding(9).background(.ultraThinMaterial, in: Capsule()) }.padding(12).foregroundStyle(.white) }
        }
    }
    private var transport: some View {
        HStack(spacing: 17) {
            Text(clockLabel(store.playhead)).foregroundStyle(.white) + Text(" / " + clockLabel(store.project.length)).foregroundStyle(VTheme.muted)
            Spacer()
            Button { store.seek(max(0,store.playhead - 1.0 / Double(store.project.fps))) } label: { Image(systemName: "backward.end.fill").font(.system(size: 13)) }
            Button { store.togglePlay() } label: { Image(systemName: store.playing ? "pause.fill" : "play.fill").font(.system(size: 17)).frame(width: 40,height: 32) }.accessibilityIdentifier("playButton")
            Button { store.seek(min(store.project.length,store.playhead + 1.0 / Double(store.project.fps))) } label: { Image(systemName: "forward.end.fill").font(.system(size: 13)) }
            Spacer()
            Button { store.undo() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(!store.canUndo)
            Button { store.redo() } label: { Image(systemName: "arrow.uturn.forward") }.disabled(!store.canRedo)
        }.font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.white)
    }
    private var selectionBar: some View {
        HStack(spacing: 0) {
            Button { store.splitSelected() } label: { Label("تقسيم",systemImage:"scissors") }
            Spacer()
            Button { sheet = .inspector } label: { Label("تعديل",systemImage:"slider.horizontal.3") }.accessibilityIdentifier("inspectorButton")
            Spacer()
            Button { store.duplicateSelected() } label: { Image(systemName: "plus.square.on.square") }
            Spacer()
            Button { store.removeSelected() } label: { Image(systemName: "trash").foregroundStyle(.red.opacity(0.9)) }
        }.font(.system(size: 12,weight:.medium)).foregroundStyle(.white).padding(.horizontal,26).frame(height:44).background(VTheme.surface)
    }
    private var toolsDock: some View {
        HStack(alignment: .top, spacing: 0) {
            dock("وسائط",icon:"plus.square",color:VTheme.mint) { importer = true }
            dock("نص",icon:"textformat",color:.white) { sheet = .titles }
            dock("موشن",icon:"diamond",color:.white) { sheet = .motion }
            dock("تعديل",icon:"slider.horizontal.3",color:.white) { sheet = .inspector }
            dock("AI",icon:"sparkles",color:VTheme.mint) { sheet = .assistant }
        }.padding(.top,16).padding(.bottom,12).background(VTheme.background)
    }
    private func dock(_ text:String,icon:String,color:Color,action:@escaping ()->Void)->some View {
        Button(action:action) { VStack(spacing:8) { Image(systemName:icon).font(.system(size:21,weight:.regular)); Text(text).font(.system(size:10,weight:.medium)) }.foregroundStyle(color).frame(maxWidth:.infinity).frame(height:47) }.accessibilityIdentifier("tool-\(text)")
    }
    private func importPhotos(_ items:[PhotosPickerItem]) async {
        var urls:[URL] = []
        do {
            for item in items {
                if let received = try await item.loadTransferable(type: PickedMedia.self) { urls.append(received.url) }
            }
            await store.importFiles(urls)
        } catch { store.error = error.localizedDescription }
        for url in urls { try? FileManager.default.removeItem(at:url) }
    }
}
struct PickedMedia: Transferable {
    var url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .data) { received in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + received.file.lastPathComponent)
            try FileManager.default.copyItem(at: received.file, to: url)
            return PickedMedia(url: url)
        }
    }
}
struct CleanPlayer: UIViewRepresentable {
    let player: AVPlayer
    final class Surface: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
    func makeUIView(context: Context) -> Surface { let view = Surface(); view.backgroundColor = .black; view.playerLayer.videoGravity = .resizeAspect; view.playerLayer.player = player; return view }
    func updateUIView(_ view: Surface, context: Context) { view.playerLayer.player = player }
}
struct SharePanel: UIViewControllerRepresentable {
    let items:[Any]
    func makeUIViewController(context: Context)->UIActivityViewController { UIActivityViewController(activityItems:items,applicationActivities:nil) }
    func updateUIViewController(_ controller:UIActivityViewController,context:Context) {}
}
