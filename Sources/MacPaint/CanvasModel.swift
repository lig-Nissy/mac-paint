import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum Tool: String, CaseIterable, Identifiable {
    case pen, eraser, line, rectangle, ellipse, triangle, star, arrow, text
    var id: String { rawValue }
    var label: String {
        switch self {
        case .pen: return "ペン"
        case .eraser: return "消しゴム"
        case .line: return "直線"
        case .rectangle: return "四角"
        case .ellipse: return "丸"
        case .triangle: return "三角"
        case .star: return "星"
        case .arrow: return "矢印"
        case .text: return "テキスト"
        }
    }
    var systemImage: String {
        switch self {
        case .pen: return "pencil.tip"
        case .eraser: return "eraser"
        case .line: return "line.diagonal"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .triangle: return "triangle"
        case .star: return "star"
        case .arrow: return "arrow.up.right"
        case .text: return "textformat"
        }
    }
    var isShape: Bool {
        switch self {
        case .rectangle, .ellipse, .triangle, .star: return true
        default: return false
        }
    }
}

struct Stroke: Identifiable {
    let id = UUID()
    var tool: Tool
    var color: Color
    var lineWidth: CGFloat
    var points: [CGPoint]
    var filled: Bool = false
    var text: String = ""
    var fontSize: CGFloat = 18
}

final class CanvasModel: ObservableObject {
    @Published var strokes: [Stroke] = []
    @Published var redoStack: [Stroke] = []
    @Published var currentStroke: Stroke?
    @Published var tool: Tool = .pen
    @Published var color: Color = .black
    @Published var lineWidth: CGFloat = 3
    @Published var fontSize: CGFloat = 18
    @Published var fillShape: Bool = false
    @Published var canvasSize: CGSize = .init(width: 1200, height: 800)
    @Published var backgroundImage: NSImage?

    @Published var editingTextID: UUID?
    @Published var editingTextValue: String = ""
    @Published var editingTextOrigin: CGPoint = .zero

    func beginStroke(at point: CGPoint) {
        currentStroke = Stroke(
            tool: tool,
            color: color,
            lineWidth: lineWidth,
            points: [point],
            filled: fillShape && tool.isShape,
            text: "",
            fontSize: fontSize
        )
    }

    func extendStroke(to point: CGPoint) {
        guard var s = currentStroke else { return }
        switch s.tool {
        case .pen, .eraser:
            s.points.append(point)
        case .line, .rectangle, .ellipse, .triangle, .star, .arrow:
            if s.points.count < 2 { s.points.append(point) } else { s.points[1] = point }
        case .text:
            break
        }
        currentStroke = s
    }

    func endStroke() {
        if let s = currentStroke, !s.points.isEmpty {
            strokes.append(s)
            redoStack.removeAll()
        }
        currentStroke = nil
    }

    func placeText(at point: CGPoint) {
        let s = Stroke(
            tool: .text, color: color, lineWidth: lineWidth,
            points: [point], filled: false, text: "", fontSize: fontSize
        )
        strokes.append(s)
        redoStack.removeAll()
        editingTextID = s.id
        editingTextValue = ""
        editingTextOrigin = point
    }

    func updateEditingText(_ value: String) {
        editingTextValue = value
        guard let id = editingTextID,
              let idx = strokes.firstIndex(where: { $0.id == id }) else { return }
        strokes[idx].text = value
    }

    func moveText(id: UUID, to point: CGPoint) {
        guard let idx = strokes.firstIndex(where: { $0.id == id }) else { return }
        guard strokes[idx].tool == .text else { return }
        strokes[idx].points = [point]
    }

    func beginEditingText(id: UUID) {
        guard let idx = strokes.firstIndex(where: { $0.id == id }) else { return }
        guard strokes[idx].tool == .text else { return }
        editingTextID = id
        editingTextValue = strokes[idx].text
        editingTextOrigin = strokes[idx].points[0]
    }

    func commitEditingText() {
        if let id = editingTextID,
           let idx = strokes.firstIndex(where: { $0.id == id }),
           strokes[idx].text.isEmpty {
            strokes.remove(at: idx)
        }
        editingTextID = nil
        editingTextValue = ""
    }

    func undo() {
        guard let last = strokes.popLast() else { return }
        redoStack.append(last)
    }

    func redo() {
        guard let s = redoStack.popLast() else { return }
        strokes.append(s)
    }

    func clear() {
        strokes.removeAll()
        redoStack.removeAll()
        currentStroke = nil
        editingTextID = nil
        backgroundImage = nil
    }

    func saveFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "whiteboard.png"
        panel.begin { [weak self] resp in
            guard resp == .OK, let url = panel.url, let self else { return }
            if let data = self.renderPNG() {
                try? data.write(to: url)
            }
        }
    }

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] resp in
            guard resp == .OK, let url = panel.url, let self else { return }
            guard let image = NSImage(contentsOf: url) else { return }
            self.loadAsBackground(image: image)
        }
    }

    private func loadAsBackground(image: NSImage) {
        strokes.removeAll()
        redoStack.removeAll()
        currentStroke = nil
        canvasSize = image.size
        backgroundImage = image
        objectWillChange.send()
    }

    func renderPNG() -> Data? {
        let size = canvasSize
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )
        guard let rep else { return nil }
        NSGraphicsContext.saveGraphicsState()
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.current = ctx
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()

        if let bg = backgroundImage {
            bg.draw(in: NSRect(origin: .zero, size: size))
        }

        for s in strokes {
            drawStroke(s, in: ctx.cgContext, size: size)
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    private func drawStroke(_ s: Stroke, in ctx: CGContext, size: CGSize) {
        guard !s.points.isEmpty else { return }
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(s.lineWidth)
        let ns = NSColor(s.color)
        ctx.setStrokeColor(ns.cgColor)
        ctx.setFillColor(ns.cgColor)

        let flip: (CGPoint) -> CGPoint = { p in CGPoint(x: p.x, y: size.height - p.y) }

        switch s.tool {
        case .pen:
            ctx.move(to: flip(s.points[0]))
            for p in s.points.dropFirst() { ctx.addLine(to: flip(p)) }
            ctx.strokePath()
        case .eraser:
            ctx.setBlendMode(.clear)
            ctx.setStrokeColor(NSColor.clear.cgColor)
            ctx.move(to: flip(s.points[0]))
            for p in s.points.dropFirst() { ctx.addLine(to: flip(p)) }
            ctx.strokePath()
        case .line:
            if s.points.count >= 2 {
                ctx.move(to: flip(s.points[0]))
                ctx.addLine(to: flip(s.points[1]))
                ctx.strokePath()
            }
        case .rectangle:
            if s.points.count >= 2 {
                let r = rect(from: flip(s.points[0]), to: flip(s.points[1]))
                if s.filled { ctx.fill(r) } else { ctx.stroke(r) }
            }
        case .ellipse:
            if s.points.count >= 2 {
                let r = rect(from: flip(s.points[0]), to: flip(s.points[1]))
                if s.filled { ctx.fillEllipse(in: r) } else { ctx.strokeEllipse(in: r) }
            }
        case .triangle:
            if s.points.count >= 2 {
                let r = rect(from: flip(s.points[0]), to: flip(s.points[1]))
                let path = CGMutablePath()
                path.move(to: CGPoint(x: r.midX, y: r.maxY))
                path.addLine(to: CGPoint(x: r.minX, y: r.minY))
                path.addLine(to: CGPoint(x: r.maxX, y: r.minY))
                path.closeSubpath()
                ctx.addPath(path)
                if s.filled { ctx.fillPath() } else { ctx.strokePath() }
            }
        case .star:
            if s.points.count >= 2 {
                let r = rect(from: flip(s.points[0]), to: flip(s.points[1]))
                let path = starPath(in: r)
                ctx.addPath(path)
                if s.filled { ctx.fillPath() } else { ctx.strokePath() }
            }
        case .arrow:
            if s.points.count >= 2 {
                drawArrow(in: ctx, from: flip(s.points[0]), to: flip(s.points[1]), lineWidth: s.lineWidth)
            }
        case .text:
            let origin = flip(s.points[0])
            let font = NSFont.systemFont(ofSize: s.fontSize)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: ns
            ]
            let lineHeight = font.ascender - font.descender + font.leading
            let lines = s.text.components(separatedBy: "\n")
            for (i, lineText) in lines.enumerated() {
                let str = NSAttributedString(string: lineText, attributes: attrs)
                let line = CTLineCreateWithAttributedString(str)
                let y = origin.y - s.fontSize - lineHeight * CGFloat(i)
                ctx.textPosition = CGPoint(x: origin.x, y: y)
                CTLineDraw(line, ctx)
            }
        }
        ctx.restoreGState()
    }

    private func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    private func starPath(in r: CGRect) -> CGPath {
        let path = CGMutablePath()
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

    private func drawArrow(in ctx: CGContext, from a: CGPoint, to b: CGPoint, lineWidth: CGFloat) {
        ctx.move(to: a)
        ctx.addLine(to: b)
        ctx.strokePath()
        let angle = atan2(b.y - a.y, b.x - a.x)
        let head = max(lineWidth * 3, 10)
        let p1 = CGPoint(x: b.x - head * cos(angle - .pi / 7),
                         y: b.y - head * sin(angle - .pi / 7))
        let p2 = CGPoint(x: b.x - head * cos(angle + .pi / 7),
                         y: b.y - head * sin(angle + .pi / 7))
        ctx.move(to: b); ctx.addLine(to: p1)
        ctx.move(to: b); ctx.addLine(to: p2)
        ctx.strokePath()
    }
}
