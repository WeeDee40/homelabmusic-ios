// Zeichnet die Glas-Ebene des App-Symbols (weiss auf transparent, 1024 × 1024):
// Haus-Umriss mit Musiknote. Aufruf: xcrun swift Helper/homelab/icon_zeichnen.swift <ziel.png>
import AppKit
import CoreGraphics

let n = 1024
let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.translateBy(x: 0, y: CGFloat(n)); ctx.scaleBy(x: 1, y: -1)          // y nach unten
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.setLineCap(.round); ctx.setLineJoin(.round)

// Haus: Dach und Wände als ein Linienzug
ctx.setLineWidth(64)
ctx.move(to: CGPoint(x: 300, y: 470))
ctx.addLine(to: CGPoint(x: 300, y: 790))
ctx.addLine(to: CGPoint(x: 724, y: 790))
ctx.addLine(to: CGPoint(x: 724, y: 470))
ctx.strokePath()
ctx.move(to: CGPoint(x: 200, y: 540))
ctx.addLine(to: CGPoint(x: 512, y: 250))
ctx.addLine(to: CGPoint(x: 824, y: 540))
ctx.strokePath()

// Musiknote: zwei Köpfe mit Balken
ctx.setLineWidth(40)
ctx.fillEllipse(in: CGRect(x: 392, y: 628, width: 92, height: 76))
ctx.fillEllipse(in: CGRect(x: 552, y: 600, width: 92, height: 76))
ctx.move(to: CGPoint(x: 466, y: 666)); ctx.addLine(to: CGPoint(x: 466, y: 470)); ctx.strokePath()
ctx.move(to: CGPoint(x: 626, y: 638)); ctx.addLine(to: CGPoint(x: 626, y: 442)); ctx.strokePath()
ctx.setLineWidth(52)
ctx.move(to: CGPoint(x: 466, y: 476)); ctx.addLine(to: CGPoint(x: 626, y: 448)); ctx.strokePath()

let bild = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: bild)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("geschrieben:", CommandLine.arguments[1])
