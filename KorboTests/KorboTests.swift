import XCTest
@testable import Korbo

final class KorboTests: XCTestCase {
    func testLocalServerDefault() {
        XCTAssertEqual(ServerConfig.localDefault.baseURL.absoluteString, "http://127.0.0.1:4096")
    }

    func testEventTypeDecoding() {
        XCTAssertEqual(OCEventType(rawValue: "session.next.text.delta"), .textDelta)
        XCTAssertEqual(OCEventType(rawValue: "permission.asked"), .permissionAsked)
    }
}
