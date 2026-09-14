import XCTest
@testable import Dev

@MainActor
final class ClipboardStoreTests: XCTestCase {
    func testRecordsNewestFirst() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        store.record("one")
        store.record("two")
        store.record("three")

        XCTAssertEqual(store.items.map(\.text), ["three", "two", "one"])
    }

    func testKeepsOnlyTheLastFive() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        for value in ["one", "two", "three", "four", "five", "six"] {
            store.record(value)
        }

        XCTAssertEqual(store.items.map(\.text), ["six", "five", "four", "three", "two"])
        XCTAssertEqual(store.items.count, 5)
    }

    func testIgnoresEmptyAndWhitespace() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        store.record("")
        store.record("   \n\t  ")
        store.record("kept")

        XCTAssertEqual(store.items.map(\.text), ["kept"])
    }

    func testDuplicateMovesExistingItemToFront() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        store.record("alpha")
        store.record("beta")
        store.record("gamma")
        let originalID = try XCTUnwrap(store.items.first(where: { $0.text == "alpha" })?.id)

        store.record("  alpha  ")

        XCTAssertEqual(store.items.map(\.text), ["alpha", "gamma", "beta"])
        XCTAssertEqual(store.items.first?.id, originalID)
        XCTAssertEqual(store.items.count, 3)
    }

    func testPersistsAcrossStoreInstances() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        store.record("first")
        store.record("second")

        let reloaded = ClipboardStore(directory: directory)
        XCTAssertEqual(reloaded.items.map(\.text), ["second", "first"])
        XCTAssertEqual(reloaded.items.map(\.id), store.items.map(\.id))
    }

    func testClearEmptiesMemoryAndDisk() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        store.record("keep me")
        store.clear()

        XCTAssertTrue(store.items.isEmpty)
        let reloaded = ClipboardStore(directory: directory)
        XCTAssertTrue(reloaded.items.isEmpty)
    }

    func testTruncatesLongText() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        store.record(String(repeating: "a", count: 60_000))

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.text.count, 50_000)
    }

    func testHistoryFileIsOwnerReadableOnly() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        store.record("secret")

        let directoryPermissions = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
        let filePermissions = try FileManager.default.attributesOfItem(
            atPath: directory.appending(path: "history.json").path
        )[.posixPermissions] as? NSNumber
        XCTAssertEqual(directoryPermissions?.uint16Value, 0o700)
        XCTAssertEqual(filePermissions?.uint16Value, 0o600)
    }

    func testCorruptHistoryLoadsAsEmpty() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "DevTests-Clipboard-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: directory.appending(path: "history.json"))

        let store = ClipboardStore(directory: directory)
        XCTAssertTrue(store.items.isEmpty)
    }

    private func makeStore() throws -> (ClipboardStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "DevTests-Clipboard-\(UUID().uuidString)", directoryHint: .isDirectory)
        return (ClipboardStore(directory: directory), directory)
    }
}
