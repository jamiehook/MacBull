// Renders the two menu-bar glyph states as template PDFs (black vector on a
// transparent page — the system recolors template images for light/dark and
// highlights). Also emits a preview PNG showing both states at real menu-bar
// sizes on light and dark bars, for eyeballing legibility.
//
//   swift make_menubar.swift
//   => menubar-awake.pdf  menubar-asleep.pdf  menubar-preview.png
//
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Swept tapered horn — same construction as the app icon.
func horn(base: CGPoint, control: CGPoint, tip: CGPoint, baseWidth: CGFloat,
          taper: CGFloat = 1.2, reversed: Bool = false, steps: Int = 48) -> CGPath {
    func pt(_ t: CGFloat) -> CGPoint {
        let m = 1 - t
        return CGPoint(x: m*m*base.x + 2*m*t*control.x + t*t*tip.x,
                       y: m*m*base.y + 2*m*t*control.y + t*t*tip.y)
    }
    func tan(_ t: CGFloat) -> CGPoint {
        CGPoint(x: 2*(1-t)*(control.x-base.x) + 2*t*(tip.x-control.x),
                y: 2*(1-t)*(control.y-base.y) + 2*t*(tip.y-control.y))
    }
    var l: [CGPoint] = [], r: [CGPoint] = []
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps)
        let s = pt(t); var d = tan(t)
        let len = max(0.0001, hypot(d.x, d.y)); d.x /= len; d.y /= len
        let h = (baseWidth / 2) * pow(1 - t, taper)
        l.append(CGPoint(x: s.x - d.y*h, y: s.y + d.x*h))
        r.append(CGPoint(x: s.x + d.y*h, y: s.y - d.x*h))
    }
    var o = l + r.reversed(); if reversed { o.reverse() }
    let p = CGMutablePath(); p.move(to: o[0]); o.dropFirst().forEach { p.addLine(to: $0) }
    p.closeSubpath(); return p
}

enum BullState { case awake, asleep }

// Draw the glyph in a 100×100 design space scaled to S, in `color`.
func drawBull(_ ctx: CGContext, _ S: CGFloat, _ state: BullState, _ color: CGColor) {
    ctx.saveGState()
    ctx.scaleBy(x: S / 100, y: S / 100)
    ctx.setFillColor(color); ctx.setStrokeColor(color)
    ctx.setLineCap(.round); ctx.setLineJoin(.round)

    // Head + two horns, each filled separately (winding-safe).
    let head = CGPath(ellipseIn: CGRect(x: 31, y: 14, width: 38, height: 40), transform: nil)
    let rHorn = horn(base: CGPoint(x: 57, y: 46), control: CGPoint(x: 82, y: 52),
                     tip: CGPoint(x: 95, y: 80), baseWidth: 18, reversed: true)
    let lHorn = horn(base: CGPoint(x: 43, y: 46), control: CGPoint(x: 18, y: 52),
                     tip: CGPoint(x: 5, y: 80), baseWidth: 18, reversed: false)
    for p in [head, rHorn, lHorn] { ctx.addPath(p); ctx.fillPath() }

    switch state {
    case .asleep:
        // a "z" floating in the gap above the head → sleeping
        ctx.setLineWidth(3.6)
        let z = CGMutablePath()
        z.move(to: CGPoint(x: 43, y: 86)); z.addLine(to: CGPoint(x: 57, y: 86))
        z.addLine(to: CGPoint(x: 43, y: 70)); z.addLine(to: CGPoint(x: 57, y: 70))
        ctx.addPath(z); ctx.strokePath()
    case .awake:
        // two steam curls rising above the head → snorting / raging
        ctx.setLineWidth(4.4)
        let a = CGMutablePath(); a.move(to: CGPoint(x: 44, y: 59))
        a.addCurve(to: CGPoint(x: 46, y: 85), control1: CGPoint(x: 35, y: 68), control2: CGPoint(x: 55, y: 76))
        let b = CGMutablePath(); b.move(to: CGPoint(x: 56, y: 59))
        b.addCurve(to: CGPoint(x: 54, y: 85), control1: CGPoint(x: 65, y: 68), control2: CGPoint(x: 45, y: 76))
        ctx.addPath(a); ctx.addPath(b); ctx.strokePath()
    }
    ctx.restoreGState()
}

let rgb = CGColorSpaceCreateDeviceRGB()
let black = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)

// --- ship: template PDFs (18pt, transparent, vector → crisp at any size) ---
func writePDF(_ path: String, _ state: BullState) {
    var box = CGRect(x: 0, y: 0, width: 18, height: 18)
    guard let consumer = CGDataConsumer(url: URL(fileURLWithPath: path) as CFURL),
          let pdf = CGContext(consumer: consumer, mediaBox: &box, nil) else { fatalError("pdf") }
    pdf.beginPDFPage(nil)
    drawBull(pdf, 18, state, black)
    pdf.endPDFPage(); pdf.closePDF()
    print("wrote \(path)")
}
writePDF("menubar-awake.pdf", .awake)
writePDF("menubar-asleep.pdf", .asleep)

// --- preview: both states at menu sizes on a light and a dark bar ---
let PW = 520, PH = 200
guard let pv = CGContext(data: nil, width: PW, height: PH, bitsPerComponent: 8,
                         bytesPerRow: 0, space: rgb,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("pv") }
pv.setShouldAntialias(true)
pv.setFillColor(CGColor(red: 0.93, green: 0.93, blue: 0.94, alpha: 1)); pv.fill(CGRect(x: 0, y: PH/2, width: PW, height: PH/2))
pv.setFillColor(CGColor(red: 0.15, green: 0.15, blue: 0.16, alpha: 1)); pv.fill(CGRect(x: 0, y: 0, width: PW, height: PH/2))

func place(_ state: BullState, _ size: CGFloat, cx: CGFloat, top: Bool) {
    let color = top ? black : white
    let midY = top ? CGFloat(PH) * 0.75 : CGFloat(PH) * 0.25
    pv.saveGState()
    pv.translateBy(x: cx - size/2, y: midY - size/2)
    drawBull(pv, size, state, color)
    pv.restoreGState()
}

let sizes: [CGFloat] = [44, 28, 18]
var x: CGFloat = 44
for s in sizes {
    for top in [true, false] {
        place(.awake,  s, cx: x,            top: top)
        place(.asleep, s, cx: x + s + 34,   top: top)
    }
    x += s*2 + 96
}

let url = URL(fileURLWithPath: "menubar-preview.png")
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, pv.makeImage()!, nil)
CGImageDestinationFinalize(dest)
print("wrote menubar-preview.png  (awake | asleep, sizes 44/28/18, light & dark)")
