import AppKit
import SwiftUI

@MainActor
final class OverlayController {
    let model = OverlayModel()
    private var panel: NSPanel?
    private var hosting: NSHostingView<OverlayView>?

    func show(status: String, text: String, level: Float, kind: OverlayModel.Kind) {
        if status == "Starting" || status == "Listening" {
            model.startedAt = .now
        }
        model.status = status
        model.text = text
        model.level = level
        model.kind = kind
        model.visible = true
        installIfNeeded()
        position()
        panel?.orderFrontRegardless()
    }

    func setStatus(_ status: String, text: String, level: Float, kind: OverlayModel.Kind) {
        model.status = status
        model.text = text
        model.level = level
        model.kind = kind
        if model.visible {
            position()
        } else {
            show(status: status, text: text, level: level, kind: kind)
        }
    }

    func setLevel(_ level: Float) {
        model.level = level
    }

    func hide() {
        model.visible = false
        panel?.orderOut(nil)
    }

    private func installIfNeeded() {
        if panel != nil { return }

        let view = OverlayView(model: model)
        let hosting = TransparentHostingView(rootView: view)
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.layer?.isOpaque = false
        self.hosting = hosting

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 138, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The window server shadows the panel's rectangular frame rather than
        // the visible capsule. OverlayView supplies a shape-aware pill shadow.
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = hosting
        self.panel = panel
    }

    private func position() {
        guard let panel, let hosting else { return }
        hosting.invalidateIntrinsicContentSize()
        let size = hosting.fittingSize
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let x = screen.midX - size.width / 2
        let y = screen.minY + 28
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }
}

private final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }
}

@MainActor
@Observable
final class OverlayModel {
    enum Kind {
        case live, busy, done, mute, fault
    }

    var visible = false
    var status = "Listening"
    var text = ""
    var level: Float = 0
    var kind: Kind = .live
    var startedAt = Date.now
}
