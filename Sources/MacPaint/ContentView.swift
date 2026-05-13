import SwiftUI

struct ContentView: View {
    @EnvironmentObject var canvas: CanvasModel

    var body: some View {
        VStack(spacing: 0) {
            Toolbar()
            Divider()
            CanvasView()
                .background(Color(white: 0.95))
        }
        .sheet(item: $canvas.savePreview) { preview in
            SavePreviewSheet(image: preview.image)
                .environmentObject(canvas)
        }
        .onAppear {
            canvas.pngDataProvider = { [weak canvas] in
                guard let canvas else { return nil }
                let viewSize = canvas.canvasSize
                guard viewSize.width > 0, viewSize.height > 0 else { return nil }
                let renderer = ImageRenderer(
                    content: CanvasSnapshotView(canvas: canvas, size: viewSize)
                )
                if let bg = canvas.backgroundImage, bg.size.width > 0, bg.size.height > 0 {
                    let scale = max(bg.size.width / viewSize.width,
                                    bg.size.height / viewSize.height)
                    renderer.scale = scale
                } else {
                    renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
                }
                guard let cg = renderer.cgImage else { return nil }
                let rep = NSBitmapImageRep(cgImage: cg)
                return rep.representation(using: .png, properties: [:])
            }
        }
    }
}

struct Toolbar: View {
    @EnvironmentObject var canvas: CanvasModel

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Tool.allCases) { t in
                ToolButton(tool: t, isActive: canvas.tool == t) {
                    if canvas.editingTextID != nil { canvas.commitEditingText() }
                    canvas.tool = t
                }
            }

            Divider().frame(height: 20)

            ColorPicker("", selection: $canvas.color, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 40)

            if canvas.tool == .text {
                HStack(spacing: 4) {
                    Text("文字")
                    Slider(value: $canvas.fontSize, in: 10...96)
                        .frame(width: 100)
                    Text("\(Int(canvas.fontSize))")
                        .monospacedDigit()
                        .frame(width: 28, alignment: .trailing)
                }
            } else {
                HStack(spacing: 4) {
                    Text("太さ")
                    Slider(value: $canvas.lineWidth, in: 1...40)
                        .frame(width: 100)
                    Text("\(Int(canvas.lineWidth))")
                        .monospacedDigit()
                        .frame(width: 24, alignment: .trailing)
                }
            }

            if canvas.tool.isShape {
                Toggle("塗り", isOn: $canvas.fillShape)
                    .toggleStyle(.checkbox)
            }

            Spacer()

            Button("元に戻す") { canvas.undo() }.disabled(canvas.strokes.isEmpty)
            Button("やり直し") { canvas.redo() }.disabled(canvas.redoStack.isEmpty)
            Button("クリア") { canvas.clear() }
            Button("開く") { canvas.openFile() }
            Button("保存") { canvas.saveFile() }
        }
        .padding(8)
    }
}

struct ToolButton: View {
    let tool: Tool
    let isActive: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: tool.systemImage)
                .font(.system(size: 14, weight: isActive ? .bold : .regular))
                .foregroundColor(isActive ? .white : .primary)
                .frame(width: 32, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isActive ? Color.accentColor
                              : (hovering ? Color.gray.opacity(0.18) : Color.clear))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isActive ? Color.accentColor : Color.gray.opacity(0.35),
                                lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tool.label)
    }
}

struct CanvasSnapshotView: View {
    @ObservedObject var canvas: CanvasModel
    let size: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white
                .frame(width: size.width, height: size.height)
            if let bg = canvas.backgroundImage {
                Image(nsImage: bg)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
            }
            Canvas { ctx, _ in
                for s in canvas.strokes {
                    if s.tool == .text { continue }
                    CanvasView.drawStatic(stroke: s, in: &ctx)
                }
            }
            .frame(width: size.width, height: size.height)
            ForEach(canvas.strokes.filter { $0.tool == .text }) { s in
                Text(s.text)
                    .font(.system(size: s.fontSize))
                    .foregroundColor(s.color)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .position(
                        x: s.points[0].x + textHalfSize(s).width,
                        y: s.points[0].y + textHalfSize(s).height
                    )
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func textHalfSize(_ s: Stroke) -> CGSize {
        let m = TextMeasure.size(of: s.text, fontSize: s.fontSize)
        return CGSize(width: m.width / 2 + 4, height: m.height / 2 + 2)
    }
}

struct CanvasView: View {
    @EnvironmentObject var canvas: CanvasModel
    @State private var hoverPoint: CGPoint?
    @State private var isHovering: Bool = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.white
                if let bg = canvas.backgroundImage {
                    Image(nsImage: bg)
                        .resizable()
                        .scaledToFit()
                }
                Canvas { ctx, size in
                    for s in canvas.strokes {
                        if s.tool == .text { continue }
                        draw(stroke: s, in: &ctx)
                    }
                    if let s = canvas.currentStroke { draw(stroke: s, in: &ctx) }
                    _ = size
                }
                .allowsHitTesting(false)

                TextItemsLayer()

                if let id = canvas.editingTextID,
                   let stroke = canvas.strokes.first(where: { $0.id == id }) {
                    TextEditorOverlay(stroke: stroke)
                }

                if isHovering, let p = hoverPoint {
                    switch canvas.tool {
                    case .pen:
                        PenCursor(color: canvas.color, lineWidth: canvas.lineWidth)
                            .position(x: p.x + 10, y: p.y - 10)
                            .allowsHitTesting(false)
                    case .eraser:
                        Circle()
                            .stroke(Color.black.opacity(0.7), lineWidth: 1)
                            .background(
                                Circle().stroke(Color.white.opacity(0.9), lineWidth: 1)
                                    .padding(1)
                            )
                            .frame(width: max(canvas.lineWidth, 4),
                                   height: max(canvas.lineWidth, 4))
                            .position(p)
                            .allowsHitTesting(false)
                    default:
                        EmptyView()
                    }
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let p):
                    isHovering = true
                    hoverPoint = p
                case .ended:
                    isHovering = false
                }
            }
            .gesture(canvasGesture)
            .trackingArea(useBlankCursor: usesCustomCursor)
            .onAppear {
                canvas.canvasSize = geo.size
            }
            .onChange(of: geo.size) { newValue in
                canvas.canvasSize = newValue
            }
        }
    }

    private var usesCustomCursor: Bool {
        switch canvas.tool {
        case .pen, .eraser: return true
        default: return false
        }
    }

    private var canvasGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                hoverPoint = value.location
                isHovering = true
                if canvas.tool == .text { return }
                if canvas.editingTextID != nil { canvas.commitEditingText() }
                if canvas.currentStroke == nil {
                    canvas.beginStroke(at: value.location)
                } else {
                    canvas.extendStroke(to: value.location)
                }
            }
            .onEnded { value in
                if canvas.tool == .text {
                    if canvas.editingTextID != nil { canvas.commitEditingText() }
                    canvas.placeText(at: value.location)
                } else {
                    canvas.endStroke()
                }
            }
    }

    private func draw(stroke s: Stroke, in ctx: inout GraphicsContext) {
        CanvasView.drawStatic(stroke: s, in: &ctx)
    }

    static func drawStatic(stroke s: Stroke, in ctx: inout GraphicsContext) {
        guard !s.points.isEmpty else { return }
        switch s.tool {
        case .pen:
            var path = Path()
            path.move(to: s.points[0])
            for p in s.points.dropFirst() { path.addLine(to: p) }
            ctx.stroke(path, with: .color(s.color),
                       style: StrokeStyle(lineWidth: s.lineWidth, lineCap: .round, lineJoin: .round))
        case .eraser:
            var path = Path()
            path.move(to: s.points[0])
            for p in s.points.dropFirst() { path.addLine(to: p) }
            var eraseCtx = ctx
            eraseCtx.blendMode = .destinationOut
            eraseCtx.stroke(path, with: .color(.black),
                            style: StrokeStyle(lineWidth: s.lineWidth, lineCap: .round, lineJoin: .round))
        case .line:
            guard s.points.count >= 2 else { return }
            var path = Path()
            path.move(to: s.points[0])
            path.addLine(to: s.points[1])
            ctx.stroke(path, with: .color(s.color),
                       style: StrokeStyle(lineWidth: s.lineWidth, lineCap: .round, lineJoin: .round))
        case .rectangle:
            guard s.points.count >= 2 else { return }
            let r = makeRect(s.points[0], s.points[1])
            let path = Path(r)
            if s.filled { ctx.fill(path, with: .color(s.color)) }
            else { ctx.stroke(path, with: .color(s.color), lineWidth: s.lineWidth) }
        case .ellipse:
            guard s.points.count >= 2 else { return }
            let r = makeRect(s.points[0], s.points[1])
            let path = Path(ellipseIn: r)
            if s.filled { ctx.fill(path, with: .color(s.color)) }
            else { ctx.stroke(path, with: .color(s.color), lineWidth: s.lineWidth) }
        case .triangle:
            guard s.points.count >= 2 else { return }
            let r = makeRect(s.points[0], s.points[1])
            var path = Path()
            path.move(to: CGPoint(x: r.midX, y: r.minY))
            path.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            path.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            path.closeSubpath()
            if s.filled { ctx.fill(path, with: .color(s.color)) }
            else { ctx.stroke(path, with: .color(s.color),
                              style: StrokeStyle(lineWidth: s.lineWidth, lineJoin: .round)) }
        case .star:
            guard s.points.count >= 2 else { return }
            let r = makeRect(s.points[0], s.points[1])
            let path = makeStarPath(in: r)
            if s.filled { ctx.fill(path, with: .color(s.color)) }
            else { ctx.stroke(path, with: .color(s.color),
                              style: StrokeStyle(lineWidth: s.lineWidth, lineJoin: .round)) }
        case .arrow:
            guard s.points.count >= 2 else { return }
            let path = makeArrowPath(from: s.points[0], to: s.points[1], width: s.lineWidth)
            ctx.stroke(path, with: .color(s.color),
                       style: StrokeStyle(lineWidth: s.lineWidth, lineCap: .round, lineJoin: .round))
        case .text:
            let text = Text(s.text)
                .font(.system(size: s.fontSize))
                .foregroundColor(s.color)
            ctx.draw(text, at: s.points[0], anchor: .topLeading)
        }
    }

    private static func makeRect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    private static func makeStarPath(in r: CGRect) -> Path {
        var path = Path()
        let cx = r.midX, cy = r.midY
        let outer = min(r.width, r.height) / 2
        let inner = outer * 0.4
        let points = 5
        for i in 0..<(points * 2) {
            let radius = (i % 2 == 0) ? outer : inner
            let angle = -CGFloat.pi / 2 + CGFloat(i) * .pi / CGFloat(points)
            let p = CGPoint(x: cx + cos(angle) * radius, y: cy + sin(angle) * radius)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    private static func makeArrowPath(from a: CGPoint, to b: CGPoint, width: CGFloat) -> Path {
        var path = Path()
        path.move(to: a)
        path.addLine(to: b)
        let angle = atan2(b.y - a.y, b.x - a.x)
        let head = max(width * 3, 10)
        let p1 = CGPoint(x: b.x - head * cos(angle - .pi / 7),
                         y: b.y - head * sin(angle - .pi / 7))
        let p2 = CGPoint(x: b.x - head * cos(angle + .pi / 7),
                         y: b.y - head * sin(angle + .pi / 7))
        path.move(to: b); path.addLine(to: p1)
        path.move(to: b); path.addLine(to: p2)
        return path
    }
}

struct SavePreviewSheet: View {
    @EnvironmentObject var canvas: CanvasModel
    let image: NSImage

    var body: some View {
        VStack(spacing: 12) {
            Text("保存プレビュー")
                .font(.headline)
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 600, maxHeight: 480)
                .border(Color.gray.opacity(0.3))
            Text("\(Int(image.size.width)) × \(Int(image.size.height)) px")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack {
                Button("キャンセル") { canvas.cancelSave() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存…") { canvas.confirmSave() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 480)
    }
}

struct PenCursor: View {
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        Image(systemName: "pencil")
            .font(.system(size: 20, weight: .regular))
            .foregroundColor(.black)
            .shadow(color: .white.opacity(0.9), radius: 0.5, x: 0.5, y: 0.5)
    }
}

extension View {
    func trackingArea(useBlankCursor: Bool) -> some View {
        background(CursorTrackingView(useBlankCursor: useBlankCursor))
    }
}

private struct CursorTrackingView: NSViewRepresentable {
    let useBlankCursor: Bool

    static let blankCursor: NSCursor = {
        let img = NSImage(size: NSSize(width: 1, height: 1))
        img.lockFocus()
        NSColor.clear.set()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        img.unlockFocus()
        return NSCursor(image: img, hotSpot: .zero)
    }()

    func makeNSView(context: Context) -> TrackingNSView {
        let v = TrackingNSView()
        v.useBlankCursor = useBlankCursor
        return v
    }

    func updateNSView(_ nsView: TrackingNSView, context: Context) {
        nsView.useBlankCursor = useBlankCursor
        nsView.window?.invalidateCursorRects(for: nsView)
    }

    final class TrackingNSView: NSView {
        var useBlankCursor: Bool = false
        private var trackingArea: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let t = trackingArea { removeTrackingArea(t) }
            let t = NSTrackingArea(
                rect: bounds,
                options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .inVisibleRect],
                owner: self, userInfo: nil
            )
            addTrackingArea(t)
            trackingArea = t
        }

        override func resetCursorRects() {
            if useBlankCursor {
                addCursorRect(bounds, cursor: CursorTrackingView.blankCursor)
            } else {
                addCursorRect(bounds, cursor: .arrow)
            }
        }

        override func cursorUpdate(with event: NSEvent) {
            if useBlankCursor {
                CursorTrackingView.blankCursor.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }
}

struct TextEditorOverlay: View {
    @EnvironmentObject var canvas: CanvasModel
    let stroke: Stroke

    private var measured: CGSize {
        TextMeasure.size(of: canvas.editingTextValue, fontSize: stroke.fontSize)
    }

    private var width: CGFloat {
        let minW = stroke.fontSize * 2.5
        return max(minW, measured.width + stroke.fontSize * 0.6)
    }

    private var height: CGFloat {
        max(stroke.fontSize * 1.4, measured.height + 4)
    }

    var body: some View {
        MultilineTextField(
            text: Binding(
                get: { canvas.editingTextValue },
                set: { canvas.updateEditingText($0) }
            ),
            fontSize: stroke.fontSize,
            color: NSColor(stroke.color),
            onCommit: { canvas.commitEditingText() }
        )
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Color.white.opacity(0.6))
        .overlay(
            Rectangle().stroke(Color.accentColor, lineWidth: 1)
        )
        .frame(width: width, height: height, alignment: .topLeading)
        .position(
            x: stroke.points[0].x + width / 2,
            y: stroke.points[0].y + height / 2
        )
        .transaction { $0.disablesAnimations = true }
    }
}

enum TextMeasure {
    static func size(of text: String, fontSize: CGFloat) -> CGSize {
        let display = text.isEmpty ? " " : text
        let font = NSFont.systemFont(ofSize: fontSize)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let lines = display.components(separatedBy: "\n")
        let widths = lines.map { ($0 as NSString).size(withAttributes: attrs).width }
        let maxW = widths.max() ?? 0
        let lineH = font.ascender - font.descender + font.leading
        return CGSize(width: maxW, height: lineH * CGFloat(lines.count))
    }
}

struct MultilineTextField: NSViewRepresentable {
    @Binding var text: String
    let fontSize: CGFloat
    let color: NSColor
    let onCommit: () -> Void

    func makeNSView(context: Context) -> CommittingTextView {
        let tv = CommittingTextView()
        context.coordinator.textBinding = $text
        tv.delegate = context.coordinator
        tv.commitHandler = onCommit
        let coord = context.coordinator
        tv.markedSyncHandler = { [weak coord] str in
            coord?.isInternalUpdate = true
            coord?.textBinding?.wrappedValue = str
            coord?.isInternalUpdate = false
        }
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.isEditable = true
        tv.isSelectable = true
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.containerSize = NSSize(width: 100_000, height: 100_000)
        tv.maxSize = NSSize(width: 100_000, height: 100_000)

        applyAttributes(to: tv)
        if !text.isEmpty {
            tv.textStorage?.setAttributedString(makeAttributed(text))
        }

        DispatchQueue.main.async {
            tv.window?.makeFirstResponder(tv)
        }
        return tv
    }

    func updateNSView(_ tv: CommittingTextView, context: Context) {
        context.coordinator.textBinding = $text
        tv.commitHandler = onCommit
        let coord = context.coordinator
        tv.markedSyncHandler = { [weak coord] str in
            coord?.isInternalUpdate = true
            coord?.textBinding?.wrappedValue = str
            coord?.isInternalUpdate = false
        }

        if tv.font?.pointSize != fontSize || tv.textColor != color {
            applyAttributes(to: tv)
        }

        let hasMarked = tv.markedRange().length > 0
        if !context.coordinator.isInternalUpdate, !hasMarked, tv.string != text {
            let wasFirstResponder = (tv.window?.firstResponder === tv)
            let selected = tv.selectedRange()
            tv.textStorage?.setAttributedString(makeAttributed(text))
            let len = (text as NSString).length
            tv.setSelectedRange(NSRange(location: min(selected.location, len), length: 0))
            if wasFirstResponder {
                tv.window?.makeFirstResponder(tv)
            }
        }
    }

    private func applyAttributes(to tv: NSTextView) {
        let font = NSFont.systemFont(ofSize: fontSize)
        tv.font = font
        tv.textColor = color
        tv.insertionPointColor = color
        tv.typingAttributes = [
            .font: font,
            .foregroundColor: color
        ]
    }

    private func makeAttributed(_ s: String) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: fontSize)
        return NSAttributedString(string: s, attributes: [
            .font: font,
            .foregroundColor: color
        ])
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var textBinding: Binding<String>?
        var isInternalUpdate: Bool = false
        init(_ p: MultilineTextField) {}
    }

    final class CommittingTextView: NSTextView {
        var commitHandler: (() -> Void)?
        var markedSyncHandler: ((String) -> Void)?
        private var insideMarkedUpdate = false

        override func didChangeText() {
            super.didChangeText()
            if insideMarkedUpdate { return }
            markedSyncHandler?(string)
        }

        override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
            insideMarkedUpdate = true
            super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
            insideMarkedUpdate = false
            markedSyncHandler?(currentDisplayString())
        }

        override func unmarkText() {
            super.unmarkText()
            markedSyncHandler?(self.string)
        }

        private func currentDisplayString() -> String {
            let confirmed = string
            if let marked = attributedSubstring(forProposedRange: markedRange(), actualRange: nil)?.string,
               !marked.isEmpty {
                let r = markedRange()
                let nsConfirmed = confirmed as NSString
                if r.location <= nsConfirmed.length {
                    let prefix = nsConfirmed.substring(to: r.location)
                    let suffix = nsConfirmed.substring(from: min(r.location, nsConfirmed.length))
                    return prefix + marked + suffix
                }
                return confirmed + marked
            }
            return confirmed
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 36 { // Return
                if hasMarkedText() {
                    super.keyDown(with: event)
                    return
                }
                if event.modifierFlags.contains(.shift) {
                    insertNewline(self)
                    return
                } else {
                    commitHandler?()
                    return
                }
            }
            super.keyDown(with: event)
        }
    }
}

struct TextItemsLayer: View {
    @EnvironmentObject var canvas: CanvasModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(canvas.strokes.filter { $0.tool == .text && $0.id != canvas.editingTextID }) { s in
                TextDraggable(stroke: s)
            }
        }
    }
}

struct TextDraggable: View {
    @EnvironmentObject var canvas: CanvasModel
    let stroke: Stroke
    @State private var dragOffset: CGSize = .zero
    @State private var isHovering: Bool = false
    @State private var isDragging: Bool = false

    private var showBorder: Bool { isHovering || isDragging }

    var body: some View {
        Text(stroke.text)
            .font(.system(size: stroke.fontSize))
            .foregroundColor(stroke.color)
            .fixedSize(horizontal: true, vertical: true)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(showBorder ? Color.white.opacity(0.6) : Color.clear)
            .overlay(
                Rectangle()
                    .stroke(Color.accentColor, lineWidth: showBorder ? 1 : 0)
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.openHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .position(
                x: stroke.points[0].x + measuredHalfSize.width + dragOffset.width,
                y: stroke.points[0].y + measuredHalfSize.height + dragOffset.height
            )
            .gesture(
                DragGesture()
                    .onChanged { v in
                        isDragging = true
                        dragOffset = v.translation
                    }
                    .onEnded { v in
                        let new = CGPoint(
                            x: stroke.points[0].x + v.translation.width,
                            y: stroke.points[0].y + v.translation.height
                        )
                        canvas.moveText(id: stroke.id, to: new)
                        dragOffset = .zero
                        isDragging = false
                    }
            )
            .onTapGesture(count: 2) {
                canvas.beginEditingText(id: stroke.id)
            }
    }

    private var measuredHalfSize: CGSize {
        let s = TextMeasure.size(of: stroke.text, fontSize: stroke.fontSize)
        return CGSize(width: s.width / 2 + 4, height: s.height / 2 + 2)
    }
}
