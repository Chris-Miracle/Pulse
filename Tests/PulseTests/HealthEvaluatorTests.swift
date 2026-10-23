import XCTest
@testable import Pulse

final class HealthEvaluatorTests: XCTestCase {
    func testFirstGoodProbeGoesOnlineSilently() {
        var e = HealthEvaluator(slowLatencyMs: 250)
        XCTAssertEqual(e.record(latencyMs: 20, pathUp: true), .online)
        XCTAssertNil(HealthEvaluator.message(from: .unknown, to: .online, latencyMs: 20))
    }

    func testPathDownIsImmediatelyOffline() {
        var e = HealthEvaluator(slowLatencyMs: 250)
        _ = e.record(latencyMs: 20, pathUp: true)
        XCTAssertEqual(e.record(latencyMs: nil, pathUp: false), .offline)
        XCTAssertEqual(HealthEvaluator.message(from: .online, to: .offline, latencyMs: nil)?.title, "Network down")
    }

    func testSingleFailedProbeIsIgnored() {
        var e = HealthEvaluator(slowLatencyMs: 250)
        _ = e.record(latencyMs: 20, pathUp: true)
        XCTAssertNil(e.record(latencyMs: nil, pathUp: true))
        XCTAssertEqual(e.record(latencyMs: nil, pathUp: true), .offline)
    }

    func testSlowNeedsThreeHighSamples() {
        var e = HealthEvaluator(slowLatencyMs: 250)
        _ = e.record(latencyMs: 20, pathUp: true)
        XCTAssertNil(e.record(latencyMs: 400, pathUp: true))
        XCTAssertNil(e.record(latencyMs: 400, pathUp: true))
        XCTAssertEqual(e.record(latencyMs: 400, pathUp: true), .slow)
    }

    func testOneGoodSampleResetsSlowCount() {
        var e = HealthEvaluator(slowLatencyMs: 250)
        _ = e.record(latencyMs: 20, pathUp: true)
        _ = e.record(latencyMs: 400, pathUp: true)
        _ = e.record(latencyMs: 400, pathUp: true)
        _ = e.record(latencyMs: 30, pathUp: true)
        XCTAssertNil(e.record(latencyMs: 400, pathUp: true))
        XCTAssertEqual(e.status, .online)
    }

    func testRecoveryNeedsTwoGoodSamples() {
        var e = HealthEvaluator(slowLatencyMs: 250)
        _ = e.record(latencyMs: nil, pathUp: false)
        XCTAssertNil(e.record(latencyMs: 30, pathUp: true))
        XCTAssertEqual(e.record(latencyMs: 30, pathUp: true), .online)
        XCTAssertEqual(HealthEvaluator.message(from: .offline, to: .online, latencyMs: 30)?.title, "Back online")
    }

    func testSlowRecoveryMessage() {
        XCTAssertEqual(HealthEvaluator.message(from: .slow, to: .online, latencyMs: 30)?.title, "Network back to normal")
        XCTAssertEqual(HealthEvaluator.message(from: .online, to: .slow, latencyMs: 412)?.body,
                       "Latency is 412 ms. Pages and calls may lag.")
    }
}
