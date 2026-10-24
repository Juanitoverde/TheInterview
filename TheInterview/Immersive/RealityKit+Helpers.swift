import RealityKit
import UIKit

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// Generated meshes, cached so repeated furniture and body parts share GPU resources.
@MainActor
enum Meshes {
    private static var cache: [String: MeshResource] = [:]

    private static func cached(_ key: String, _ make: () -> MeshResource) -> MeshResource {
        if let mesh = cache[key] { return mesh }
        let mesh = make()
        cache[key] = mesh
        return mesh
    }

    static func box(_ width: Float, _ height: Float, _ depth: Float, radius: Float = 0) -> MeshResource {
        let safeRadius = min(radius, min(width, min(height, depth)) * 0.49)
        return cached("box \(width) \(height) \(depth) \(safeRadius)") {
            .generateBox(width: width, height: height, depth: depth, cornerRadius: safeRadius)
        }
    }

    static func sphere(_ radius: Float) -> MeshResource {
        cached("sphere \(radius)") { .generateSphere(radius: radius) }
    }

    static func cylinder(height: Float, radius: Float) -> MeshResource {
        cached("cylinder \(height) \(radius)") { .generateCylinder(height: height, radius: radius) }
    }

    /// A horizontal plane facing up (+Y).
    static func floor(_ width: Float, _ depth: Float) -> MeshResource {
        cached("floor \(width) \(depth)") { .generatePlane(width: width, depth: depth) }
    }

    /// A vertical plane facing +Z.
    static func panel(_ width: Float, _ height: Float) -> MeshResource {
        cached("panel \(width) \(height)") { .generatePlane(width: width, height: height) }
    }
}

@MainActor
enum Materials {
    static func matte(_ hex: UInt32, roughness: Float = 0.85) -> SimpleMaterial {
        SimpleMaterial(color: UIColor(hex: hex), roughness: .float(roughness), isMetallic: false)
    }

    static func gloss(_ hex: UInt32, roughness: Float = 0.3) -> SimpleMaterial {
        SimpleMaterial(color: UIColor(hex: hex), roughness: .float(roughness), isMetallic: false)
    }

    static func metal(_ hex: UInt32, roughness: Float = 0.35) -> SimpleMaterial {
        SimpleMaterial(color: UIColor(hex: hex), roughness: .float(roughness), isMetallic: true)
    }

    /// Unaffected by lighting: screens, light panels, the view through windows.
    static func glow(_ hex: UInt32) -> UnlitMaterial {
        UnlitMaterial(color: UIColor(hex: hex))
    }

    /// A vertical sky gradient for the view out of the windows.
    static func sky() -> RealityKit.Material {
        let width = 4
        let height = 256
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(
                colorsSpace: colorSpace,
                colors: [UIColor(hex: 0x5B8FD1).cgColor, UIColor(hex: 0xA9CBEA).cgColor, UIColor(hex: 0xE8F1F8).cgColor] as CFArray,
                locations: [0, 0.6, 1])
        else { return glow(0xA9CBEA) }
        // Top of the image is deep blue, fading to a pale horizon.
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: CGPoint(x: 0, y: 0), options: [])
        guard let image = context.makeImage(),
              let texture = try? TextureResource.generate(from: image, options: .init(semantic: .color))
        else { return glow(0xA9CBEA) }
        var material = UnlitMaterial()
        material.color = .init(tint: .white, texture: .init(texture))
        return material
    }
}

@MainActor
func makeModel(_ mesh: MeshResource, _ material: RealityKit.Material, at position: SIMD3<Float> = .zero, shadow: Bool = false) -> ModelEntity {
    let entity = ModelEntity(mesh: mesh, materials: [material])
    entity.position = position
    if shadow {
        entity.components.set(GroundingShadowComponent(castsShadow: true))
    }
    return entity
}

@MainActor
extension Entity {
    /// Adds a child and returns it, for compact scene construction.
    @discardableResult
    func add<E: Entity>(_ child: E) -> E {
        addChild(child)
        return child
    }

    /// Yaw (rotation about Y) that turns a +Z-facing entity toward `direction`.
    static func yaw(toward direction: SIMD3<Float>) -> Float {
        atan2(direction.x, direction.z)
    }
}

/// Builds a flat 3D text label centred on its origin, facing +Z.
@MainActor
func makeTextLabel(_ string: String, size: CGFloat, weight: UIFont.Weight = .semibold, color: UInt32, depth: Float = 0.01) -> Entity {
    let mesh = MeshResource.generateText(
        string,
        extrusionDepth: depth,
        font: UIFont.systemFont(ofSize: size, weight: weight),
        containerFrame: .zero,
        alignment: .center,
        lineBreakMode: .byTruncatingTail
    )
    let text = ModelEntity(mesh: mesh, materials: [Materials.matte(color, roughness: 0.4)])
    text.position = -mesh.bounds.center
    let holder = Entity()
    holder.addChild(text)
    return holder
}
