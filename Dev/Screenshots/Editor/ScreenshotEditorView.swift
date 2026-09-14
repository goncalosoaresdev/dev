import AppKit
import SwiftUI

struct ScreenshotEditorView: View {
    @Bindable var model: ScreenshotEditorModel
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            AnnotationCanvas(model: model)
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .underPageBackgroundColor))
            Divider()
            footer
        }
        .frame(minWidth: 640, minHeight: 460)
        .alert("Add text", isPresented: $model.isEnteringText) {
            TextField("Text", text: $model.textDraft)
            Button("Cancel", role: .cancel) {
                model.textDraft = ""
                model.pendingTextPoint = nil
            }
            Button("Add") { model.commitText() }
        } message: {
            Text("Enter the label to place on the screenshot.")
        }
        .alert("Couldn’t save annotations", isPresented: errorPresented) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
        .onDeleteCommand { model.deleteSelection() }
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            ForEach(AnnotationTool.allCases) { tool in
                Button {
                    model.selectedTool = tool
                    model.selectedID = nil
                } label: {
                    Image(systemName: tool.symbol)
                        .frame(width: 27, height: 27)
                        .background(
                            model.selectedTool == tool ? Color.primary.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .help(tool.title)
            }

            Divider().frame(height: 22).padding(.horizontal, 4)

            ColorPicker("Color", selection: colorBinding, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 28)
                .disabled(model.selectedTool == .select || model.selectedTool == .redact)

            Picker("Width", selection: $model.lineWidth) {
                Text("Thin").tag(2.0)
                Text("Medium").tag(3.0)
                Text("Thick").tag(6.0)
            }
            .labelsHidden()
            .frame(width: 92)
            .disabled(model.selectedTool == .select || model.selectedTool == .text || model.selectedTool == .redact)

            Spacer()

            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!model.canUndo).help("Undo")
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!model.canRedo).help("Redo")
            Button { model.deleteSelection() } label: { Image(systemName: "trash") }
                .disabled(model.selectedID == nil).help("Delete selection")
            Button("Clear") { model.clear() }
                .disabled(model.annotations.isEmpty)
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 16)
        .frame(height: 50)
    }

    private var footer: some View {
        HStack {
            Text(instruction).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
            Button("Save", action: onSave).keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
    }

    private var instruction: String {
        switch model.selectedTool {
        case .select: "Click an annotation to select it, then drag to move it"
        case .rectangle: "Drag to draw a highlight box"
        case .arrow: "Drag from the arrow’s tail to its tip"
        case .pen: "Drag to draw freely"
        case .text: "Click where you want to add text"
        case .redact: "Drag over content to cover it"
        }
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { model.color.swiftUIColor },
            set: { color in
                let converted = NSColor(color).usingColorSpace(.sRGB) ?? .systemRed
                model.color = AnnotationColor(
                    red: converted.redComponent,
                    green: converted.greenComponent,
                    blue: converted.blueComponent,
                    alpha: 1
                )
            }
        )
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }
}

private struct AnnotationCanvas: View {
    @Bindable var model: ScreenshotEditorModel
    @State private var dragStart: CGPoint?
    @State private var movingOriginal: ScreenshotAnnotation?
    @State private var mutationStarted = false

    var body: some View {
        GeometryReader { proxy in
            let imageFrame = aspectFitFrame(imageSize: model.image.size, container: proxy.size)
            ZStack(alignment: .topLeading) {
                Color.clear
                Image(nsImage: model.image)
                    .resizable().scaledToFit()
                    .frame(width: imageFrame.width, height: imageFrame.height)
                    .position(x: imageFrame.midX, y: imageFrame.midY)
                Canvas { context, _ in
                    for annotation in model.annotations {
                        draw(annotation, selected: annotation.id == model.selectedID, frame: imageFrame, context: &context)
                    }
                    if let draft = model.draftAnnotation {
                        draw(draft, selected: false, frame: imageFrame, context: &context)
                    }
                }
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(in: imageFrame))
        }
        .accessibilityLabel("Screenshot annotation canvas")
        .accessibilityHint("Use the toolbar to select a markup tool")
    }

    private func dragGesture(in frame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard frame.contains(value.startLocation) else { return }
                let start = normalize(value.startLocation, in: frame)
                let end = normalize(clamp(value.location, to: frame), in: frame)
                if dragStart == nil { dragStart = start }

                switch model.selectedTool {
                case .select:
                    moveSelection(from: start, to: end)
                case .rectangle, .redact:
                    model.draftAnnotation = ScreenshotAnnotation(
                        kind: model.selectedTool == .rectangle ? .rectangle : .redact,
                        rect: standardizedRect(from: start, to: end), color: model.color, lineWidth: model.lineWidth
                    )
                case .arrow:
                    model.draftAnnotation = ScreenshotAnnotation(
                        kind: .arrow, points: [start, end], color: model.color, lineWidth: model.lineWidth
                    )
                case .pen:
                    if model.draftAnnotation == nil {
                        model.draftAnnotation = ScreenshotAnnotation(
                            kind: .pen, points: [start], color: model.color, lineWidth: model.lineWidth
                        )
                    }
                    model.draftAnnotation?.points.append(end)
                case .text:
                    break
                }
            }
            .onEnded { value in
                defer {
                    dragStart = nil
                    movingOriginal = nil
                    mutationStarted = false
                    model.draftAnnotation = nil
                }
                guard frame.contains(value.startLocation) else { return }
                let point = normalize(clamp(value.location, to: frame), in: frame)
                switch model.selectedTool {
                case .select:
                    if !mutationStarted { model.selectedID = hitTest(point).map(\.id) }
                case .text:
                    model.pendingTextPoint = point
                    model.isEnteringText = true
                case .rectangle, .redact:
                    guard let draft = model.draftAnnotation, let rect = draft.rect,
                          rect.width * frame.width >= 4, rect.height * frame.height >= 4 else { return }
                    model.commit(draft)
                case .arrow:
                    guard let draft = model.draftAnnotation, draft.points.count == 2,
                          distance(draft.points[0], draft.points[1]) * max(frame.width, frame.height) >= 4 else { return }
                    model.commit(draft)
                case .pen:
                    guard let draft = model.draftAnnotation, draft.points.count > 1 else { return }
                    model.commit(draft)
                }
            }
    }

    private func moveSelection(from start: CGPoint, to end: CGPoint) {
        if movingOriginal == nil {
            guard let hit = hitTest(start) else { return }
            movingOriginal = hit
            model.selectedID = hit.id
        }
        guard let original = movingOriginal,
              let index = model.annotations.firstIndex(where: { $0.id == original.id }) else { return }
        if !mutationStarted { model.beginMutation(); mutationStarted = true }
        model.annotations[index] = translated(original, dx: end.x - start.x, dy: end.y - start.y)
    }

    private func hitTest(_ point: CGPoint) -> ScreenshotAnnotation? {
        model.annotations.reversed().first { annotation in
            if let rect = annotation.rect { return rect.insetBy(dx: -0.015, dy: -0.015).contains(point) }
            guard !annotation.points.isEmpty else { return false }
            let xs = annotation.points.map(\.x), ys = annotation.points.map(\.y)
            return CGRect(
                x: (xs.min() ?? 0) - 0.025, y: (ys.min() ?? 0) - 0.025,
                width: (xs.max() ?? 0) - (xs.min() ?? 0) + 0.05,
                height: (ys.max() ?? 0) - (ys.min() ?? 0) + 0.05
            ).contains(point)
        }
    }

    private func translated(_ annotation: ScreenshotAnnotation, dx: CGFloat, dy: CGFloat) -> ScreenshotAnnotation {
        var copy = annotation
        if let rect = copy.rect {
            let proposed = rect.offsetBy(dx: dx, dy: dy)
            copy.rect = CGRect(
                x: min(max(proposed.minX, 0), 1 - rect.width),
                y: min(max(proposed.minY, 0), 1 - rect.height),
                width: rect.width, height: rect.height
            )
        } else if !copy.points.isEmpty {
            let xs = copy.points.map(\.x), ys = copy.points.map(\.y)
            let appliedDX = min(max(dx, -(xs.min() ?? 0)), 1 - (xs.max() ?? 1))
            let appliedDY = min(max(dy, -(ys.min() ?? 0)), 1 - (ys.max() ?? 1))
            copy.points = copy.points.map { CGPoint(x: $0.x + appliedDX, y: $0.y + appliedDY) }
        }
        return copy
    }

    private func draw(_ annotation: ScreenshotAnnotation, selected: Bool, frame: CGRect, context: inout GraphicsContext) {
        let color = annotation.color.swiftUIColor
        switch annotation.kind {
        case .rectangle:
            if let rect = annotation.rect {
                context.stroke(Path(roundedRect: denormalize(rect, in: frame), cornerRadius: 2), with: .color(color), lineWidth: CGFloat(annotation.lineWidth))
            }
        case .redact:
            if let rect = annotation.rect { context.fill(Path(denormalize(rect, in: frame)), with: .color(.black)) }
        case .arrow:
            guard annotation.points.count >= 2 else { break }
            let start = denormalize(annotation.points[0], in: frame)
            let end = denormalize(annotation.points[1], in: frame)
            var path = Path(); path.move(to: start); path.addLine(to: end)
            let head = arrowHead(from: start, to: end, size: 12 + CGFloat(annotation.lineWidth))
            path.move(to: head.0); path.addLine(to: end); path.addLine(to: head.1)
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: CGFloat(annotation.lineWidth), lineCap: .round, lineJoin: .round))
        case .pen:
            guard let first = annotation.points.first else { break }
            var path = Path(); path.move(to: denormalize(first, in: frame))
            for point in annotation.points.dropFirst() { path.addLine(to: denormalize(point, in: frame)) }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: CGFloat(annotation.lineWidth), lineCap: .round, lineJoin: .round))
        case .text:
            guard let point = annotation.points.first, let text = annotation.text else { break }
            context.draw(Text(text).font(.system(size: 15, weight: .semibold)).foregroundColor(color), at: denormalize(point, in: frame), anchor: .topLeading)
        }
        if selected {
            let bounds = annotationBounds(annotation, frame: frame).insetBy(dx: -4, dy: -4)
            context.stroke(Path(bounds), with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
    }

    private func annotationBounds(_ annotation: ScreenshotAnnotation, frame: CGRect) -> CGRect {
        if let rect = annotation.rect { return denormalize(rect, in: frame) }
        let points = annotation.points.map { denormalize($0, in: frame) }
        guard !points.isEmpty else { return .zero }
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x: xs.min() ?? 0, y: ys.min() ?? 0, width: max(20, (xs.max() ?? 0) - (xs.min() ?? 0)), height: max(20, (ys.max() ?? 0) - (ys.min() ?? 0)))
    }

    private func aspectFitFrame(imageSize: CGSize, container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (container.width - size.width) / 2, y: (container.height - size.height) / 2, width: size.width, height: size.height)
    }

    private func clamp(_ point: CGPoint, to frame: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, frame.minX), frame.maxX), y: min(max(point.y, frame.minY), frame.maxY))
    }
    private func normalize(_ point: CGPoint, in frame: CGRect) -> CGPoint {
        CGPoint(x: (point.x - frame.minX) / frame.width, y: (point.y - frame.minY) / frame.height)
    }
    private func denormalize(_ point: CGPoint, in frame: CGRect) -> CGPoint {
        CGPoint(x: frame.minX + point.x * frame.width, y: frame.minY + point.y * frame.height)
    }
    private func denormalize(_ rect: CGRect, in frame: CGRect) -> CGRect {
        CGRect(x: frame.minX + rect.minX * frame.width, y: frame.minY + rect.minY * frame.height, width: rect.width * frame.width, height: rect.height * frame.height)
    }
    private func standardizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }
    private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat { hypot(rhs.x - lhs.x, rhs.y - lhs.y) }
    private func arrowHead(from start: CGPoint, to end: CGPoint, size: CGFloat) -> (CGPoint, CGPoint) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        return (
            CGPoint(x: end.x - size * cos(angle - .pi / 6), y: end.y - size * sin(angle - .pi / 6)),
            CGPoint(x: end.x - size * cos(angle + .pi / 6), y: end.y - size * sin(angle + .pi / 6))
        )
    }
}
