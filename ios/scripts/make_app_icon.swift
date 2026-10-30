// Draws the 1024x1024 app icon: a gold pawn on the dark theme background over
// a faint board. Opaque (App Store icons may not have alpha).
//
//   swift ios/scripts/make_app_icon.swift ios/ChessDashboard/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png")

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
	CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(
	data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
	bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let s = CGFloat(size)

// Background: theme card (#1c1c1e) at the top fading to theme bg (#0a0a0c).
let bg = CGGradient(colorsSpace: space, colors: [rgb(34, 34, 38), rgb(10, 10, 12)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])

// A faint board under the piece, fading out upward.
let squares = 8
let cell = s / CGFloat(squares)
for row in 0..<3 {
	for col in 0..<squares where (row + col) % 2 == 0 {
		let fade = CGFloat(3 - row) / 3
		ctx.setFillColor(rgb(89, 93, 102, 0.22 * fade))
		ctx.fill(CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell))
	}
}

// The pawn (y grows upward in CoreGraphics), as separate overlapping parts.
let cx = s / 2
var parts: [CGPath] = []
// Base plinth.
parts.append(CGPath(roundedRect: CGRect(x: cx - 250, y: 150, width: 500, height: 70), cornerWidth: 30, cornerHeight: 30, transform: nil))
parts.append(CGPath(roundedRect: CGRect(x: cx - 205, y: 205, width: 410, height: 60), cornerWidth: 26, cornerHeight: 26, transform: nil))
// Body: concave flanks rising from the base to the collar.
let body = CGMutablePath()
body.move(to: CGPoint(x: cx - 180, y: 255))
body.addCurve(to: CGPoint(x: cx - 75, y: 560), control1: CGPoint(x: cx - 90, y: 330), control2: CGPoint(x: cx - 70, y: 450))
body.addLine(to: CGPoint(x: cx + 75, y: 560))
body.addCurve(to: CGPoint(x: cx + 180, y: 255), control1: CGPoint(x: cx + 70, y: 450), control2: CGPoint(x: cx + 90, y: 330))
body.closeSubpath()
parts.append(body)
// Collar.
parts.append(CGPath(roundedRect: CGRect(x: cx - 140, y: 540, width: 280, height: 56), cornerWidth: 28, cornerHeight: 28, transform: nil))
// Head.
parts.append(CGPath(ellipseIn: CGRect(x: cx - 125, y: 575, width: 250, height: 250), transform: nil))

// Gold gradient fill: theme accent (#d9a13d), lighter at the top. Each part
// is clipped and filled on its own (one path would cancel the overlaps), all
// in one layer so the glow is cast once by the whole silhouette.
let gold = CGGradient(
	colorsSpace: space, colors: [rgb(247, 212, 140), rgb(217, 161, 61), rgb(150, 101, 28)] as CFArray,
	locations: [0, 0.5, 1])!
ctx.setShadow(offset: .zero, blur: 90, color: rgb(217, 161, 61, 0.35))
ctx.beginTransparencyLayer(auxiliaryInfo: nil)
for part in parts {
	ctx.saveGState()
	ctx.addPath(part)
	ctx.clip()
	ctx.drawLinearGradient(
		gold, start: CGPoint(x: cx - 200, y: 830), end: CGPoint(x: cx + 200, y: 150),
		options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
	ctx.restoreGState()
}
ctx.endTransparencyLayer()

let image = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(out.path)") }
print("wrote \(out.path)")
