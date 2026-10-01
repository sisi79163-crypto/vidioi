import XCTest
@testable import VidioiCore

final class ProjectTests: XCTestCase {
    private func project() -> EditProject {
        var p = EditProject()
        var clip = Clip(kind: .text, name: "عنوان")
        clip.text = "عنوان عربي"; clip.duration = 4
        p.clips = [clip]; return p
    }
    func testAtomicPlanFailurePreservesProject() throws {
        let p = project()
        let plan = EditPlan(summary: "", operations: [
            EditOperation(action: "set", clipID: p.clips[0].id.uuidString, property: "scale", number: 2),
            EditOperation(action: "set", clipID: p.clips[0].id.uuidString, property: "opacity", number: 3)
        ])
        XCTAssertThrowsError(try plan.applying(to: p))
        XCTAssertEqual(p.clips[0].style.scale, 1)
    }
    func testSetAndKeyframeCanBeApplied() throws {
        let p = project(); let id = p.clips[0].id.uuidString
        let plan = EditPlan(summary: "أحمر", operations: [
            EditOperation(action: "set", clipID: id, property: "color", text: "#FF3434"),
            EditOperation(action: "keyframe", clipID: id, property: "scale", number: 1, time: 0),
            EditOperation(action: "keyframe", clipID: id, property: "scale", number: 2, time: 2)
        ])
        let edited = try plan.applying(to: p)
        XCTAssertEqual(edited.clips[0].style.color, "#FF3434")
        XCTAssertEqual(edited.clips[0].value(.scale, at: 1), 1.5, accuracy: 0.0001)
        XCTAssertEqual(edited.clips[0].value(.scale, at: 3), 2)
    }
    func testLargeLaneDoesNotTrap() {
        let p = project()
        let plan = EditPlan(summary: "", operations: [EditOperation(action: "set", clipID: p.clips[0].id.uuidString, property: "lane", number: 1e100)])
        XCTAssertThrowsError(try plan.applying(to: p))
    }
    func testUnknownIDAndAssetTraversalRejected() {
        let p = project()
        let plan = EditPlan(summary: "", operations: [EditOperation(action: "remove", clipID: UUID().uuidString)])
        XCTAssertThrowsError(try plan.applying(to: p))
        var invalid = p; invalid.clips[0].kind = .video; invalid.clips[0].asset = "../private.mp4"
        XCTAssertThrowsError(try invalid.validate())
    }
    func testShorteningClipPastKeyframeFails() {
        var p = project(); p.clips[0].keys = [MotionKey(time: 3, property: .scale, value: 2)]
        let plan = EditPlan(summary: "", operations: [EditOperation(action: "set", clipID: p.clips[0].id.uuidString, property: "duration", number: 2)])
        XCTAssertThrowsError(try plan.applying(to: p))
    }
    func testArabicSRTWithCRLFAndMultiline() throws {
        let clips = try Subtitles.parse("1\r\n00:00:01,250 --> 00:00:03,500\r\nالسلام عليكم\r\nسطر ثانٍ\r\n\r\n2\r\n00:00:04,000 --> 00:00:05,000\r\nنهاية", lane: 3)
        XCTAssertEqual(clips.count, 2)
        XCTAssertEqual(clips[0].start, 1.25)
        XCTAssertEqual(clips[0].duration, 2.25)
        XCTAssertEqual(clips[0].text, "السلام عليكم\nسطر ثانٍ")
        XCTAssertEqual(clips[0].lane, 3)
    }
    func testSRTRejectsReversedTimestamps() {
        XCTAssertThrowsError(try Subtitles.parse("1\n00:00:03,000 --> 00:00:01,000\nكلمة", lane: 2))
    }
    func testProjectCodecRoundtrip() throws {
        let p = project(); let bytes = try JSONEncoder().encode(p)
        XCTAssertEqual(try JSONDecoder().decode(EditProject.self, from: bytes), p)
    }
    func testAddTextAndDuplicateIDValidation() throws {
        let p = project()
        let plan = EditPlan(summary: "نص", operations: [EditOperation(action: "addText", number: 2, text: "صلوا على النبي", time: 5)])
        let edited = try plan.applying(to: p)
        XCTAssertEqual(edited.clips.count, 2); XCTAssertEqual(edited.clips[1].start, 5)
        var invalid = p; invalid.clips.append(p.clips[0]); XCTAssertThrowsError(try invalid.validate())
    }
}
