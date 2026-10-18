// App-Symbol und Startbild der HomeLab-Apps (HomeLabOffice, HomeLabMusic, HomeLabBooks), alle im gleichen Stil:
// Farbverlauf, Monogramm «HL» + Anfangsbuchstabe in weissen, runden Strichen (H und L teilen sich den hohen
// Mittelbalken) und oben rechts eine weisse Plakette mit ausgestanztem Symbol (Computer, Note, Buch).
// Die Symbole sind selbst gezeichnet (SF Symbols dürfen laut Lizenz nicht in App-Symbolen stehen).
// Dieselbe Datei liegt in allen drei Repos, nur `app` unten ist verschieden.
// Aufruf: xcrun swift icon_zeichnen.swift <ziel.png> [--zeichen | --rund | --start]
//   ohne Option: App-Symbol 1024 × 1024, deckend ohne Alphakanal (App Store verlangt das)
//   --zeichen: nur das weisse Zeichen mit Plakette auf transparent (Vorlage, z. B. Anmeldeseite)
//   --rund:    App-Symbol mit runden Ecken auf transparent (Logo der Anmeldeseite)
//   --start:   Startbild 2732 × 2732 mit Schriftzug; quadratisch, damit es am iPhone (Mittelstreifen),
//              iPad und Mac (Querformat) bildschirmfüllend und scharf ist
import AppKit
import CoreGraphics

enum App { case office, music, books }
let app = App.music

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }

struct Stil {
  let name: String
  let verlauf: [CGColor]                    // oben links -> unten rechts
  let lichter: [(CGFloat, CGFloat, CGFloat, CGColor)]   // Startbild: x, y (0…1, y nach oben), Radius, Farbe
  let mitteX: CGFloat                       // Mitte des Monogramms (ohne Plakette) im 1024er Raster
}
let stil: Stil = {
  switch app {
  case .office: return Stil(name: "HomeLabOffice",
    verlauf: [c(0.16, 0.45, 0.96), c(0.13, 0.58, 0.90), c(0.10, 0.74, 0.80)],
    lichter: [(0.30, 0.97, 0.44, c(0.55, 0.75, 1.0, 0.45)), (0.75, 0.62, 0.40, c(0.06, 0.20, 0.62, 0.45)),
              (0.35, 0.28, 0.40, c(0.20, 0.85, 0.85, 0.40)), (0.73, 0.05, 0.36, c(0.05, 0.35, 0.55, 0.45))],
    mitteX: 487)
  case .music: return Stil(name: "HomeLabMusic",
    verlauf: [c(0.98, 0.36, 0.34), c(0.86, 0.02, 0.21), c(0.70, 0.01, 0.33)],
    lichter: [(0.30, 0.97, 0.44, c(1.00, 0.55, 0.50, 0.40)), (0.75, 0.64, 0.40, c(0.45, 0.01, 0.14, 0.45)),
              (0.35, 0.28, 0.40, c(1.00, 0.12, 0.32, 0.40)), (0.73, 0.05, 0.36, c(0.42, 0.02, 0.36, 0.50))],
    mitteX: 501)
  case .books: return Stil(name: "HomeLabBooks",
    verlauf: [c(0.16, 0.78, 0.70), c(0.04, 0.58, 0.52), c(0.02, 0.40, 0.48)],
    lichter: [(0.30, 0.97, 0.44, c(0.55, 0.95, 0.85, 0.40)), (0.75, 0.62, 0.40, c(0.01, 0.28, 0.35, 0.45)),
              (0.35, 0.28, 0.40, c(0.20, 0.85, 0.75, 0.40)), (0.73, 0.05, 0.36, c(0.02, 0.22, 0.38, 0.50))],
    mitteX: 482)
  }
}()

// Monogramm mit Plakette im 1024er Raster, y nach unten. Zeichnet in eine eigene Ebene, damit das Symbol
// aus der Plakette ausgestanzt werden kann und sich halbtransparente Striche nicht überlagern.
func zeichen(_ ctx: CGContext) {
  ctx.beginTransparencyLayer(auxiliaryInfo: nil)
  ctx.setStrokeColor(c(1, 1, 1)); ctx.setFillColor(c(1, 1, 1))
  ctx.setLineWidth(80); ctx.setLineCap(.round); ctx.setLineJoin(.round)
  func linie(_ pts: [(CGFloat, CGFloat)]) {
    ctx.move(to: CGPoint(x: pts[0].0, y: pts[0].1))
    for p in pts.dropFirst() { ctx.addLine(to: CGPoint(x: p.0, y: p.1)) }
    ctx.strokePath()
  }
  linie([(152, 352), (152, 650)])                  // H links
  linie([(152, 490), (410, 490)])                  // H Querbalken
  linie([(410, 255), (410, 760), (650, 760)])      // gemeinsamer Balken H/L und L-Fuss
  switch app {
  case .office:                                    // O als Ring, so hoch wie die Mittellänge
    ctx.strokeEllipse(in: CGRect(x: 561, y: 380, width: 260, height: 260))
  case .music:                                     // M: Diagonale links gerade abgeschnitten
    ctx.saveGState()
    ctx.clip(to: CGRect(x: 493, y: 0, width: 531, height: 1024))
    linie([(400, 328), (668, 542), (850, 378), (850, 724)])
    ctx.restoreGState()
  case .books:                                     // B: Stamm, oberer und unterer Bogen (unten breiter)
    let x0: CGFloat = 535, oben: CGFloat = 290, mitte: CGFloat = 465, unten: CGFloat = 640, r = (mitte - oben) / 2
    ctx.move(to: CGPoint(x: x0, y: oben)); ctx.addLine(to: CGPoint(x: 680, y: oben))
    ctx.addArc(center: CGPoint(x: 680, y: oben + r), radius: r, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
    ctx.addLine(to: CGPoint(x: x0, y: mitte))
    ctx.move(to: CGPoint(x: x0, y: mitte)); ctx.addLine(to: CGPoint(x: 725, y: mitte))
    ctx.addArc(center: CGPoint(x: 725, y: mitte + r), radius: r, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
    ctx.addLine(to: CGPoint(x: x0, y: unten)); ctx.addLine(to: CGPoint(x: x0, y: oben))
    ctx.strokePath()
  }

  // Plakette oben rechts, Symbol ausgestanzt (Mitte 868/165, Radius 105)
  ctx.fillEllipse(in: CGRect(x: 763, y: 60, width: 210, height: 210))
  ctx.setBlendMode(.destinationOut)
  switch app {
  case .office:                                    // Computer: Bildschirm mit Fuss
    ctx.addPath(CGPath(roundedRect: CGRect(x: 806, y: 112, width: 124, height: 84), cornerWidth: 12, cornerHeight: 12, transform: nil))
    ctx.fillPath()
    ctx.fill(CGRect(x: 856, y: 194, width: 24, height: 18))
    ctx.addPath(CGPath(roundedRect: CGRect(x: 834, y: 208, width: 68, height: 14), cornerWidth: 7, cornerHeight: 7, transform: nil))
    ctx.fillPath()
  case .music:                                     // Achtelnote: schräger Kopf, Hals, Fähnchen
    ctx.saveGState(); ctx.translateBy(x: 846, y: 202); ctx.rotate(by: -0.4)
    ctx.fillEllipse(in: CGRect(x: -34, y: -24, width: 68, height: 48)); ctx.restoreGState()
    ctx.setLineWidth(15); ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: 872, y: 196)); ctx.addLine(to: CGPoint(x: 872, y: 106)); ctx.strokePath()
    ctx.move(to: CGPoint(x: 872, y: 108))
    ctx.addCurve(to: CGPoint(x: 902, y: 176), control1: CGPoint(x: 880, y: 136), control2: CGPoint(x: 922, y: 140))
    ctx.strokePath()
  case .books:                                     // Buch: Deckel mit Rücken, darunter abgesetzt der Seitenblock
    ctx.addPath(CGPath(roundedRect: CGRect(x: 820, y: 104, width: 96, height: 98), cornerWidth: 12, cornerHeight: 12, transform: nil))
    ctx.fillPath()
    ctx.addPath(CGPath(roundedRect: CGRect(x: 820, y: 210, width: 96, height: 18), cornerWidth: 9, cornerHeight: 9, transform: nil))
    ctx.fillPath()
    ctx.setBlendMode(.normal)
    ctx.fill(CGRect(x: 840, y: 100, width: 8, height: 106))           // Rücken
  }
  ctx.setBlendMode(.normal)
  ctx.endTransparencyLayer()
}

func verlauf(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
  ctx.drawLinearGradient(CGGradient(colorsSpace: cs, colors: stil.verlauf as CFArray, locations: [0, 0.5, 1])!,
                         start: CGPoint(x: 0, y: h), end: CGPoint(x: w, y: 0), options: [])
}
func speichern(_ ctx: CGContext) {
  try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
  print("geschrieben:", CommandLine.arguments[1])
}

let args = CommandLine.arguments
if args.contains("--start") {
  let n = 2732, N = CGFloat(n)
  let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
  verlauf(ctx, N, N)
  for (x, y, r, col) in stil.lichter {             // weiche Lichter und Schatten für Tiefe
    let g = CGGradient(colorsSpace: cs, colors: [col, col.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
    let p = CGPoint(x: x * N, y: y * N)
    ctx.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: r * N, options: [])
  }
  // Grössen bezogen auf den Streifen, den ein iPhone im Hochformat zeigt (Höhe × 1179/2556)
  let streifen = N * 1179 / 2556, f = streifen / 1179
  let scale: CGFloat = 0.42 * streifen / 1024
  let ox = N / 2 - stil.mitteX * scale, oy = N * 0.40 - 508 * scale
  ctx.saveGState()
  ctx.translateBy(x: 0, y: N); ctx.scaleBy(x: 1, y: -1)
  ctx.setAlpha(0.97)
  ctx.translateBy(x: ox, y: oy); ctx.scaleBy(x: scale, y: scale)
  zeichen(ctx)
  ctx.restoreGState()
  NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
  let text = NSAttributedString(string: stil.name, attributes: [
    .font: NSFont.systemFont(ofSize: 90 * f, weight: .light), .foregroundColor: NSColor(white: 1, alpha: 0.95), .kern: 4 * f])
  let size = text.size()
  text.draw(at: NSPoint(x: (N - size.width) / 2, y: N - (oy + 1024 * 0.80 * scale) - size.height - 120 * f))
  speichern(ctx)
} else {
  let n = 1024, N = CGFloat(n)
  let transparent = args.contains("--zeichen") || args.contains("--rund")
  let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                      bitmapInfo: (transparent ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast).rawValue)!
  if args.contains("--rund") {
    ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: N, height: N), cornerWidth: 225, cornerHeight: 225, transform: nil))
    ctx.clip()
  }
  if !args.contains("--zeichen") { verlauf(ctx, N, N) }
  ctx.translateBy(x: 0, y: N); ctx.scaleBy(x: 1, y: -1)
  zeichen(ctx)
  speichern(ctx)
}
