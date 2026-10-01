import SwiftUI
import AVFoundation
import CoreText
import UniformTypeIdentifiers

struct ProjectEntry: Identifiable {
    let id: UUID
    let title: String
    let updated: Date
}
@MainActor final class EditorStore: ObservableObject {
    @Published var project = EditProject()
    @Published var selected: UUID?
    @Published var entries: [ProjectEntry] = []
    @Published var isBusy = false
    @Published var status = ""
    @Published var error: String?
    @Published var playhead = 0.0
    @Published var playing = false
    @Published var pendingPlan: EditPlan?
    @Published var exportURL: URL?
    @Published var fonts: [String] = ["Arial-BoldMT", "GeezaPro", "HelveticaNeue-Bold"]
    let player = AVPlayer()
    private var undoStack: [EditProject] = []
    private var redoStack: [EditProject] = []
    private var previewTask: Task<Void, Never>?
    private var observer: Any?
    private var revision = 0
    private let root: URL
    var directory: URL { root.appendingPathComponent(project.id.uuidString, isDirectory: true) }
    var assets: URL { directory.appendingPathComponent("Assets", isDirectory: true) }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var selectedClip: Clip? { project.clips.first { $0.id == selected } }
    init() {
        root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Projects", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                self?.playhead = time.seconds.isFinite ? time.seconds : 0
                self?.playing = self?.player.rate != 0
            }
        }
        refreshEntries()
        if let entry = entries.first { open(entry.id) } else { newProject() }
    }
    func refreshEntries() {
        entries = ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []).compactMap { folder in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("project.json")),
                  let p = try? JSONDecoder().decode(EditProject.self, from: data) else { return nil }
            let date = (try? folder.appendingPathComponent("project.json").resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return ProjectEntry(id: p.id, title: p.title, updated: date)
        }.sorted { $0.updated > $1.updated }
    }
    func newProject() {
        previewTask?.cancel(); player.pause(); player.replaceCurrentItem(with: nil)
        project = EditProject(); selected = nil; undoStack = []; redoStack = []; playhead = 0
        do { try save() } catch { self.error = error.localizedDescription }
        refreshEntries()
    }
    func open(_ id: UUID) {
        guard !isBusy else { return }
        do {
            let data = try Data(contentsOf: root.appendingPathComponent(id.uuidString).appendingPathComponent("project.json"))
            let loaded = try JSONDecoder().decode(EditProject.self, from: data)
            try loaded.validate(); project = loaded; selected = nil; undoStack = []; redoStack = []
            playhead = 0; registerSavedFonts(); schedulePreview()
        } catch { self.error = error.localizedDescription }
    }
    private func save() throws {
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(project).write(to: directory.appendingPathComponent("project.json"), options: .atomic)
    }
    func change(_ edit: (inout EditProject) throws -> Void) {
        guard !isBusy else { return }
        do {
            var next = project; try edit(&next); try next.validate()
            guard next != project else { return }
            let previous = project; project = next
            do { try save() } catch { project = previous; throw error }
            undoStack.append(previous); if undoStack.count > 50 { undoStack.removeFirst() }
            redoStack.removeAll(); schedulePreview()
        } catch { self.error = error.localizedDescription }
    }
    func updateSelected(_ edit: (inout Clip) -> Void) {
        guard let selected else { return }
        change { p in if let i = p.clips.firstIndex(where: { $0.id == selected }) { edit(&p.clips[i]) } }
    }
    func undo() { navigateHistory(undo: true) }
    func redo() { navigateHistory(undo: false) }
    private func navigateHistory(undo: Bool) {
        guard !isBusy, let next = undo ? undoStack.last : redoStack.last else { return }
        let previous = project; project = next
        do {
            try save()
            if undo { undoStack.removeLast(); redoStack.append(previous) } else { redoStack.removeLast(); undoStack.append(previous) }
            if !project.clips.contains(where: { $0.id == selected }) { selected = nil }
            schedulePreview()
        } catch { project = previous; self.error = error.localizedDescription }
    }
    func seek(_ seconds: Double) {
        playhead = min(project.length, max(0, seconds))
        player.seek(to: CMTime(seconds: playhead, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    func togglePlay() {
        if player.rate == 0 { if playhead >= project.length - 0.1 { seek(0) }; player.play() } else { player.pause() }
    }
    private func schedulePreview() {
        revision += 1; let token = revision
        previewTask?.cancel(); player.pause()
        let snapshot = project; let folder = assets
        guard !snapshot.clips.isEmpty else { player.replaceCurrentItem(with: nil); return }
        previewTask = Task {
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
                let product = try await RenderEngine.build(snapshot, assets: folder)
                try Task.checkCancellation()
                guard revision == token else { return }
                player.replaceCurrentItem(with: product.playerItem()); seek(playhead)
            } catch is CancellationError {} catch { if revision == token { self.error = error.localizedDescription } }
        }
    }
    func addText(_ text: String = "اكتب النص هنا") {
        var c = Clip(kind: .text, name: text); c.text = text; c.start = playhead
        c.lane = min(31, (project.clips.map(\.lane).max() ?? 0) + 1)
        c.style.y = 0.75; c.style.motion = .pop
        change { $0.clips.append(c) }; selected = c.id
    }
    func addHadithCard() {
        addText("قال رسول الله ﷺ\nاكتب الحديث الصحيح ومصدره")
        updateSelected { $0.duration = 5; $0.style.y = 0.35; $0.style.fontSize = 66; $0.style.color = "#E6C46B"; $0.style.motion = .fade }
    }
    func removeSelected() {
        guard let selected else { return }; change { $0.clips.removeAll { $0.id == selected } }; self.selected = nil
    }
    func duplicateSelected() {
        guard var c = selectedClip else { return }; c.id = UUID(); c.start = c.end
        change { $0.clips.append(c) }; selected = c.id
    }
    func splitSelected() {
        guard let c = selectedClip else { return }
        let offset = playhead - c.start
        guard offset >= 0.05, c.duration - offset >= 0.05 else { error = "ضع مؤشر الزمن داخل المقطع"; return }
        change { p in
            guard let i = p.clips.firstIndex(where: { $0.id == c.id }) else { return }
            var left = c; var right = c; right.id = UUID(); right.start = playhead
            left.duration = offset; right.duration = c.duration - offset; right.sourceIn += offset * c.speed
            // Insert interpolated boundary values to preserve continuous keyframed motion.
            left.keys = c.keys.filter { $0.time < offset }
            right.keys = c.keys.filter { $0.time > offset }.map { k in var n = k; n.id = UUID(); n.time -= offset; return n }
            for property in Set(c.keys.map(\.property)) {
                let value = c.value(property, at: offset)
                left.keys.append(MotionKey(time: offset, property: property, value: value))
                right.keys.append(MotionKey(time: 0, property: property, value: value))
            }
            p.clips[i] = left; p.clips.append(right)
        }
    }
    func addKey(_ property: AnimatedProperty) {
        guard let c = selectedClip else { return }
        let time = min(c.duration, max(0, playhead - c.start))
        updateSelected {
            $0.keys.removeAll { $0.property == property && abs($0.time - time) < 0.001 }
            $0.keys.append(MotionKey(time: time, property: property, value: c.value(property, at: time)))
        }
    }
    func importFiles(_ urls: [URL]) async {
        guard !isBusy else { return }; isBusy = true; status = "استيراد الملفات"
        defer { isBusy = false; status = "" }
        do {
            var next = project
            for url in urls {
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                let ext = url.pathExtension.lowercased()
                if ext == "json" {
                    pendingPlan = try JSONDecoder().decode(EditPlan.self, from: Data(contentsOf: url)); continue
                }
                if ext == "srt" {
                    next.clips += try Subtitles.parse(String(contentsOf: url, encoding: .utf8), lane: min(31, (next.clips.map(\.lane).max() ?? 0) + 1)); continue
                }
                let name = UUID().uuidString + "." + ext
                let destination = assets.appendingPathComponent(name)
                try FileManager.default.copyItem(at: url, to: destination)
                if ["ttf", "otf"].contains(ext) { registerFont(destination); continue }
                let type = UTType(filenameExtension: ext)
                let kind: MediaKind
                if type?.conforms(to: .movie) == true { kind = .video }
                else if type?.conforms(to: .audio) == true { kind = .audio }
                else if type?.conforms(to: .image) == true { kind = .image }
                else { throw EditError.invalid("صيغة غير مدعومة: \(ext)") }
                var c = Clip(kind: kind, name: url.lastPathComponent, asset: name)
                if kind == .video || kind == .audio {
                    let duration = try await AVURLAsset(url: destination).load(.duration).seconds
                    guard duration.isFinite, duration >= 0.05 else { throw EditError.invalid("ملف بلا مدة صالحة") }
                    c.duration = duration
                }
                if kind == .video { c.start = next.clips.filter { $0.kind == .video && $0.lane == 0 }.map(\.end).max() ?? 0 }
                else { c.start = playhead; c.lane = kind == .audio ? 1 : 2 }
                next.clips.append(c)
            }
            try next.validate()
            isBusy = false
            change { $0 = next }
        } catch { self.error = error.localizedDescription }
    }
    private func registerFont(_ url: URL) {
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] {
            for descriptor in descriptors {
                if let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String, !fonts.contains(name) { fonts.append(name) }
            }
        }
    }
    private func registerSavedFonts() {
        for url in (try? FileManager.default.contentsOfDirectory(at: assets, includingPropertiesForKeys: nil)) ?? [] where ["ttf", "otf"].contains(url.pathExtension.lowercased()) { registerFont(url) }
    }
    func requestPlan(_ prompt: String, endpoint: String, token: String) async {
        guard !isBusy else { return }; isBusy = true; status = "تحليل طلب المونتاج"
        defer { isBusy = false; status = "" }
        do { pendingPlan = try await AIClient.plan(prompt: prompt, project: project, endpoint: endpoint, token: token) }
        catch { self.error = error.localizedDescription }
    }
    func applyPlan() {
        guard let plan = pendingPlan else { return }
        change { $0 = try plan.applying(to: $0) }; pendingPlan = nil
    }
    func export() async {
        guard !isBusy, !project.clips.isEmpty else { return }
        isBusy = true; status = "تصدير الفيديو"; player.pause(); previewTask?.cancel()
        defer { isBusy = false; status = "" }
        do {
            let product = try await RenderEngine.build(project, assets: assets)
            let folder = directory.appendingPathComponent("Exports", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let output = folder.appendingPathComponent("vidioi-\(UUID().uuidString.prefix(8)).mp4")
            try await RenderEngine.export(product, to: output, highResolution: max(project.width, project.height) > 1920)
            exportURL = output
        } catch { self.error = error.localizedDescription }
    }
    func projectJSON() -> URL { directory.appendingPathComponent("project.json") }
}
