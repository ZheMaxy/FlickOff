// Draws the 1280x640 image shown when the repository or website is shared.
//   swift scripts/make_social_preview.swift docs/images/icon.png docs/images/menu.png docs/images/social-preview.png
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 4, let icon = NSImage(contentsOfFile: arguments[1]), let menu = NSImage(contentsOfFile: arguments[2]) else {
    fatalError("usage: make_social_preview.swift <icon> <menu screenshot> <output>")
}
let width = 1280, height = 640
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                              hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
bitmap.size = NSSize(width: width, height: height)
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

NSGradient(starting: NSColor(red: 0.08, green: 0.14, blue: 0.22, alpha: 1), ending: NSColor(red: 0.015, green: 0.03, blue: 0.055, alpha: 1))!
    .draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -40)

icon.draw(in: NSRect(x: 72, y: 448, width: 112, height: 112))

func text(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, in rect: NSRect) {
    let style = NSMutableParagraphStyle()
    style.lineHeightMultiple = 1.08
    NSAttributedString(string: string, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style,
    ]).draw(with: rect, options: [.usesLineFragmentOrigin])
}
text("FlickOff", size: 76, weight: .bold, color: .white, in: NSRect(x: 200, y: 450, width: 560, height: 100))
text("Touch Bar flickering?\nKeep your Mac. Lose the flicker.", size: 42, weight: .semibold, color: NSColor(red: 0.28, green: 0.95, blue: 0.78, alpha: 1),
     in: NSRect(x: 72, y: 300, width: 760, height: 120))
text("Set Touch Bar brightness separately from the screen,\nor turn its display off. For Apple silicon MacBook Pro.",
     size: 28, weight: .regular, color: NSColor(white: 0.82, alpha: 1), in: NSRect(x: 72, y: 170, width: 760, height: 90))

let scale = 540 / menu.size.height
let frame = NSRect(x: CGFloat(width) - 56 - menu.size.width * scale, y: 50, width: menu.size.width * scale, height: 540)
let shadow = NSShadow()
shadow.shadowColor = NSColor(white: 0, alpha: 0.6)
shadow.shadowBlurRadius = 32
shadow.shadowOffset = NSSize(width: 0, height: -10)
NSGraphicsContext.saveGraphicsState()
shadow.set()
menu.draw(in: frame)
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.current = nil
guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode the image") }
try data.write(to: URL(fileURLWithPath: arguments[3]))
