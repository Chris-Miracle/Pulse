import XCTest
@testable import Pulse

@MainActor
final class UnitFormattingTests: XCTestCase {
    func testSessionTotalsInBytesAndBits() {
        XCTAssertEqual(NetworkMonitor.formatTotal(1_200_000_000, bits: false), "1.2 GB")
        XCTAssertEqual(NetworkMonitor.formatTotal(1_200_000_000, bits: true), "9.60 Gb")
        XCTAssertEqual(NetworkMonitor.formatTotal(85_000_000, bits: true), "680.0 Mb")
        XCTAssertEqual(NetworkMonitor.formatTotal(17_000, bits: true), "136 Kb")
    }

    func testSpeedTestInBitsAndBytes() {
        XCTAssertEqual(NetworkMonitor.formatSpeed(mbps: 340, bits: true), "340 Mbps")
        XCTAssertEqual(NetworkMonitor.formatSpeed(mbps: 340, bits: false), "42.5 MB/s")
        XCTAssertEqual(NetworkMonitor.formatSpeed(mbps: 10, bits: false), "1.25 MB/s")
        XCTAssertEqual(NetworkMonitor.formatSpeed(mbps: 25.4, bits: true), "25.4 Mbps")
    }

    func testMissingSpeedShowsDash() {
        XCTAssertEqual(NetworkMonitor.speedParts(mbps: nil, bits: false).value, "–")
        XCTAssertEqual(NetworkMonitor.speedParts(mbps: nil, bits: false).unit, "MB/s")
    }

    func testLiveRateMatchesBetweenUnits() {
        // 17 KB/s of live traffic is 136 Kbps
        XCTAssertEqual(NetworkMonitor.format(17_000, bits: false), "17 KB/s")
        XCTAssertEqual(NetworkMonitor.format(17_000, bits: true), "136 Kbps")
    }
}
