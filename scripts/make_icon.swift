import AppKit

let size = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
rep.size = NSSize(width: size, height: size)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let rect = NSRect(x: 0, y: 0, width: size, height: size)
let top = NSColor(red: 0.32, green: 0.66, blue: 0.48, alpha: 1)      // #52a97a-ish
let bottom = NSColor(red: 0.13, green: 0.36, blue: 0.26, alpha: 1)   // #214d43-ish
NSGradient(starting: top, ending: bottom)!.draw(in: rect, angle: -70)

// subtle rising line (progress) behind the figure
let path = NSBezierPath()
path.move(to: NSPoint(x: 120, y: 330))
path.line(to: NSPoint(x: 330, y: 420))
path.line(to: NSPoint(x: 520, y: 360))
path.line(to: NSPoint(x: 900, y: 700))
path.lineWidth = 34
path.lineCapStyle = .round
path.lineJoinStyle = .round
NSColor.white.withAlphaComponent(0.22).setStroke()
path.stroke()

let cfg = NSImage.SymbolConfiguration(pointSize: 540, weight: .semibold)
if let sym = NSImage(systemSymbolName: "figure.strengthtraining.traditional", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
    let tinted = NSImage(size: sym.size, flipped: false) { r in
        sym.draw(in: r)
        NSColor.white.set()
        r.fill(using: .sourceAtop)
        return true
    }
    let s = tinted.size
    let scale = 640 / max(s.width, s.height)
    let w = s.width * scale, h = s.height * scale
    tinted.draw(in: NSRect(x: (CGFloat(size) - w) / 2, y: (CGFloat(size) - h) / 2 + 10, width: w, height: h),
                from: .zero, operation: .sourceOver, fraction: 1)
}
NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
