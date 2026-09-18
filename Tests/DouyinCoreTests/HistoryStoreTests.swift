import XCTest
@testable import DouyinCore

final class HistoryStoreTests: XCTestCase {
    func testHistoryDedupNotesAndPersistence() throws {
        let suite = "douyin2mpv.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HistoryStore(defaults: defaults)
        XCTAssertEqual(store.record("640145788197").count, 1)
        _ = store.setNote("路亚日记", for: "640145788197")
        _ = store.record("797085759862")
        let result = store.record("640145788197")
        XCTAssertEqual(result.map(\.id), ["640145788197", "797085759862"])
        XCTAssertEqual(result.first?.note, "路亚日记")
        XCTAssertEqual(HistoryStore(defaults: defaults).load(), result)
        XCTAssertEqual(store.record("https://example.com/signed.m3u8"), result)
        XCTAssertEqual(store.remove("640145788197").map(\.id), ["797085759862"])
    }
    func testMigrationRunsOnlyOnceAndCanClearNote() throws {
        let suite = "douyin2mpv.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HistoryStore(defaults: defaults)
        let input = "https://www.douyin.com/follow/live/640145788197?anchor_id=1141722744096457"
        XCTAssertEqual(store.migrateLastInput(input).first?.id, "640145788197")
        _ = store.setNote("备注", for: "640145788197")
        XCTAssertEqual(store.setNote("", for: "640145788197").first?.note, "")
        _ = store.remove("640145788197")
        XCTAssertTrue(store.migrateLastInput(input).isEmpty)
    }
}
