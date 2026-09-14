import AppKit
import CoreText
import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class ScreenshotLibrary {
    private(set) var items: [ScreenshotItem] = []
    private let directory: URL
    private let maximumItems = 20

    init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.directory = directory ?? URL.applicationSupportDirectory
            .appending(path: "Dev", directoryHint: .isDirectory)
            .appending(path: "Screenshots", directoryHint: .isDirectory)
        try? fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
        reload(fileManager: fileManager)
    }

    func save(_ image: CGImage, fileManager: FileManager = .default) throws -> ScreenshotItem {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID()
        let createdAt = Date.now
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let filename = "Dev Screenshot \(formatter.string(from: createdAt)) \(id.uuidString).png"
        let url = directory.appending(path: filename)

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ScreenshotLibraryError.cannotCreateDestination
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ScreenshotLibraryError.cannotEncodeImage
        }

        let item = ScreenshotItem(id: id, url: url, createdAt: createdAt)
        items.insert(item, at: 0)
        applyRetention(fileManager: fileManager)
        return item
    }

    func delete(_ item: ScreenshotItem, fileManager: FileManager = .default) {
        do {
            var trashedURL: NSURL?
            try fileManager.trashItem(at: item.url, resultingItemURL: &trashedURL)
            try? fileManager.removeItem(at: originalURL(for: item))
            try? fileManager.removeItem(at: annotationsURL(for: item))
            items.removeAll { $0.id == item.id }
        } catch {
            // Keep the item visible if moving it to Trash failed.
        }
    }

    func copy(_ item: ScreenshotItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        var objects: [NSPasteboardWriting] = [item.url as NSURL]
        if let image = NSImage(contentsOf: item.url) { objects.append(image) }
        pasteboard.writeObjects(objects)
    }

    func reveal(_ item: ScreenshotItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func editingImage(for item: ScreenshotItem) -> NSImage? {
        NSImage(contentsOf: FileManager.default.fileExists(atPath: originalURL(for: item).path)
            ? originalURL(for: item)
            : item.url)
    }

    func annotations(for item: ScreenshotItem) -> [ScreenshotAnnotation] {
        guard let data = try? Data(contentsOf: annotationsURL(for: item)) else { return [] }
        if let annotations = try? JSONDecoder().decode([ScreenshotAnnotation].self, from: data) {
            return annotations
        }
        // Migrate the rectangle-only format used by the first screenshot build.
        if let rectangles = try? JSONDecoder().decode([CGRect].self, from: data) {
            return rectangles.map { ScreenshotAnnotation(kind: .rectangle, rect: $0) }
        }
        return []
    }

    func saveAnnotations(
        _ annotations: [ScreenshotAnnotation],
        for item: ScreenshotItem,
        fileManager: FileManager = .default
    ) throws {
        let original = originalURL(for: item)
        if !fileManager.fileExists(atPath: original.path) {
            try fileManager.copyItem(at: item.url, to: original)
        }
        guard let image = NSImage(contentsOf: original),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ScreenshotLibraryError.cannotReadImage
        }

        let width = cgImage.width
        let height = cgImage.height
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ScreenshotLibraryError.cannotCreateDestination
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let exportScale = CGFloat(width) / max(image.size.width, 1)
        for annotation in annotations {
            render(annotation, in: context, size: CGSize(width: width, height: height), scale: exportScale)
        }
        guard let rendered = context.makeImage() else {
            throw ScreenshotLibraryError.cannotEncodeImage
        }
        try write(rendered, to: item.url)
        let annotationData = try JSONEncoder().encode(annotations)
        try annotationData.write(to: annotationsURL(for: item), options: .atomic)

        if let index = items.firstIndex(where: { $0.id == item.id }) {
            let refreshed = items.remove(at: index)
            items.insert(refreshed, at: index)
        }
    }

    private func reload(fileManager: FileManager) {
        let keys: Set<URLResourceKey> = [.creationDateKey, .isRegularFileKey]
        let urls = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )) ?? []

        items = urls.compactMap { url in
            guard url.pathExtension.lowercased() == "png",
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { return nil }
            return ScreenshotItem(
                id: Self.id(from: url),
                url: url,
                createdAt: values.creationDate ?? .distantPast
            )
        }
        .sorted { $0.createdAt > $1.createdAt }

        applyRetention(fileManager: fileManager)
    }

    private func applyRetention(fileManager: FileManager) {
        guard items.count > maximumItems else { return }
        let excess = items.dropFirst(maximumItems)
        for item in excess {
            try? fileManager.removeItem(at: item.url)
            try? fileManager.removeItem(at: originalURL(for: item))
            try? fileManager.removeItem(at: annotationsURL(for: item))
        }
        items = Array(items.prefix(maximumItems))
    }

    private static func id(from url: URL) -> UUID {
        let stem = url.deletingPathExtension().lastPathComponent
        if let suffix = stem.split(separator: " ").last,
           let match = UUID(uuidString: String(suffix)) {
            return match
        }
        return UUID()
    }

    private func originalURL(for item: ScreenshotItem) -> URL {
        item.url.deletingPathExtension().appendingPathExtension("dev-original")
    }

    private func annotationsURL(for item: ScreenshotItem) -> URL {
        item.url.deletingPathExtension().appendingPathExtension("json")
    }

    private func write(_ image: CGImage, to url: URL) throws {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ScreenshotLibraryError.cannotCreateDestination
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ScreenshotLibraryError.cannotEncodeImage
        }
        try (data as Data).write(to: url, options: .atomic)
    }

    private func render(
        _ annotation: ScreenshotAnnotation,
        in context: CGContext,
        size: CGSize,
        scale: CGFloat
    ) {
        let color = NSColor(
            red: annotation.color.red,
            green: annotation.color.green,
            blue: annotation.color.blue,
            alpha: annotation.color.alpha
        ).cgColor
        context.saveGState()
        context.setStrokeColor(color)
        context.setLineWidth(max(1, CGFloat(annotation.lineWidth) * scale))
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch annotation.kind {
        case .rectangle:
            if let rect = annotation.rect { context.stroke(pixelRect(rect, size: size)) }
        case .redact:
            if let rect = annotation.rect {
                context.setFillColor(NSColor.black.cgColor)
                context.fill(pixelRect(rect, size: size))
            }
        case .arrow:
            guard annotation.points.count >= 2 else { break }
            let start = pixelPoint(annotation.points[0], size: size)
            let end = pixelPoint(annotation.points[1], size: size)
            context.move(to: start)
            context.addLine(to: end)
            let head = arrowHead(from: start, to: end, size: (12 + CGFloat(annotation.lineWidth)) * scale)
            context.move(to: head.0)
            context.addLine(to: end)
            context.addLine(to: head.1)
            context.strokePath()
        case .pen:
            guard let first = annotation.points.first else { break }
            context.move(to: pixelPoint(first, size: size))
            for point in annotation.points.dropFirst() {
                context.addLine(to: pixelPoint(point, size: size))
            }
            context.strokePath()
        case .text:
            guard let point = annotation.points.first, let value = annotation.text else { break }
            let pixel = pixelPoint(point, size: size)
            let fontSize = max(12, 15 * scale)
            let attributed = NSAttributedString(
                string: value,
                attributes: [
                    .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                    .foregroundColor: NSColor(cgColor: color) ?? .systemRed
                ]
            )
            let line = CTLineCreateWithAttributedString(attributed)
            context.textPosition = CGPoint(x: pixel.x, y: pixel.y - fontSize)
            CTLineDraw(line, context)
        }
        context.restoreGState()
    }

    private func pixelPoint(_ point: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: (1 - point.y) * size.height)
    }

    private func pixelRect(_ rect: CGRect, size: CGSize) -> CGRect {
        CGRect(
            x: rect.minX * size.width,
            y: (1 - rect.maxY) * size.height,
            width: rect.width * size.width,
            height: rect.height * size.height
        )
    }

    private func arrowHead(from start: CGPoint, to end: CGPoint, size: CGFloat) -> (CGPoint, CGPoint) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        return (
            CGPoint(x: end.x - size * cos(angle - .pi / 6), y: end.y - size * sin(angle - .pi / 6)),
            CGPoint(x: end.x - size * cos(angle + .pi / 6), y: end.y - size * sin(angle + .pi / 6))
        )
    }
}

enum ScreenshotLibraryError: LocalizedError {
    case cannotReadImage
    case cannotCreateDestination
    case cannotEncodeImage

    var errorDescription: String? {
        switch self {
        case .cannotReadImage: "The screenshot could not be opened for editing."
        case .cannotCreateDestination: "Dev could not create the screenshot file."
        case .cannotEncodeImage: "Dev could not encode the screenshot as PNG."
        }
    }
}
