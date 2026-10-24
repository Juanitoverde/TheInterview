import CoreGraphics
import Foundation
import RealityKit
import UIKit

/// Surface textures drawn in code: wood planks, tiles, carpet, wood grain and rugs.
///
/// Floor textures are drawn at the real-world size of the surface they cover (a plane's UVs span the
/// whole plane), so planks and tiles come out at believable sizes without relying on texture tiling.
@MainActor
enum ProceduralTextures {
    private static var cache: [String: TextureResource] = [:]

    /// Wooden floorboards, roughly 18 cm wide, running along the depth of the surface.
    static func woodPlanks(width: Float, depth: Float, base: UInt32, seed: UInt64 = 1) -> TextureResource? {
        render(key: "planks \(width) \(depth) \(base) \(seed)", width: width, depth: depth) { context, size, scale, random in
            fill(context, CGRect(origin: .zero, size: size), base, variation: 0)
            let plankWidth = 0.18 * scale
            var x: CGFloat = 0
            while x < size.width {
                var y = -random.next(in: 0...1.8) * scale
                while y < size.height {
                    let length = random.next(in: 1.2...2.4) * scale
                    let plank = CGRect(x: x, y: y, width: plankWidth, height: length)
                    fill(context, plank, base, variation: random.next(in: -0.09...0.09))
                    // Grain: a few long, slightly wavy darker lines.
                    context.setStrokeColor(UIColor(hex: base).withBrightness(0.82, alpha: 0.35).cgColor)
                    context.setLineWidth(max(1, scale * 0.004))
                    for _ in 0..<5 {
                        let gx = plank.minX + random.next(in: 0.1...0.9) * plankWidth
                        let wobble = random.next(in: 0.003...0.012) * scale
                        context.move(to: CGPoint(x: gx, y: plank.minY))
                        context.addCurve(
                            to: CGPoint(x: gx, y: plank.maxY),
                            control1: CGPoint(x: gx + wobble, y: plank.minY + length / 3),
                            control2: CGPoint(x: gx - wobble, y: plank.minY + 2 * length / 3)
                        )
                    }
                    context.strokePath()
                    // Joint at the end of the board.
                    fill(context, CGRect(x: x, y: plank.maxY - 1, width: plankWidth, height: max(1.5, scale * 0.003)), 0x3A2A1C, variation: 0, alpha: 0.6)
                    y += length
                }
                fill(context, CGRect(x: x + plankWidth - 1, y: 0, width: max(1.5, scale * 0.003), height: size.height), 0x3A2A1C, variation: 0, alpha: 0.55)
                x += plankWidth
            }
        }
    }

    /// Square tiles with grout lines and subtle stone speckle.
    static func tiles(width: Float, depth: Float, tileSize: CGFloat, base: UInt32, grout: UInt32, variation: CGFloat = 0.04, speckle: Bool = true) -> TextureResource? {
        render(key: "tiles \(width) \(depth) \(tileSize) \(base) \(grout)", width: width, depth: depth) { context, size, scale, random in
            fill(context, CGRect(origin: .zero, size: size), grout, variation: 0)
            let tile = tileSize * scale
            let gap = max(1.5, scale * 0.004)
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    fill(context, CGRect(x: x + gap / 2, y: y + gap / 2, width: tile - gap, height: tile - gap), base, variation: random.next(in: -variation...variation))
                    x += tile
                }
                y += tile
            }
            if speckle {
                speckles(context, size: size, count: Int(size.width * size.height / 60), base: base, random: &random, strength: 0.1)
            }
        }
    }

    /// Commercial carpet tiles: dense fleck noise, with alternate tiles turned for a faint checker.
    static func carpet(width: Float, depth: Float, base: UInt32) -> TextureResource? {
        render(key: "carpet \(width) \(depth) \(base)", width: width, depth: depth) { context, size, scale, random in
            let tile = 0.5 * scale
            var row = 0
            var y: CGFloat = 0
            while y < size.height {
                var column = 0
                var x: CGFloat = 0
                while x < size.width {
                    fill(context, CGRect(x: x, y: y, width: tile, height: tile), base, variation: (row + column).isMultiple(of: 2) ? 0.03 : -0.03)
                    x += tile
                    column += 1
                }
                y += tile
                row += 1
            }
            speckles(context, size: size, count: Int(size.width * size.height / 12), base: base, random: &random, strength: 0.18)
        }
    }

    /// Long wood grain for desks, counters and panelling.
    static func woodGrain(base: UInt32) -> TextureResource? {
        render(key: "grain \(base)", pixelWidth: 512, pixelHeight: 512) { context, size, _, random in
            fill(context, CGRect(origin: .zero, size: size), base, variation: 0)
            var x: CGFloat = 0
            while x < size.width {
                let band = random.next(in: 2...9)
                fill(context, CGRect(x: x, y: 0, width: band, height: size.height), base, variation: random.next(in: -0.08...0.06))
                x += band
            }
            context.setStrokeColor(UIColor(hex: base).withBrightness(0.75, alpha: 0.3).cgColor)
            context.setLineWidth(1)
            for _ in 0..<40 {
                let gx = random.next(in: 0...1) * size.width
                let wobble = random.next(in: 4...18)
                context.move(to: CGPoint(x: gx, y: 0))
                context.addCurve(to: CGPoint(x: gx, y: size.height),
                                 control1: CGPoint(x: gx + wobble, y: size.height / 3),
                                 control2: CGPoint(x: gx - wobble, y: 2 * size.height / 3))
            }
            context.strokePath()
        }
    }

    /// A rug with a border and a simple inner pattern.
    static func rug(width: Float, depth: Float, base: UInt32, border: UInt32, accent: UInt32) -> TextureResource? {
        render(key: "rug \(width) \(depth) \(base) \(border)", width: width, depth: depth) { context, size, scale, random in
            fill(context, CGRect(origin: .zero, size: size), border, variation: 0)
            let inset = 0.12 * scale
            let field = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
            fill(context, field, base, variation: 0)
            context.setStrokeColor(UIColor(hex: accent).cgColor)
            context.setLineWidth(max(2, scale * 0.02))
            context.stroke(field.insetBy(dx: inset * 0.6, dy: inset * 0.6))
            // Diamonds down the middle.
            let diamond = min(field.width, field.height) * 0.18
            var y = field.minY + diamond * 1.6
            while y < field.maxY - diamond {
                let centre = CGPoint(x: field.midX, y: y)
                context.move(to: CGPoint(x: centre.x, y: centre.y - diamond / 2))
                context.addLine(to: CGPoint(x: centre.x + diamond / 2, y: centre.y))
                context.addLine(to: CGPoint(x: centre.x, y: centre.y + diamond / 2))
                context.addLine(to: CGPoint(x: centre.x - diamond / 2, y: centre.y))
                context.closePath()
                y += diamond * 1.4
            }
            context.strokePath()
            speckles(context, size: size, count: Int(size.width * size.height / 20), base: base, random: &random, strength: 0.12)
        }
    }

    // MARK: Drawing helpers

    /// Seeded generator so textures look the same every launch.
    struct Random {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed &+ 0x9E37_79B9_7F4A_7C15
        }

        mutating func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53)
        }

        mutating func next(in range: ClosedRange<CGFloat>) -> CGFloat {
            range.lowerBound + CGFloat(next()) * (range.upperBound - range.lowerBound)
        }
    }

    private static func fill(_ context: CGContext, _ rect: CGRect, _ color: UInt32, variation: CGFloat, alpha: CGFloat = 1) {
        context.setFillColor(UIColor(hex: color).withBrightness(1 + variation, alpha: alpha).cgColor)
        context.fill(rect)
    }

    private static func speckles(_ context: CGContext, size: CGSize, count: Int, base: UInt32, random: inout Random, strength: CGFloat) {
        for _ in 0..<count {
            let lighter = random.next() > 0.5
            context.setFillColor(UIColor(hex: base).withBrightness(lighter ? 1 + strength : 1 - strength, alpha: 0.5).cgColor)
            let dot = random.next(in: 1...2)
            context.fill(CGRect(x: random.next(in: 0...1) * size.width, y: random.next(in: 0...1) * size.height, width: dot, height: dot))
        }
    }

    /// Draws a texture sized for a surface of `width` × `depth` metres (about 170 pixels per metre, capped at 2048).
    private static func render(key: String, width: Float, depth: Float, draw: (CGContext, CGSize, CGFloat, inout Random) -> Void) -> TextureResource? {
        let scale = min(170, 2048 / CGFloat(max(width, depth)))
        return render(key: key, pixelWidth: Int(CGFloat(width) * scale), pixelHeight: Int(CGFloat(depth) * scale), scale: scale, draw: draw)
    }

    private static func render(key: String, pixelWidth: Int, pixelHeight: Int, scale: CGFloat = 1, draw: (CGContext, CGSize, CGFloat, inout Random) -> Void) -> TextureResource? {
        if let cached = cache[key] { return cached }
        guard pixelWidth > 0, pixelHeight > 0,
              let context = CGContext(
                data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // FNV-1a of the key: a stable seed, so each surface looks the same every launch.
        var random = Random(seed: key.utf8.reduce(UInt64(0xCBF2_9CE4_8422_2325)) { ($0 ^ UInt64($1)) &* 0x0100_0000_01B3 })
        draw(context, CGSize(width: pixelWidth, height: pixelHeight), scale, &random)
        guard let image = context.makeImage(),
              let texture = try? TextureResource.generate(from: image, options: .init(semantic: .color))
        else { return nil }
        cache[key] = texture
        return texture
    }
}

extension UIColor {
    /// The same hue with its brightness scaled (1 = unchanged) and the given alpha.
    func withBrightness(_ factor: CGFloat, alpha: CGFloat) -> UIColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var originalAlpha: CGFloat = 0
        guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &originalAlpha) else { return withAlphaComponent(alpha) }
        return UIColor(hue: hue, saturation: saturation, brightness: min(max(brightness * factor, 0), 1), alpha: alpha)
    }
}

extension Materials {
    /// A material using a procedural texture, falling back to a flat colour if it couldn't be made.
    static func textured(_ texture: TextureResource?, fallback: UInt32, roughness: Float = 0.7) -> RealityKit.Material {
        guard let texture else { return matte(fallback, roughness: roughness) }
        var material = SimpleMaterial()
        material.color = .init(tint: .white, texture: .init(texture))
        material.roughness = .float(roughness)
        material.metallic = .float(0)
        return material
    }
}
