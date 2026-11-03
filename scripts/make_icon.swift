import CoreGraphics
import Foundation
import ImageIO

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let set = output.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
let space = CGColorSpaceCreateDeviceRGB()
for base in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let size = base * factor
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                bytesPerRow: size * 4, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
        context.addPath(CGPath(roundedRect: CGRect(x: 64, y: 64, width: 896, height: 896),
                               cornerWidth: 204, cornerHeight: 204, transform: nil))
        context.clip()
        let gradient = CGGradient(colorsSpace: space, colors: [
            CGColor(red: 0.08, green: 0.14, blue: 0.22, alpha: 1),
            CGColor(red: 0.015, green: 0.03, blue: 0.055, alpha: 1)
        ] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 160, y: 900),
                                   end: CGPoint(x: 850, y: 120), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.setFillColor(CGColor(red: 0.0, green: 0.01, blue: 0.02, alpha: 1))
        context.addPath(CGPath(roundedRect: CGRect(x: 154, y: 390, width: 716, height: 244),
                               cornerWidth: 60, cornerHeight: 60, transform: nil))
        context.fillPath()
        context.setStrokeColor(CGColor(red: 0.28, green: 0.95, blue: 0.78, alpha: 1))
        context.setLineWidth(30)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.move(to: CGPoint(x: 218, y: 512))
        for point in [(285, 512), (325, 558), (365, 478), (405, 530), (445, 512), (566, 512)] {
            context.addLine(to: CGPoint(x: point.0, y: point.1))
        }
        context.strokePath()
        context.setStrokeColor(CGColor(gray: 0.96, alpha: 1))
        context.setLineWidth(26)
        context.addArc(center: CGPoint(x: 727, y: 507), radius: 54,
                       startAngle: .pi * 0.23, endAngle: .pi * 0.77, clockwise: true)
        context.strokePath()
        context.move(to: CGPoint(x: 727, y: 568))
        context.addLine(to: CGPoint(x: 727, y: 511))
        context.strokePath()
        let suffix = factor == 2 ? "@2x" : ""
        let url = set.appendingPathComponent("icon_\(base)x\(base)\(suffix).png")
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        guard CGImageDestinationFinalize(destination) else { fatalError("Cannot write app icon") }
    }
}
