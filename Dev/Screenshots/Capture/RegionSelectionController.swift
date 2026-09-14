import AppKit

@MainActor
final class RegionSelectionController {
    struct Selection {
        let screen: NSScreen
        let rect: CGRect
    }

    private var panels: [NSPanel] = []
    private var completion: ((Selection?) -> Void)?

    func begin(completion: @escaping (Selection?) -> Void) {
        cancel()
        self.completion = completion

        for screen in NSScreen.screens {
            let view = RegionSelectionView(screen: screen)
            view.onComplete = { [weak self] rect in
                self?.finish(Selection(screen: screen, rect: rect))
            }
            view.onCancel = { [weak self] in self?.finish(nil) }

            let panel = SelectionPanel(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.hidesOnDeactivate = false
            panel.contentView = view
            panel.setFrame(screen.frame, display: true)
            panels.append(panel)
            panel.orderFrontRegardless()
        }

        NSApp.activate(ignoringOtherApps: true)
        if let panel = panels.first {
            panel.makeKey()
            panel.makeFirstResponder(panel.contentView)
        }
    }

    func cancel() {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        completion = nil
    }

    private func finish(_ selection: Selection?) {
        let callback = completion
        completion = nil
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        callback?(selection)
    }
}

private final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class RegionSelectionView: NSView {
    var onComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private let selectionScreen: NSScreen
    private var startPoint: CGPoint?
    private var selectionRect: CGRect?

    init(screen: NSScreen) {
        selectionScreen = screen
        super.init(frame: CGRect(origin: .zero, size: screen.frame.size))
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        startPoint = convert(event.locationInWindow, from: nil)
        selectionRect = CGRect(origin: startPoint ?? .zero, size: .zero)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startPoint else { return }
        let current = convert(event.locationInWindow, from: nil)
        selectionRect = standardizedRect(from: startPoint, to: current).intersection(bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let startPoint else { return }
        let current = convert(event.locationInWindow, from: nil)
        let rect = standardizedRect(from: startPoint, to: current).intersection(bounds)
        self.startPoint = nil
        guard rect.width >= 4, rect.height >= 4 else {
            selectionRect = nil
            needsDisplay = true
            return
        }
        onComplete?(rect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let mask = NSBezierPath(rect: bounds)
        if let selectionRect {
            mask.appendRect(selectionRect)
            mask.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(0.42).setFill()
        mask.fill()

        guard let selectionRect else { return }
        let outline = NSBezierPath(rect: selectionRect.insetBy(dx: 0.5, dy: 0.5))
        outline.lineWidth = 1
        NSColor.black.withAlphaComponent(0.65).setStroke()
        outline.stroke()

        let inner = NSBezierPath(rect: selectionRect.insetBy(dx: 1.5, dy: 1.5))
        inner.lineWidth = 1
        NSColor.white.withAlphaComponent(0.95).setStroke()
        inner.stroke()

        drawDimensions(for: selectionRect)
    }

    private func drawDimensions(for rect: CGRect) {
        let scale = selectionScreen.backingScaleFactor
        let text = "\(Int((rect.width * scale).rounded())) × \(Int((rect.height * scale).rounded()))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let badge = CGRect(
            x: min(max(rect.midX - size.width / 2 - 7, 6), bounds.maxX - size.width - 20),
            y: max(rect.minY - size.height - 14, 6),
            width: size.width + 14,
            height: size.height + 7
        )
        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: badge, xRadius: 7, yRadius: 7).fill()
        text.draw(
            at: CGPoint(x: badge.minX + 7, y: badge.minY + 3),
            withAttributes: attributes
        )
    }

    private func standardizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }
}
