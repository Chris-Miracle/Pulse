// Renders the Pulse app icon (1024x1024 PNG).
// Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

// macOS icon grid: 824pt rounded square centred on a 1024 canvas
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

// Drop shadow under the tile
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.35))
ctx.addPath(tilePath)
ctx.setFillColor(rgb(0x0B1E33))
ctx.fillPath()
ctx.restoreGState()

// Background gradient: deep navy to teal
ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: [rgb(0x0A1A2F), rgb(0x0E3B4F), rgb(0x0F5C5A)] as CFArray,
                    locations: [0, 0.55, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: tile.minX, y: tile.maxY),
                       end: CGPoint(x: tile.maxX, y: tile.minY), options: [])

// Faint grid lines, like a monitor screen
ctx.setStrokeColor(rgb(0xFFFFFF, 0.05))
ctx.setLineWidth(3)
var g = tile.minX + 103
while g < tile.maxX {
    ctx.move(to: CGPoint(x: g, y: tile.minY)); ctx.addLine(to: CGPoint(x: g, y: tile.maxY))
    ctx.move(to: CGPoint(x: tile.minX, y: g)); ctx.addLine(to: CGPoint(x: tile.maxX, y: g))
    g += 103
}
ctx.strokePath()

// Soft highlight on the top half
let shine = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                       colors: [rgb(0xFFFFFF, 0.10), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(shine, start: CGPoint(x: 512, y: tile.maxY), end: CGPoint(x: 512, y: 512), options: [])

// Pulse (ECG) line, in tile-relative coordinates (0...1)
let pts: [(CGFloat, CGFloat)] = [
    (0.00, 0.50), (0.22, 0.50),
    (0.27, 0.56), (0.32, 0.50),          // small P wave
    (0.38, 0.50), (0.42, 0.42),          // dip
    (0.50, 0.84),                        // spike up
    (0.57, 0.20),                        // drop down
    (0.62, 0.50), (0.68, 0.50),
    (0.74, 0.60), (0.80, 0.50),          // T wave
    (1.00, 0.50),
]
let line = CGMutablePath()
for (i, p) in pts.enumerated() {
    let pt = CGPoint(x: tile.minX + p.0 * tile.width, y: tile.minY + p.1 * tile.height)
    i == 0 ? line.move(to: pt) : line.addLine(to: pt)
}

let pulseGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [rgb(0x34E0A1), rgb(0x3DF5C8), rgb(0x5CC8FF)] as CFArray,
                               locations: [0, 0.5, 1])!

func strokePulse(width: CGFloat, glow: CGFloat, alpha: CGFloat) {
    ctx.saveGState()
    if glow > 0 { ctx.setShadow(offset: .zero, blur: glow, color: rgb(0x3DF5C8, 0.9)) }
    ctx.setAlpha(alpha)
    ctx.addPath(line)
    ctx.setLineWidth(width)
    ctx.setLineJoin(.round)
    ctx.setLineCap(.round)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(pulseGradient, start: CGPoint(x: tile.minX, y: 512),
                           end: CGPoint(x: tile.maxX, y: 512), options: [])
    ctx.restoreGState()
}

// Glow halo, then the crisp line on top
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 60, color: rgb(0x3DF5C8, 0.8))
ctx.addPath(line)
ctx.setStrokeColor(rgb(0x3DF5C8, 0.5))
ctx.setLineWidth(40)
ctx.setLineJoin(.round)
ctx.setLineCap(.round)
ctx.strokePath()
ctx.restoreGState()
strokePulse(width: 44, glow: 0, alpha: 1)

// Bright dot at the peak
let peak = CGPoint(x: tile.minX + 0.50 * tile.width, y: tile.minY + 0.84 * tile.height)
ctx.setShadow(offset: .zero, blur: 30, color: rgb(0xFFFFFF, 0.9))
ctx.setFillColor(rgb(0xFFFFFF))
ctx.fillEllipse(in: CGRect(x: peak.x - 22, y: peak.y - 22, width: 44, height: 44))
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")
