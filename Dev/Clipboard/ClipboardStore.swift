import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class ClipboardStore {
    private(set) var items: [ClipboardItem] = []

    private let directory: URL
    private let fileManager: FileManager
    private let maximumItems = 5
    private let maximumCharacters = 50_000

    init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.directory = directory ?? URL.applicationSupportDirectory
            .appending(path: "Dev", directoryHint: .isDirectory)
            .appending(path: "Clipboard", directoryHint: .isDirectory)
        self.fileManager = fileManager
        try? fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: self.directory.path)
        load()
        restrictHistoryFile()
    }

    func record(_ text: String) {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if value.count > maximumCharacters {
            value = String(value.prefix(maximumCharacters))
        }

        if let index = items.firstIndex(where: { $0.text == value }) {
            let existing = items.remove(at: index)
            items.insert(
                ClipboardItem(id: existing.id, text: existing.text, createdAt: .now),
                at: 0
            )
        } else {
            items.insert(
                ClipboardItem(id: UUID(), text: value, createdAt: .now),
                at: 0
            )
            if items.count > maximumItems {
                items = Array(items.prefix(maximumItems))
            }
        }
        save()
    }

    func delete(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        items = []
        save()
    }

    func copy(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)
    }

    private var fileURL: URL {
        directory.appending(path: "history.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let stored = try? JSONDecoder().decode([ClipboardItem].self, from: data) else {
            items = []
            return
        }
        items = Array(stored.prefix(maximumItems))
    }

    private func save() {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let data = try JSONEncoder().encode(items)
            try data.write(to: fileURL, options: .atomic)
            restrictHistoryFile()
        } catch {
            // Keep the in-memory list if the file cannot be written.
        }
    }

    private func restrictHistoryFile() {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
