import XCTest
@testable import InfinityFlow

final class InfinityFlowTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testHoldStartsAndReleaseStops() {
        var ptt = HoldToTalk()
        XCTAssertEqual(ptt.keyDown(at: t0), .start)
        XCTAssertEqual(ptt.keyDown(at: t0 + 0.1), .none, "key repeat is ignored")
        XCTAssertEqual(ptt.keyUp(at: t0 + 1.5), .stop)
        XCTAssertFalse(ptt.isActive)
        XCTAssertEqual(ptt.keyUp(at: t0 + 2), .none, "release without press is ignored")
    }

    func testShortTapWithoutSecondPressIsDismissed() {
        var ptt = HoldToTalk()
        _ = ptt.keyDown(at: t0)
        XCTAssertEqual(ptt.keyUp(at: t0 + 0.2), .none, "keeps listening for a second press")
        XCTAssertTrue(ptt.isActive)
        XCTAssertEqual(ptt.timeout(at: t0 + 0.5), .none, "window not over yet")
        XCTAssertEqual(ptt.timeout(at: t0 + 0.7), .cancel)
        XCTAssertFalse(ptt.isActive)
    }

    func testDoubleTapLocksHandsFreeAndNextPressStops() {
        var ptt = HoldToTalk()
        _ = ptt.keyDown(at: t0)
        _ = ptt.keyUp(at: t0 + 0.15)
        XCTAssertEqual(ptt.keyDown(at: t0 + 0.3), .lock)
        XCTAssertTrue(ptt.isLocked)
        XCTAssertEqual(ptt.keyUp(at: t0 + 0.4), .none, "release is ignored while locked")
        XCTAssertEqual(ptt.timeout(at: t0 + 5), .none)
        XCTAssertEqual(ptt.keyDown(at: t0 + 12), .stop)
        XCTAssertFalse(ptt.isActive)
    }

    func testQuickTripleTapDismisses() {
        var ptt = HoldToTalk()
        _ = ptt.keyDown(at: t0)
        _ = ptt.keyUp(at: t0 + 0.1)
        _ = ptt.keyDown(at: t0 + 0.2)
        _ = ptt.keyUp(at: t0 + 0.25)
        XCTAssertEqual(ptt.keyDown(at: t0 + 0.4), .cancel)
    }

    func testMirroredBars() {
        let bars = AudioLevel.bars(from: [0.1, 0.2, 0.3, 0.4, 0.5, 1.0])
        XCTAssertEqual(bars.count, 10)
        XCTAssertEqual(bars[4], 1.0, accuracy: 0.001, "newest level is at the centre")
        XCTAssertEqual(bars[5], 1.0, accuracy: 0.001)
        XCTAssertEqual(bars[0], bars[9], accuracy: 0.001, "symmetric")
        XCTAssertLessThan(bars[0], bars[4])
        XCTAssertEqual(AudioLevel.bars(from: []).count, 10)
    }

    func testAudioLevelMapping() {
        XCTAssertEqual(AudioLevel.normalized(rms: 0), 0)
        XCTAssertEqual(AudioLevel.normalized(rms: 1), 1, accuracy: 0.001)
        XCTAssertEqual(AudioLevel.normalized(rms: 0.0001), 0, "below the floor clamps to 0")
        XCTAssertEqual(AudioLevel.normalized(rms: pow(10, -25.0 / 20)), 0.5, accuracy: 0.01)
        let samples: [Float] = [0.5, -0.5, 0.5, -0.5]
        samples.withUnsafeBufferPointer { XCTAssertEqual(AudioLevel.rms($0), 0.5, accuracy: 0.0001) }
    }

    func testTranscriptCleanup() {
        XCTAssertEqual(TranscriptText.clean("  Hello   world \n again "), "Hello world again")
        XCTAssertNil(TranscriptText.clean(" \n\t "))
        XCTAssertEqual(TranscriptText.wordCount("Ship it to beta users"), 5)
    }

    func testMultipartBody() {
        var body = MultipartBody(boundary: "B")
        body.addField("model", "whisper-1")
        body.addFile("file", filename: "a.wav", mimeType: "audio/wav", contents: Data("RIFF".utf8))
        let text = String(decoding: body.finalized(), as: UTF8.self)
        XCTAssertEqual(body.contentType, "multipart/form-data; boundary=B")
        XCTAssertEqual(text, """
        --B\r
        Content-Disposition: form-data; name="model"\r
        \r
        whisper-1\r
        --B\r
        Content-Disposition: form-data; name="file"; filename="a.wav"\r
        Content-Type: audio/wav\r
        \r
        RIFF\r
        --B--\r

        """)
    }

    func testHistoryDateGroups() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 12))!
        let day: TimeInterval = 86_400
        let dates = [now, now - day, now - 3 * day, now - 20 * day, now - 90 * day]
        let groups = DateSection.group(dates, date: { $0 }, now: now, calendar: calendar)
        XCTAssertEqual(groups.map(\.0), [.today, .yesterday, .previous7Days, .previous30Days, .older])
    }
}
