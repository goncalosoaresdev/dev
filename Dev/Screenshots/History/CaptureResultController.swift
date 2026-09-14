import AppKit
import SwiftUI

@MainActor
final class CaptureResultController {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    func show(item: ScreenshotItem, on screen: NSScreen?, onEdit: @escaping @MainActor () -> Void) {
        dismiss()
        let hosting = NSHostingView(rootView: CaptureResultView(
            item: item,
            onEdit: { [weak self] in
                self?.dismiss()
                onEdit()
            },
            onDismiss: { [weak self] in self?.dismiss() }
        ))
        let panel = CaptureResultPanel(
            contentRect: NSRect(x: 0, y: 0, width: 286, height: 116),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.contentView = hosting
        let visible = screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        panel.setFrameOrigin(NSPoint(x: visible.maxX - 302, y: visible.minY + 18))
        panel.orderFrontRegardless()
        self.panel = panel

        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

private final class CaptureResultPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct CaptureResultView: View {
    let item: ScreenshotItem
    let onEdit: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let image = NSImage(contentsOf: item.url) {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo")
                }
            }
            .frame(width: 112, height: 80)
            .background(.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.primary.opacity(0.1), lineWidth: 1)
            }
            .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
            .help("Drag this screenshot anywhere")

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Screenshot copied")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Spacer()
                    Button(action: onDismiss) { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                Text("Drag it now, or add markup")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Button(action: onEdit) {
                    Label("Annotate", systemImage: "pencil.tip.crop.circle")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 27)
                        .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.primary.opacity(0.09), lineWidth: 1)
        }
    }
}
