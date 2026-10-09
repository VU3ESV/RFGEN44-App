// Draws the 1024×1024 app icon (a sine carrier on a dark rounded square).
// Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Background: macOS icon grid inset with a deep blue gradient.
let inset: CGFloat = 100
let rect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let shape = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.addPath(shape)
ctx.clip()
let colors = [NSColor(red: 0.05, green: 0.10, blue: 0.22, alpha: 1).cgColor,
              NSColor(red: 0.07, green: 0.30, blue: 0.45, alpha: 1).cgColor] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY), options: [])

// Faint graticule.
ctx.setStrokeColor(NSColor(white: 1, alpha: 0.08).cgColor)
ctx.setLineWidth(4)
for i in 1..<8 {
    let x = rect.minX + rect.width * CGFloat(i) / 8
    let y = rect.minY + rect.height * CGFloat(i) / 8
    ctx.move(to: CGPoint(x: x, y: rect.minY)); ctx.addLine(to: CGPoint(x: x, y: rect.maxY))
    ctx.move(to: CGPoint(x: rect.minX, y: y)); ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
}
ctx.strokePath()

// Carrier.
let wave = CGMutablePath()
let midY = rect.midY + 40
for step in 0...400 {
    let t = CGFloat(step) / 400
    let x = rect.minX + 70 + t * (rect.width - 140)
    let y = midY + sin(t * .pi * 6) * 150
    if step == 0 { wave.move(to: CGPoint(x: x, y: y)) } else { wave.addLine(to: CGPoint(x: x, y: y)) }
}
ctx.setShadow(offset: .zero, blur: 40, color: NSColor(red: 1, green: 0.6, blue: 0.1, alpha: 0.9).cgColor)
ctx.setStrokeColor(NSColor(red: 1, green: 0.72, blue: 0.25, alpha: 1).cgColor)
ctx.setLineWidth(34)
ctx.setLineCap(.round)
ctx.addPath(wave)
ctx.strokePath()
ctx.restoreGState()

// Label.
let label = "RFGEN44" as NSString
let font = NSFont.systemFont(ofSize: 112, weight: .heavy)
let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(white: 1, alpha: 0.92)]
let textSize = label.size(withAttributes: attrs)
label.draw(at: CGPoint(x: (size - textSize.width) / 2, y: rect.minY + 70), withAttributes: attrs)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")
