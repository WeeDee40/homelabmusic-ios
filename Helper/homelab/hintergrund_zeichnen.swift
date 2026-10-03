// Hintergrundebene des App-Symbols: Farbverlauf Indigo -> Violett wie die Wochenmix-Cover (1024 × 1024).
// Aufruf: xcrun swift Helper/homelab/hintergrund_zeichnen.swift <ziel.png>
import AppKit
let n = 1024
let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [
  CGColor(red: 0.30, green: 0.24, blue: 0.86, alpha: 1),
  CGColor(red: 0.55, green: 0.32, blue: 0.92, alpha: 1),
  CGColor(red: 0.85, green: 0.40, blue: 0.86, alpha: 1)] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: CGFloat(n)), end: CGPoint(x: CGFloat(n), y: 0), options: [])
try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
  .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
