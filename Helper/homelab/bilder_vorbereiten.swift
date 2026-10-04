// Bereitet die HLM-Bilder auf: App-Symbol (randlos zugeschnitten), freigestelltes HLM-Zeichen (weiss auf
// transparent, für Anmeldeseite) und das Startbild.
// Aufruf: xcrun swift Helper/homelab/bilder_vorbereiten.swift <symbol.jpg> <startbild.jpg> <zielordner>
import AppKit
import CoreGraphics

let a = CommandLine.arguments
let symbol = NSImage(contentsOfFile: a[1])!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let start = NSImage(contentsOfFile: a[2])!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let ziel = a[3]

func speichern(_ bild: CGImage, _ name: String) {
  try! NSBitmapImageRep(cgImage: bild).representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: ziel + "/" + name))
  print("geschrieben:", name, bild.width, "x", bild.height)
}

func leinwand(_ n: Int) -> CGContext {
  CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

// 1. App-Symbol: Quadrat innerhalb des abgerundeten Rechtecks (ohne schwarze Ecken), auf 1024 skaliert
let quadrat = symbol.cropping(to: CGRect(x: 140, y: 175, width: 945, height: 945))!
let c1 = leinwand(1024)
c1.interpolationQuality = .high
c1.draw(quadrat, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
speichern(c1.makeImage()!, "symbol.png")

// 2. HLM-Zeichen freistellen: Helligkeit -> Deckkraft, weiss
let ausschnitt = symbol.cropping(to: CGRect(x: 225, y: 355, width: 760, height: 580))!
let w = ausschnitt.width, h = ausschnitt.height
var px = [UInt8](repeating: 0, count: w * h * 4)
let c2 = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                   space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
c2.draw(ausschnitt, in: CGRect(x: 0, y: 0, width: w, height: h))
for i in stride(from: 0, to: px.count, by: 4) {
  let minimum = Double(min(px[i], px[i + 1], px[i + 2]))        // Rot hat wenig Grün/Blau, Weiss viel
  let deck = UInt8(max(0, min(255, (minimum - 90) / (225 - 90) * 255)))
  px[i] = deck; px[i + 1] = deck; px[i + 2] = deck; px[i + 3] = deck   // vormultipliziert: weiss
}
let zeichen = c2.makeImage()!
let c3 = leinwand(1024)
c3.interpolationQuality = .high
let breite = 800.0, hoehe = breite * Double(h) / Double(w)
c3.draw(zeichen, in: CGRect(x: (1024 - breite) / 2, y: (1024 - hoehe) / 2, width: breite, height: hoehe))
speichern(c3.makeImage()!, "zeichen.png")

// 3. Startbild unverändert als PNG
speichern(start, "start.png")
