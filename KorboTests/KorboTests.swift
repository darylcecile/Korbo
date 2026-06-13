import XCTest
@testable import Korbo

final class KorboTests: XCTestCase {
    func testLocalServerDefault() {
        XCTAssertEqual(ServerConfig.localDefault.baseURL?.absoluteString, "http://127.0.0.1:4096")
    }

    func testEventTypeDecoding() {
        XCTAssertEqual(OCEventType(rawValue: "message.part.delta"), .messagePartDelta)
        XCTAssertEqual(OCEventType(rawValue: "permission.asked"), .permissionAsked)
    }

    // MARK: - BYO sessions

    func testSessionBaseURLAcceptsBareHost() {
        XCTAssertEqual(
            CloudStore.sessionBaseURLString(for: "byo-abc123.cloud.korbo.app"),
            "https://byo-abc123.cloud.korbo.app"
        )
    }

    func testSessionBaseURLRejectsSpoofingAndMalformedHosts() {
        // Userinfo trick whose real host is evil.com — must not leak the token.
        XCTAssertNil(CloudStore.sessionBaseURLString(for: "good.korbo.app@evil.com"))
        XCTAssertNil(CloudStore.sessionBaseURLString(for: "host.korbo.app/path"))
        XCTAssertNil(CloudStore.sessionBaseURLString(for: "https://host.korbo.app"))
        XCTAssertNil(CloudStore.sessionBaseURLString(for: "host.korbo.app:8080"))
        XCTAssertNil(CloudStore.sessionBaseURLString(for: "host.korbo.app?q=1"))
        XCTAssertNil(CloudStore.sessionBaseURLString(for: "no-dot-host"))
        XCTAssertNil(CloudStore.sessionBaseURLString(for: "  "))
    }

    func testCloudSessionStatusLenientDecoding() {
        XCTAssertEqual(CloudSessionStatus(rawValue: "online"), .online)
        // Unknown/absent status falls back to offline for safe connection gating.
        let json = #"{"id":"byo-1","status":"degraded","proxyHost":"byo-1.cloud.korbo.app"}"#
        let session = try! JSONDecoder().decode(CloudSession.self, from: Data(json.utf8))
        XCTAssertEqual(session.status, .offline)
        XCTAssertEqual(session.rawStatus, "degraded")
    }

    func testCloudSessionDisplayNameFallback() {
        let named = CloudSession(id: "byo-1", name: "My Mac", repo: "a/b", status: .online,
                                 proxyHost: "byo-1.cloud.korbo.app", createdAt: nil, lastHeartbeat: nil)
        XCTAssertEqual(named.displayName, "My Mac")
        let repoOnly = CloudSession(id: "byo-1", name: nil, repo: "owner/repo", status: .online,
                                    proxyHost: "byo-1.cloud.korbo.app", createdAt: nil, lastHeartbeat: nil)
        XCTAssertEqual(repoOnly.displayName, "owner/repo")
        let bare = CloudSession(id: "byo-abcdef", name: nil, repo: nil, status: .offline,
                                proxyHost: "byo-abcdef.cloud.korbo.app", createdAt: nil, lastHeartbeat: nil)
        XCTAssertEqual(bare.displayName, "Session abcdef")
    }
}
