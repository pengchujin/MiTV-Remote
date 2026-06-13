import AppKit

guard CommandLine.arguments.count == 2 else {
    fputs("usage: generate_app_icon.swift OUTPUT_PNG\n", stderr)
    exit(2)
}

let canvasSize = NSSize(width: 1024, height: 1024)
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize.width),
    pixelsHigh: Int(canvasSize.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("failed to create bitmap context\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("failed to create graphics context\n", stderr)
    exit(1)
}
NSGraphicsContext.current = context
defer {
    NSGraphicsContext.restoreGraphicsState()
}

let background = NSBezierPath(
    roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880),
    xRadius: 210,
    yRadius: 210
)
NSColor(calibratedRed: 0.95, green: 0.16, blue: 0.12, alpha: 1).setFill()
background.fill()

let remoteShadow = NSBezierPath(
    roundedRect: NSRect(x: 330, y: 178, width: 380, height: 680),
    xRadius: 150,
    yRadius: 150
)
NSColor(calibratedWhite: 0, alpha: 0.15).setFill()
remoteShadow.fill()

let remote = NSBezierPath(
    roundedRect: NSRect(x: 310, y: 198, width: 380, height: 680),
    xRadius: 150,
    yRadius: 150
)
NSColor.white.setFill()
remote.fill()

NSColor(calibratedRed: 0.95, green: 0.16, blue: 0.12, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 422, y: 642, width: 156, height: 156)).fill()

let ring = NSBezierPath(ovalIn: NSRect(x: 397, y: 392, width: 206, height: 206))
ring.lineWidth = 34
NSColor(calibratedRed: 0.95, green: 0.16, blue: 0.12, alpha: 1).setStroke()
ring.stroke()

NSBezierPath(ovalIn: NSRect(x: 463, y: 458, width: 74, height: 74)).fill()
NSBezierPath(ovalIn: NSRect(x: 454, y: 282, width: 92, height: 92)).fill()

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 82, weight: .heavy),
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraph
]
"MI".draw(in: NSRect(x: 398, y: 664, width: 204, height: 100), withAttributes: attributes)

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("failed to render app icon\n", stderr)
    exit(1)
}

try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
