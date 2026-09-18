import XCTest
@testable import DouyinCore

final class LiveResolverTests: XCTestCase {
    func testRoomInputs() throws {
        XCTAssertEqual(try LiveResolver.roomID(from: " 640145788197 \n"), "640145788197")
        XCTAssertEqual(try LiveResolver.roomID(from: "https://live.douyin.com/797085759862?anchor_id=123"), "797085759862")
        XCTAssertEqual(try LiveResolver.roomID(from: "https://www.douyin.com/jingxuan/search/muzi?aid=abc&live_web_rid=640145788197&type=general"), "640145788197")
        XCTAssertEqual(try LiveResolver.roomID(from: "[直播](https://www.douyin.com/search/test?aid=abc\\&live_web_rid=640145788197)"), "640145788197")
        XCTAssertThrowsError(try LiveResolver.roomID(from: "https://douyin.com.evil.example/?live_web_rid=123456"))
        XCTAssertThrowsError(try LiveResolver.roomID(from: "https://www.douyin.com/video/123456789"))
        XCTAssertThrowsError(try LiveResolver.roomID(from: "hello"))
    }
    func testFollowLiveLinks() throws {
        let link = "https://www.douyin.com/follow/live/640145788197?anchor_id=1141722744096457"
        XCTAssertEqual(try LiveResolver.roomID(from: link), "640145788197")
        XCTAssertEqual(try LiveResolver.roomID(from: "[直播](\(link))"), "640145788197")
        XCTAssertEqual(try LiveResolver.roomID(from: "https://douyin.com/follow/live/640145788197/"), "640145788197")
        for invalid in [
            "https://www.douyin.com/follow/live/?anchor_id=1141722744096457",
            "https://www.douyin.com/follow/live/invalid?anchor_id=1141722744096457",
            "https://www.douyin.com/follow/live/640145788197/extra",
            "https://www.douyin.com.evil.example/follow/live/640145788197"
        ] {
            XCTAssertThrowsError(try LiveResolver.roomID(from: invalid), invalid)
        }
    }
    func testEscapedQualityMaps() throws {
        let html = #"<script>push([1,"{\"hls_pull_url_map\":{\"SD2\":\"https://example.com/sd/playlist.m3u8?a=1\u0026b=2\",\"FULL_HD1\":\"https://example.com/full/playlist.m3u8?a=1\u0026b=2\"},\"flv_pull_url\":{\"FULL_HD1\":\"https://example.com/full.flv\"}}"])</script>"#
        let streams = try LiveResolver.streams(in: html)
        XCTAssertEqual(streams.count, 3)
        XCTAssertEqual(streams[0].id, "HLS-FULL_HD1")
        XCTAssertEqual(streams[0].url.absoluteString, "https://example.com/full/playlist.m3u8?a=1&b=2")
        XCTAssertEqual(streams[1].id, "FLV-FULL_HD1")
    }
    func testNoStreamAndUnsafeScheme() throws {
        XCTAssertThrowsError(try LiveResolver.streams(in: "<html>请完成验证</html>"))
        XCTAssertThrowsError(try LiveResolver.streams(in: #"{"hls_pull_url_map":{"HD1":"file:///etc/passwd"}}"#))
    }
    func testFirstRoomMapWins() throws {
        let streams = try LiveResolver.streams(in: #"{"hls_pull_url_map":{"HD1":"https://example.com/actual.m3u8"},"recommendations":[{"hls_pull_url_map":{"HD1":"https://example.com/other.m3u8"}}]}"#)
        XCTAssertEqual(streams.count, 1)
        XCTAssertEqual(streams[0].url.lastPathComponent, "actual.m3u8")
    }
    // Opt-in integration check; ordinary tests work offline.
    func testLiveIntegration() async throws {
        guard let id = ProcessInfo.processInfo.environment["DOUYIN_TEST_ROOM"] else { throw XCTSkip("Set DOUYIN_TEST_ROOM for live integration") }
        let streams = try await LiveResolver.resolve(roomID: id)
        XCTAssertFalse(streams.isEmpty)
        print("Live integration: \(streams.map(\.id).joined(separator: ", "))")
        let (data, response) = try await URLSession.shared.data(from: streams[0].url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("#EXTM3U"))
    }
}
