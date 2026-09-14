import AppKit
import Observation
import SwiftUI

@MainActor
final class ScreenshotEditorController: NSObject, NSWindowDelegate {
    private var windows: [UUID: NSWindow] = [:]

    func open(item: ScreenshotItem, library: ScreenshotLibrary) {
        if let window = windows[item.id] {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        guard let image = library.editingImage(for: item) else { return }
        let model = ScreenshotEditorModel(
            item: item,
            image: image,
            annotations: library.annotations(for: item)
        )
        let view = ScreenshotEditorView(
            model: model,
            onCancel: { [weak self] in self?.close(item.id) },
            onSave: { [weak self] in
                do {
                    try library.saveAnnotations(model.annotations, for: item)
                    self?.close(item.id)
                } catch {
                    model.errorMessage = error.localizedDescription
                }
            }
        )
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.title = "Annotate Screenshot"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 820, height: 620))
        window.minSize = NSSize(width: 560, height: 420)
        window.center()
        window.delegate = self
        window.identifier = NSUserInterfaceItemIdentifier(item.id.uuidString)
        windows[item.id] = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let raw = window.identifier?.rawValue,
              let id = UUID(uuidString: raw) else { return }
        windows[id] = nil
    }

    private func close(_ id: UUID) {
        windows[id]?.close()
        windows[id] = nil
    }
}

@MainActor
@Observable
final class ScreenshotEditorModel {
    let item: ScreenshotItem
    let image: NSImage
    var annotations: [ScreenshotAnnotation]
    var draftAnnotation: ScreenshotAnnotation?
    var selectedTool: AnnotationTool = .rectangle
    var selectedID: UUID?
    var color: AnnotationColor = .fault
    var lineWidth: Double = 3
    var isEnteringText = false
    var pendingTextPoint: CGPoint?
    var textDraft = ""
    var errorMessage: String?
    private var undoStack: [[ScreenshotAnnotation]] = []
    private var redoStack: [[ScreenshotAnnotation]] = []

    init(item: ScreenshotItem, image: NSImage, annotations: [ScreenshotAnnotation]) {
        self.item = item
        self.image = image
        self.annotations = annotations
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func commit(_ annotation: ScreenshotAnnotation) {
        recordUndo()
        annotations.append(annotation)
        selectedID = annotation.id
    }

    func beginMutation() { recordUndo() }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previous
        selectedID = nil
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
        selectedID = nil
    }

    func clear() {
        guard !annotations.isEmpty else { return }
        recordUndo()
        annotations.removeAll()
        draftAnnotation = nil
        selectedID = nil
    }

    func deleteSelection() {
        guard let selectedID, annotations.contains(where: { $0.id == selectedID }) else { return }
        recordUndo()
        annotations.removeAll { $0.id == selectedID }
        self.selectedID = nil
    }

    func commitText() {
        let value = textDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        defer {
            textDraft = ""
            pendingTextPoint = nil
            isEnteringText = false
        }
        guard !value.isEmpty, let point = pendingTextPoint else { return }
        commit(ScreenshotAnnotation(
            kind: .text,
            points: [point],
            text: value,
            color: color,
            lineWidth: lineWidth
        ))
    }

    private func recordUndo() {
        undoStack.append(annotations)
        if undoStack.count > 50 { undoStack.removeFirst() }
        redoStack.removeAll()
    }
}
