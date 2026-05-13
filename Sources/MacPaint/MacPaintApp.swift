import SwiftUI
import AppKit

@main
struct MacPaintApp: App {
    @StateObject private var canvas = CanvasModel()

    init() {
        AppIcon.handleExportArgIfNeeded()
        NSApplication.shared.applicationIconImage = AppIcon.make(size: 512)
        installControlZMonitor()
    }

    private func installControlZMonitor() {
        let canvas = self.canvas
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.contains(.control),
                  !event.modifierFlags.contains(.command),
                  let chars = event.charactersIgnoringModifiers?.lowercased(),
                  chars == "z" else {
                return event
            }
            if event.window?.firstResponder is NSTextView {
                return event
            }
            DispatchQueue.main.async {
                if event.modifierFlags.contains(.shift) {
                    canvas.redo()
                } else {
                    canvas.undo()
                }
            }
            return nil
        }
    }

    var body: some Scene {
        WindowGroup("Mac Paint") {
            ContentView()
                .environmentObject(canvas)
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New") { canvas.clear() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Button("Open…") { canvas.openFile() }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Save…") { canvas.saveFile() }
                    .keyboardShortcut("s", modifiers: .command)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("元に戻す") { canvas.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(canvas.strokes.isEmpty)
                Button("やり直し") { canvas.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(canvas.redoStack.isEmpty)
            }
        }
    }
}

enum AppIcon {
    static func handleExportArgIfNeeded() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--export-iconset"), i + 1 < args.count else { return }
        let dir = args[i + 1]
        let fm = FileManager.default
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let sizes: [(name: String, px: Int)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32),
            ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256),
            ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024)
        ]
        for s in sizes {
            let img = make(size: CGFloat(s.px))
            guard let tiff = img.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(s.name).png")
            try? png.write(to: url)
        }
        exit(0)
    }

    static func make(size: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            img.unlockFocus(); return img
        }

        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        let radius = size * 0.22
        let bgPath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.addPath(bgPath)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillPath()

        let stripeH = size / 6
        let colors: [NSColor] = [
            NSColor.systemRed, .systemOrange, .systemYellow,
            .systemGreen, .systemBlue, .systemPurple
        ]
        ctx.saveGState()
        ctx.addPath(bgPath)
        ctx.clip()
        for (i, c) in colors.enumerated() {
            ctx.setFillColor(c.withAlphaComponent(0.85).cgColor)
            ctx.fill(CGRect(x: 0, y: CGFloat(i) * stripeH, width: size, height: stripeH))
        }
        ctx.restoreGState()

        ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: size * 0.04, dy: size * 0.04),
                           cornerWidth: radius * 0.85, cornerHeight: radius * 0.85, transform: nil))
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.setLineWidth(size * 0.012)
        ctx.strokePath()

        let brushColor = NSColor.black
        ctx.saveGState()
        ctx.translateBy(x: size * 0.5, y: size * 0.5)
        ctx.rotate(by: -.pi / 4)
        let bw = size * 0.12, bh = size * 0.55
        let brushRect = CGRect(x: -bw / 2, y: -bh / 2, width: bw, height: bh)
        ctx.setFillColor(brushColor.cgColor)
        ctx.addPath(CGPath(roundedRect: brushRect, cornerWidth: bw * 0.25, cornerHeight: bw * 0.25, transform: nil))
        ctx.fillPath()

        let tip = CGMutablePath()
        tip.move(to: CGPoint(x: -bw / 2, y: bh / 2))
        tip.addLine(to: CGPoint(x: bw / 2, y: bh / 2))
        tip.addLine(to: CGPoint(x: 0, y: bh / 2 + bw * 1.1))
        tip.closeSubpath()
        ctx.addPath(tip)
        ctx.setFillColor(NSColor.systemPink.cgColor)
        ctx.fillPath()

        let metal = CGRect(x: -bw / 2, y: -bh / 2 + bh * 0.55, width: bw, height: bh * 0.1)
        ctx.setFillColor(NSColor.systemGray.cgColor)
        ctx.fill(metal)
        ctx.restoreGState()

        img.unlockFocus()
        return img
    }
}
