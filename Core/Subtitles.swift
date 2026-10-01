import Foundation

enum Subtitles {
    static func parse(_ input: String, lane: Int) throws -> [Clip] {
        let normalized = input.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")
        var clips: [Clip] = []
        for block in blocks {
            let lines = block.components(separatedBy: "\n")
            guard let lineIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let times = lines[lineIndex].components(separatedBy: "-->").map { $0.trimmingCharacters(in: .whitespaces) }
            guard times.count == 2, let start = timestamp(times[0]), let end = timestamp(times[1]), end > start else {
                throw EditError.invalid("توقيت SRT غير صالح")
            }
            let text = lines.dropFirst(lineIndex + 1).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            var c = Clip(kind: .text, name: String(text.prefix(30)))
            c.text = text; c.start = start; c.duration = end - start; c.lane = lane
            c.style.y = 0.78; c.style.fontSize = 72; c.style.motion = .pop
            clips.append(c)
        }
        guard !clips.isEmpty else { throw EditError.invalid("لم يتم العثور على ترجمة SRT") }
        return clips
    }
    private static func timestamp(_ string: String) -> Double? {
        let fields = string.replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard fields.count == 3, let h = Double(fields[0]), let m = Double(fields[1]), let s = Double(fields[2]),
              h >= 0, (0..<60).contains(m), (0..<60).contains(s) else { return nil }
        return h * 3600 + m * 60 + s
    }
}
