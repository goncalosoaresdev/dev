import AppKit
import SwiftUI

struct ScreenshotShelfView: View {
    @Bindable var screenshots: ScreenshotController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Screenshots")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Spacer()
                Text("Drag anywhere")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            if case .failed(let message) = screenshots.phase {
                HStack(spacing: 9) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(message)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    if screenshots.failureNeedsScreenRecordingSettings {
                        Button("Open Settings") {
                            screenshots.openScreenRecordingSettings()
                        }
                    } else {
                        Button("Dismiss") {
                            screenshots.dismissFailure()
                        }
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 11)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            } else if screenshots.library.items.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.dashed")
                    Text("Your recent selections will appear here")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        ForEach(screenshots.library.items.prefix(8)) { item in
                            ScreenshotThumbnail(item: item, screenshots: screenshots)
                        }
                    }
                }
                .frame(height: 62)
            }
        }
    }
}

private struct ScreenshotThumbnail: View {
    let item: ScreenshotItem
    let screenshots: ScreenshotController

    private var library: ScreenshotLibrary { screenshots.library }

    var body: some View {
        Group {
            if let image = NSImage(contentsOf: item.url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 72, height: 54)
        .background(.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(.primary.opacity(0.09), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { screenshots.edit(item) }
        .onDrag {
            NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
        }
        .contextMenu {
            Button("Copy") { library.copy(item) }
            Button("Reveal in Finder") { library.reveal(item) }
            Divider()
            Button("Delete", role: .destructive) { library.delete(item) }
        }
        .help("Click to annotate, or drag into another app")
    }
}
