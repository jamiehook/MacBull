// Renders the MacBull app icon (a white bull head on an energetic gradient
// squircle) to a PNG. Geometry is authored in a 1024-pt design space and
// scaled to the requested output size.
//
//   swift make_icon.swift <out.png> [size]
//
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "master.png"
let outSize = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) ?? 1024 : 1024

let space = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: outSize, height: outSize,
                          bitsPerComponent: 8, bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("could not create context")
}

ctx.scaleBy(x: CGFloat(outSize) / 1024.0, y: CGFloat(outSize) / 1024.0)
ctx.setShouldAntialias(true)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

// ---- background squircle with diagonal energy gradient ----
let margin: CGFloat = 92
let body = CGRect(x: margin, y: margin, width: 1024 - 2 * margin, height: 1024 - 2 * margin)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 224, cornerHeight: 224, transform: nil)

ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
let gradient = CGGradient(colorsSpace: space,
                          colors: [rgb(255, 64, 87), rgb(255, 138, 0)] as CFArray,
                          locations: [0, 1])!
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: body.minX, y: body.maxY),
                       end: CGPoint(x: body.maxX, y: body.minY),
                       options: [])
ctx.restoreGState()

// ---- bull head ----
func mirror(_ path: CGPath) -> CGPath {
    var t = CGAffineTransform(translationX: 1024, y: 0).scaledBy(x: -1, y: 1)
    return path.copy(using: &t) ?? path
}

// Snout: an upward-pointing rounded triangle / shield for the lower face.
let face = CGMutablePath()
face.addEllipse(in: CGRect(x: 512 - 175, y: 300, width: 350, height: 360))

// A smooth horn built by sweeping a tapering width along a quadratic-Bézier
// spine (base → control → tip). Thickness is full at the base and tapers to a
// point, so the result is always a solid, bull-like horn regardless of curve.
// `reversed` flips the traversal order (and thus the winding). A reflected horn
// has its winding flipped by the mirror; reversing one of the pair keeps both
// wound the same way as the head, so their union fills with no notch.
func horn(base: CGPoint, control: CGPoint, tip: CGPoint,
          baseWidth: CGFloat, taper: CGFloat = 1.2, reversed: Bool = false,
          steps: Int = 56) -> CGPath {
    func point(_ t: CGFloat) -> CGPoint {
        let m = 1 - t
        return CGPoint(x: m*m*base.x + 2*m*t*control.x + t*t*tip.x,
                       y: m*m*base.y + 2*m*t*control.y + t*t*tip.y)
    }
    func tangent(_ t: CGFloat) -> CGPoint {
        CGPoint(x: 2*(1-t)*(control.x-base.x) + 2*t*(tip.x-control.x),
                y: 2*(1-t)*(control.y-base.y) + 2*t*(tip.y-control.y))
    }
    var leftEdge: [CGPoint] = [], rightEdge: [CGPoint] = []
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps)
        let s = point(t)
        var d = tangent(t)
        let len = max(0.0001, hypot(d.x, d.y)); d.x /= len; d.y /= len
        let half = (baseWidth / 2) * pow(1 - t, taper)
        leftEdge.append(CGPoint(x: s.x - d.y*half, y: s.y + d.x*half))
        rightEdge.append(CGPoint(x: s.x + d.y*half, y: s.y - d.x*half))
    }
    var outline = leftEdge + rightEdge.reversed()
    if reversed { outline.reverse() }
    let p = CGMutablePath()
    p.move(to: outline[0])
    outline.dropFirst().forEach { p.addLine(to: $0) }
    p.closeSubpath()
    return p
}

// Horns emerge from the sides of the crown pointing out, then sweep up to sharp
// tips — a longhorn splay. Each is built from its own (mirrored) coordinates so
// both wind the same way as the head; `reversed` on the right cancels the
// orientation flip that mirroring the x-axis introduces, so the union has no notch.
let rightHorn = horn(base: CGPoint(x: 560, y: 578),
                     control: CGPoint(x: 772, y: 648),
                     tip: CGPoint(x: 910, y: 808),
                     baseWidth: 150, reversed: true)
let leftHorn = horn(base: CGPoint(x: 464, y: 578),
                    control: CGPoint(x: 252, y: 648),
                    tip: CGPoint(x: 114, y: 808),
                    baseWidth: 150, reversed: false)

// Soft ambient shadow for depth: fill the pieces in a dark tone (each separately
// so winding never matters), then paint the white silhouette exactly on top —
// only the shadow that escapes beyond the silhouette remains, with no inner seam.
let pieces = [face, rightHorn, leftHorn]

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 34, color: rgb(90, 0, 0, 0.32))
ctx.setFillColor(rgb(90, 0, 0, 1))
for piece in pieces { ctx.addPath(piece); ctx.fillPath() }
ctx.restoreGState()

ctx.setFillColor(rgb(255, 255, 255))
for piece in pieces { ctx.addPath(piece); ctx.fillPath() }

// ---- facial features punched in the gradient's deep tone ----
let accent = rgb(196, 38, 30)

ctx.setFillColor(accent)
for cx in [446.0, 578.0] {                                    // eyes
    ctx.addEllipse(in: CGRect(x: cx - 32, y: 452, width: 64, height: 78))
}
ctx.fillPath()

ctx.setFillColor(accent)
for cx in [482.0, 542.0] {                                    // nostrils
    ctx.addEllipse(in: CGRect(x: cx - 20, y: 348, width: 40, height: 30))
}
ctx.fillPath()

// ---- write PNG ----
guard let image = ctx.makeImage() else { fatalError("could not render image") }
let url = URL(fileURLWithPath: outPath)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("could not create \(outPath)")
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(outPath)") }
print("wrote \(outPath) at \(outSize)px")
