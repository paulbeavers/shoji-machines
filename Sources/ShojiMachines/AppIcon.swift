import AppKit

/// The app icon: Shoji's panes, with server-rack lines in the active one.
@MainActor
enum AppIcon {
    static func render(to path: String) {
        let s: CGFloat = 1024
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(s), pixelsHigh: Int(s), bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let card = NSBezierPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
        NSColor(hex: 0x11111B).setFill()
        card.fill()
        let panes = [CGRect(x: 190, y: 190, width: 370, height: 644),
                     CGRect(x: 600, y: 532, width: 234, height: 302),
                     CGRect(x: 600, y: 190, width: 234, height: 302)]
        for (i, r) in panes.enumerated() {
            let p = NSBezierPath(roundedRect: r, xRadius: 36, yRadius: 36)
            NSColor(hex: 0x1E1E2E).setFill()
            p.fill()
            p.lineWidth = 22
            if i == 0 {
                NSGradient(colors: [NSColor(hex: 0xCBA6F7), NSColor(hex: 0x89B4FA)])?.draw(in: p.copy() as! NSBezierPath, angle: -45)
                NSColor(hex: 0x1E1E2E).setFill()
                NSBezierPath(roundedRect: r.insetBy(dx: 16, dy: 16), xRadius: 24, yRadius: 24).fill()
                // Three server units with status lights.
                for k in 0..<3 {
                    let unit = CGRect(x: r.minX + 60, y: r.minY + 120 + CGFloat(k) * 150, width: r.width - 120, height: 100)
                    NSColor(hex: 0x313244).setFill()
                    NSBezierPath(roundedRect: unit, xRadius: 18, yRadius: 18).fill()
                    NSColor(hex: k == 2 ? 0xA6E3A1 : 0x89B4FA).setFill()
                    NSBezierPath(ovalIn: CGRect(x: unit.maxX - 70, y: unit.midY - 16, width: 32, height: 32)).fill()
                }
            } else {
                NSColor(hex: 0x45475A).setStroke()
                p.stroke()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
