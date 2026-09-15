import SwiftUI

struct ClipboardShelfView: View {
  @Bindable var clipboard: ClipboardController
  var onInsert: (ClipboardItem) -> Void = { _ in }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if !clipboard.isEnabled {
        emptyWell(symbol: "pause.circle", text: "Clipboard is paused")
      } else if clipboard.store.items.isEmpty {
        emptyWell(symbol: "doc.on.clipboard", text: "No copied text yet")
      } else {
        ScrollView {
          VStack(spacing: 5) {
            ForEach(clipboard.store.items) { item in
              ClipboardRow(item: item) {
                onInsert(item)
              } onCopy: {
                clipboard.copy(item)
              } onDelete: {
                clipboard.store.delete(item)
              }
            }
          }
          .padding(1)
        }
        .scrollIndicators(.hidden)
      }
    }
    .padding(.bottom, 12)
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
  @State private var hovering = false
  let item: ClipboardItem
  let onInsert: () -> Void
  let onCopy: () -> Void
  let onDelete: () -> Void

  var body: some View {
    Button(action: onInsert) {
      HStack(spacing: 10) {
        Image(systemName: "text.alignleft")
          .font(.system(size: 13)).foregroundStyle(.secondary)
        VStack(alignment: .leading, spacing: 5) {
          Text(preview)
            .font(.system(size: 12))
            .foregroundStyle(.primary)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Image(systemName: "return")
          .font(.system(size: 11)).foregroundStyle(.secondary)
          .opacity(hovering ? 1 : 0.35)
      }
      .padding(10)
      .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
      .background(.primary.opacity(hovering ? 0.08 : 0.035), in: RoundedRectangle(cornerRadius: 12))
      .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.07)) }
      .contentShape(RoundedRectangle(cornerRadius: 12))
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
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
