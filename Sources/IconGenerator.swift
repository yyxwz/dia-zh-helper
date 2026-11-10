import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else { exit(2) }
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

let background = NSBezierPath(roundedRect: NSRect(x: 48, y: 48, width: 928, height: 928), xRadius: 210, yRadius: 210)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.25, green: 0.27, blue: 0.95, alpha: 1),
    NSColor(calibratedRed: 0.50, green: 0.22, blue: 0.92, alpha: 1)
])!
gradient.draw(in: background, angle: -45)

let glow = NSBezierPath(ovalIn: NSRect(x: 620, y: 620, width: 310, height: 310))
NSColor.white.withAlphaComponent(0.16).setFill()
glow.fill()

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 560, weight: .bold),
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraph
]
let text = NSAttributedString(string: "中", attributes: attributes)
text.draw(in: NSRect(x: 110, y: 205, width: 804, height: 650))

image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else { exit(3) }
try png.write(to: destination)
