import SwiftUI

struct ClipboardShelfView: View {
    @Bindable var clipboard: ClipboardController
    var onInsert: (ClipboardItem) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Copied")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Spacer()
                if clipboard.isEnabled, !clipboard.store.items.isEmpty {
                    Text("Click to insert")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            if !clipboard.isEnabled {
                emptyWell(symbol: "pause.circle", text: "Clipboard is paused")
            } else if clipboard.store.items.isEmpty {
                emptyWell(symbol: "doc.on.clipboard", text: "Text you copy will appear here")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(clipboard.store.items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Rectangle()
                                .fill(.primary.opacity(0.08))
                                .frame(height: 1)
                                .padding(.horizontal, 11)
                        }
                        ClipboardRow(item: item) {
                            onInsert(item)
                        } onCopy: {
                            clipboard.copy(item)
                        } onDelete: {
                            clipboard.store.delete(item)
                        }
                    }
                }
                .frame(maxHeight: 144)
                .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(.primary.opacity(0.09), lineWidth: 1)
                }
            }
        }
    }

    private func emptyWell(symbol: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
            Text(text)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

private struct ClipboardRow: View {
    let item: ClipboardItem
    let onInsert: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Text(preview)
            .font(.system(size: 11))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 11)
            .frame(height: 28)
            .contentShape(Rectangle())
            .onTapGesture(perform: onInsert)
            .contextMenu {
                Button("Insert", action: onInsert)
                Button("Copy", action: onCopy)
                Divider()
                Button("Delete", role: .destructive, action: onDelete)
            }
            .help("Click to insert into the frontmost app")
    }

    private var preview: String {
        item.text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
    }
}
