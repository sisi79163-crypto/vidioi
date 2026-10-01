import SwiftUI
import AVKit
import UniformTypeIdentifiers

@main struct VidioiApp: App {
    @StateObject private var store = EditorStore()
    var body: some Scene { WindowGroup { EditorView().environmentObject(store).preferredColorScheme(.dark) } }
}
private let accent = Color(red: 0.64, green: 0.44, blue: 1)
struct EditorView: View {
    @EnvironmentObject var store: EditorStore
    @State private var importer = false
    @State private var library = false
    @State private var settings = false
    @State private var tab = 0
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                ZStack {
                    Color.black
                    if store.project.clips.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "film.stack").font(.system(size: 38)).foregroundStyle(accent)
                            Text("ابدأ باستيراد فيديو أو صورة").foregroundStyle(.secondary)
                            Button("استيراد ملفات") { importer = true }.buttonStyle(.borderedProminent).tint(accent)
                        }
                    } else {
                        VideoPlayer(player: store.player).aspectRatio(CGFloat(store.project.width) / CGFloat(store.project.height), contentMode: .fit)
                    }
                }.frame(maxWidth: .infinity).frame(height: 280)
                transport
                TimelinePanel()
                HStack {
                    tabButton("الطبقات", icon: "square.3.layers.3d", index: 0)
                    tabButton("خصائص", icon: "slider.horizontal.3", index: 1)
                    tabButton("الموشن", icon: "sparkles.rectangle.stack", index: 2)
                    tabButton("AI", icon: "wand.and.stars", index: 3)
                }.padding(.vertical, 10)
                Group {
                    switch tab {
                    case 1: InspectorPanel()
                    case 2: MotionPanel()
                    case 3: AssistantPanel()
                    default: layerPanel
                    }
                }.frame(maxHeight: .infinity)
            }
            .background(Color(red: 0.055, green: 0.06, blue: 0.085))
            .toolbar(.hidden, for: .navigationBar)
            .overlay { if store.isBusy { ZStack { Color.black.opacity(0.65).ignoresSafeArea(); VStack(spacing: 14) { ProgressView(); Text(store.status) }.padding(30).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20)) } } }
            .fileImporter(isPresented: $importer, allowedContentTypes: [.movie, .audio, .image, .data], allowsMultipleSelection: true) { result in
                switch result { case .success(let urls): Task { await store.importFiles(urls) }; case .failure(let e): store.error = e.localizedDescription }
            }
            .sheet(isPresented: $library) { ProjectLibrary().environmentObject(store) }
            .sheet(isPresented: $settings) { SettingsPanel().environmentObject(store) }
            .sheet(isPresented: Binding(get: { store.pendingPlan != nil }, set: { if !$0 { store.pendingPlan = nil } })) { PlanReview().environmentObject(store) }
            .sheet(isPresented: Binding(get: { store.exportURL != nil }, set: { if !$0 { store.exportURL = nil } })) {
                if let url = store.exportURL { SharePanel(items: [url]) }
            }
            .alert("vidioi", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("حسنًا") { store.error = nil } } message: { Text(store.error ?? "") }
        }.tint(accent)
    }
    private var header: some View {
        HStack {
            Button { store.refreshEntries(); library = true } label: { Image(systemName: "folder") }
            VStack(alignment: .leading, spacing: 2) {
                Text("vidioi").font(.system(size: 25, weight: .black, design: .rounded)).tracking(-1)
                Text(store.project.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button { settings = true } label: { Image(systemName: "gearshape") }
            Button { Task { await store.export() } } label: { Label("تصدير", systemImage: "square.and.arrow.up").font(.caption.bold()) }
                .buttonStyle(.borderedProminent).disabled(store.project.clips.isEmpty || store.isBusy)
        }.padding(.horizontal, 16).padding(.vertical, 10)
    }
    private var transport: some View {
        HStack(spacing: 22) {
            Button { store.undo() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(!store.canUndo)
            Button { store.redo() } label: { Image(systemName: "arrow.uturn.forward") }.disabled(!store.canRedo)
            Spacer()
            Text(String(format: "%.1f / %.1f s", store.playhead, store.project.length)).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            Button { store.togglePlay() } label: { Image(systemName: store.playing ? "pause.fill" : "play.fill") }
        }.padding(12)
    }
    private func tabButton(_ title: String, icon: String, index: Int) -> some View {
        Button { tab = index } label: {
            VStack(spacing: 5) { Image(systemName: icon); Text(title).font(.caption2) }.frame(maxWidth: .infinity).foregroundStyle(tab == index ? accent : .secondary)
        }
    }
    private var layerPanel: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack {
                    Button { importer = true } label: { Label("ملفات", systemImage: "plus") }
                    Button { store.addText(); tab = 1 } label: { Label("نص", systemImage: "textformat") }
                    Button { store.addHadithCard(); tab = 1 } label: { Label("بطاقة حديث", systemImage: "text.book.closed") }
                }.buttonStyle(.bordered).font(.caption)
                ForEach(store.project.clips.sorted { $0.lane > $1.lane }) { clip in
                    Button { store.selected = clip.id; store.seek(clip.start); tab = 1 } label: {
                        HStack {
                            Image(systemName: clip.kind.icon).foregroundStyle(clip.kind.tint)
                            VStack(alignment: .leading) { Text(clip.name).lineLimit(1); Text("L\(clip.lane) · \(clip.start, specifier: "%.1f")s · \(clip.duration, specifier: "%.1f")s").font(.caption).foregroundStyle(.secondary) }
                            Spacer(); if store.selected == clip.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(accent) }
                        }.padding(12).background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                }
                Text("فيديو · صوت · صور · PNG · خطوط TTF/OTF · ترجمة SRT · أوامر JSON").font(.caption2).foregroundStyle(.secondary)
            }.padding(.horizontal, 14).padding(.bottom, 20)
        }
    }
}
extension MediaKind {
    var icon: String { switch self { case .video: return "film"; case .audio: return "waveform"; case .image: return "photo"; case .text: return "textformat" } }
    var tint: Color { switch self { case .video: return accent; case .audio: return .mint; case .image: return .orange; case .text: return .cyan } }
}
struct TimelinePanel: View {
    @EnvironmentObject var store: EditorStore
    @State private var pixelsPerSecond = 32.0
    private var lanes: [Int] { Array(Set(store.project.clips.map(\.lane))).sorted(by: >) }
    var body: some View {
        VStack(spacing: 5) {
            Slider(value: Binding(get: { store.playhead }, set: { store.seek($0) }), in: 0...max(0.1, store.project.length)).padding(.horizontal, 14)
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 0) { ForEach(0...Int(ceil(store.project.length)), id: \.self) { second in Text("\(second)s").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).frame(width: pixelsPerSecond, alignment: .leading) } }
                    ForEach(lanes, id: \.self) { lane in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.025))
                            ForEach(store.project.clips.filter { $0.lane == lane }) { clip in
                                Button { store.selected = clip.id; store.seek(clip.start) } label: {
                                    HStack(spacing: 3) { Image(systemName: clip.kind.icon); Text(clip.name).lineLimit(1) }
                                        .font(.system(size: 10, weight: .semibold)).padding(.horizontal, 5)
                                        .frame(width: max(10, clip.duration * pixelsPerSecond), height: 30, alignment: .leading)
                                        .background(clip.kind.tint.opacity(0.45), in: RoundedRectangle(cornerRadius: 5))
                                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(store.selected == clip.id ? .white : .clear, lineWidth: 2))
                                }.buttonStyle(.plain).offset(x: clip.start * pixelsPerSecond)
                            }
                        }.frame(width: max(350, store.project.length * pixelsPerSecond + pixelsPerSecond), height: 32)
                    }
                }.overlay(alignment: .topLeading) { Rectangle().fill(Color.white).frame(width: 1).offset(x: store.playhead * pixelsPerSecond).allowsHitTesting(false) }.padding(.horizontal, 12)
            }.frame(height: 108)
        }.environment(\.layoutDirection, .leftToRight)
    }
}
struct InspectorPanel: View {
    @EnvironmentObject var store: EditorStore
    var body: some View {
        if let clip = store.selectedClip {
            ScrollView {
                VStack(spacing: 13) {
                    HStack { Text(clip.name).lineLimit(1).font(.headline); Spacer(); Button("تقسيم") { store.splitSelected() }; Button { store.duplicateSelected() } label: { Image(systemName: "plus.square.on.square") }; Button(role: .destructive) { store.removeSelected() } label: { Image(systemName: "trash") } }.font(.caption)
                    if clip.kind == .text {
                        TextField("النص", text: Binding(get: { store.selectedClip?.text ?? "" }, set: { value in store.updateSelected { $0.text = value; $0.name = String(value.prefix(30)) } }), axis: .vertical).textFieldStyle(.roundedBorder)
                        Picker("الخط", selection: Binding(get: { store.selectedClip?.style.fontName ?? "Arial-BoldMT" }, set: { name in store.updateSelected { $0.style.fontName = name } })) { ForEach(store.fonts, id: \.self) { Text($0).tag($0) } }
                        number("حجم الخط", key: \LayerStyle.fontSize, range: 8...220)
                        HStack { Text("اللون"); Spacer(); ForEach(["#FFFFFF", "#FF3434", "#E6C46B", "#4AE5BD"], id: \.self) { hex in Button { store.updateSelected { $0.style.color = hex } } label: { Circle().fill(Color(hex: hex)).frame(width: 26, height: 26).overlay(Circle().stroke(clip.style.color == hex ? .white : .clear, lineWidth: 2)) } } }
                    }
                    timing("البداية", key: \Clip.start, range: 0...max(60, store.project.length))
                    timing("المدة", key: \Clip.duration, range: 0.05...max(60, clip.duration))
                    if clip.kind == .video || clip.kind == .audio {
                        timing("القص من المصدر", key: \Clip.sourceIn, range: 0...max(60, clip.sourceIn))
                        timing("السرعة", key: \Clip.speed, range: 0.25...4)
                        timing("الصوت", key: \Clip.volume, range: 0...2)
                    }
                    Stepper("الطبقة L\(clip.lane)", value: Binding(get: { store.selectedClip?.lane ?? 0 }, set: { lane in store.updateSelected { $0.lane = lane } }), in: 0...31)
                    if clip.kind != .audio {
                        number("X", key: \LayerStyle.x, range: -0.5...1.5)
                        number("Y", key: \LayerStyle.y, range: -0.5...1.5)
                        number("Scale", key: \LayerStyle.scale, range: 0.05...4)
                        number("Stretch", key: \LayerStyle.stretch, range: 0.1...3)
                        number("الدوران", key: \LayerStyle.rotation, range: -180...180)
                        number("الشفافية", key: \LayerStyle.opacity, range: 0...1)
                        if clip.kind != .text {
                            number("الإضاءة", key: \LayerStyle.brightness, range: -1...1)
                            number("التباين", key: \LayerStyle.contrast, range: 0...3)
                            number("التشبع", key: \LayerStyle.saturation, range: 0...3)
                        }
                    }
                }.font(.caption).padding(14)
            }
        } else { ContentUnavailableView("اختر طبقة", systemImage: "square.3.layers.3d") }
    }
    private func number(_ label: String, key: WritableKeyPath<LayerStyle, Double>, range: ClosedRange<Double>) -> some View {
        NumericSlider(label: label, value: Binding(get: { store.selectedClip?.style[keyPath: key] ?? range.lowerBound }, set: { n in store.updateSelected { $0.style[keyPath: key] = n } }), range: range)
    }
    private func timing(_ label: String, key: WritableKeyPath<Clip, Double>, range: ClosedRange<Double>) -> some View {
        NumericSlider(label: label, value: Binding(get: { store.selectedClip?[keyPath: key] ?? range.lowerBound }, set: { n in store.updateSelected { $0[keyPath: key] = n } }), range: range)
    }
}
struct NumericSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var body: some View {
        VStack(spacing: 2) { HStack { Text(label); Spacer(); TextField("", value: $value, format: .number.precision(.fractionLength(2))).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 75) }; Slider(value: $value, in: range) }
    }
}
struct MotionPanel: View {
    @EnvironmentObject var store: EditorStore
    var body: some View {
        if let clip = store.selectedClip, clip.kind != .audio {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("حركة الدخول").font(.headline)
                    HStack { ForEach(MotionPreset.allCases, id: \.self) { motion in Button(motion.rawValue) { store.updateSelected { $0.style.motion = motion } }.buttonStyle(.bordered).tint(clip.style.motion == motion ? accent : .gray) } }
                    Text("حرّك مؤشر الزمن ثم أضف Keyframe. عدّل قيمته أدناه.").font(.caption).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))]) { ForEach(AnimatedProperty.allCases, id: \.self) { property in Button { store.addKey(property) } label: { Label(property.rawValue, systemImage: "diamond") }.buttonStyle(.bordered).font(.caption) } }
                    ForEach(clip.keys.sorted { $0.time < $1.time }) { key in
                        HStack {
                            Text("\(key.property.rawValue) @ \(key.time, specifier: "%.2f")s").font(.caption)
                            TextField("قيمة", value: Binding(get: { store.selectedClip?.keys.first(where: { $0.id == key.id })?.value ?? key.value }, set: { value in store.updateSelected { c in if let i = c.keys.firstIndex(where: { $0.id == key.id }) { c.keys[i].value = value } } }), format: .number).keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder)
                            Button { store.updateSelected { $0.keys.removeAll { $0.id == key.id } } } label: { Image(systemName: "trash") }
                        }
                    }
                }.padding(14)
            }
        } else { ContentUnavailableView("اختر نصًا أو فيديو أو صورة", systemImage: "diamond") }
    }
}
struct AssistantPanel: View {
    @EnvironmentObject var store: EditorStore
    @AppStorage("aiEndpoint") private var endpoint = ""
    @State private var prompt = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("مساعد vidioi").font(.headline)
                Text("صف التعديل المطلوب. سيرجع المساعد خطة تطبّقها على الطبقات مع إمكانية التراجع.").font(.caption).foregroundStyle(.secondary)
                TextField("كبّر النص الأول واجعله أحمر مع حركة Pop…", text: $prompt, axis: .vertical).lineLimit(3...6).textFieldStyle(.roundedBorder)
                Button { Task { await store.requestPlan(prompt, endpoint: endpoint, token: SecureSettings.token()) } } label: { Label("جهّز التعديلات", systemImage: "wand.and.stars").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isBusy)
                ShareLink(item: store.projectJSON()) { Label("مشاركة بيانات المشروع للمساعد", systemImage: "square.and.arrow.up") }.font(.caption)
                Text("يرسل طلبك وبيانات التايملاين فقط. الملفات الأصلية تبقى على جهازك. يمكنك أيضًا استيراد خطة JSON دون اتصال بالخادم.").font(.caption2).foregroundStyle(.secondary)
            }.padding(14)
        }
    }
}
struct PlanReview: View {
    @EnvironmentObject var store: EditorStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if let plan = store.pendingPlan {
                    Section("الخطة") { Text(plan.summary) }
                    Section("التعديلات") { ForEach(Array(plan.operations.enumerated()), id: \.offset) { _, op in
                        VStack(alignment: .leading) { Text("\(op.action) · \(op.property ?? "")").font(.headline); Text(op.text ?? op.number.map { String($0) } ?? op.clipID ?? "").font(.caption).foregroundStyle(.secondary) }
                    } }
                    Button("تطبيق الخطة") { store.applyPlan(); dismiss() }.disabled(store.isBusy)
                }
            }.navigationTitle("مراجعة المونتاج").toolbar { Button("إلغاء") { store.pendingPlan = nil; dismiss() } }
        }
    }
}
struct SettingsPanel: View {
    @EnvironmentObject var store: EditorStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("aiEndpoint") private var endpoint = ""
    @State private var token = SecureSettings.token()
    @State private var title = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("المشروع") {
                    TextField("الاسم", text: $title).onSubmit { store.change { $0.title = title } }
                    Picker("الإطار", selection: Binding(get: { "\(store.project.width)x\(store.project.height)" }, set: { value in
                        let parts = value.split(separator: "x").compactMap { Int($0) }
                        if parts.count == 2 { store.change { $0.width = parts[0]; $0.height = parts[1] } }
                    })) { Text("9:16 · 1080p").tag("1080x1920"); Text("16:9 · 1080p").tag("1920x1080"); Text("1:1").tag("1080x1080"); Text("9:16 · 4K").tag("2160x3840") }
                    Picker("FPS", selection: Binding(get: { store.project.fps }, set: { fps in store.change { $0.fps = fps } })) { ForEach([24, 25, 30, 60], id: \.self) { Text("\($0)").tag($0) } }
                }
                Section("اتصال الذكاء الاصطناعي") {
                    TextField("https://your-server.example", text: $endpoint).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    SecureField("رمز اتصال الخادم", text: $token)
                    Text("مفتاح OpenAI محفوظ في الخادم. هذا الحقل لرمز اتصال vidioi فقط.").font(.caption)
                }
                Section("النسخة الأولى") { Text("مونتاج محلي وموشن Keyframes. تتبّع الشخص، عزل الخلفية، LUT ثلاثي الأبعاد وتوليد الوسائط ليست مضافة بعد.").font(.caption) }
            }.navigationTitle("الإعدادات").onAppear { title = store.project.title }
                .toolbar { Button("حفظ") {
                    store.change { $0.title = title }
                    do { try SecureSettings.save(token: token); dismiss() } catch { store.error = error.localizedDescription }
                } }
        }
    }
}
struct ProjectLibrary: View {
    @EnvironmentObject var store: EditorStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack { List {
            Button { store.newProject(); dismiss() } label: { Label("مشروع جديد", systemImage: "plus") }
            ForEach(store.entries) { entry in Button { store.open(entry.id); dismiss() } label: { VStack(alignment: .leading) { Text(entry.title); Text(entry.updated, style: .date).font(.caption).foregroundStyle(.secondary) } } }
        }.navigationTitle("مشاريعي").toolbar { Button("إغلاق") { dismiss() } } }
    }
}
struct SharePanel: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
extension Color {
    init(hex: String) {
        let n = UInt32(hex.dropFirst(), radix: 16) ?? 0xFFFFFF
        self.init(red: Double((n >> 16) & 255) / 255, green: Double((n >> 8) & 255) / 255, blue: Double(n & 255) / 255)
    }
}
