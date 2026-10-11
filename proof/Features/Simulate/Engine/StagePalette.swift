import Foundation
import RealityKit
import simd
#if canImport(UIKit)
import UIKit
#endif

/// A colour in sRGB, kept as plain floats so the whole palette is `Sendable`
/// and can be compared in tests without touching UIKit.
public struct StageColor: Sendable, Equatable {
    public var red: Float
    public var green: Float
    public var blue: Float
    public var alpha: Float

    public init(red: Float, green: Float, blue: Float, alpha: Float = 1) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
        self.alpha = min(max(alpha, 0), 1)
    }

    /// `StageColor(hex: 0x8A6A4E)`.
    public init(hex: UInt32, alpha: Float = 1) {
        self.init(
            red: Float((hex >> 16) & 0xFF) / 255.0,
            green: Float((hex >> 8) & 0xFF) / 255.0,
            blue: Float(hex & 0xFF) / 255.0,
            alpha: alpha
        )
    }

    /// Linear blend towards `other`. Used to tint an object by its risk band
    /// without losing the material's own identity.
    public func blended(with other: StageColor, amount: Float) -> StageColor {
        let t = min(max(amount, 0), 1)
        return StageColor(
            red: red + (other.red - red) * t,
            green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t,
            alpha: alpha + (other.alpha - alpha) * t
        )
    }

    #if canImport(UIKit)
    public var uiColor: UIColor {
        UIColor(
            red: CGFloat(red), green: CGFloat(green),
            blue: CGFloat(blue), alpha: CGFloat(alpha))
    }
    #endif
}

// MARK: - Material families

/// The handful of surface finishes the stage needs. Every `ObjectType` maps to
/// one of these; nothing in the scene is an untinted grey primitive.
public enum StageMaterialFamily: String, Sendable, CaseIterable {
    case wood
    case metal
    case plastic
    case ceramic
    case upholstery
    case glass
    case fabric
    case stone

    /// SPEC §2.7.12: the warm per-archetype base colours for the 3D stage.
    public var baseColor: StageColor {
        switch self {
        case .wood: return StageColor(hex: 0x8A6A4E)
        case .metal: return StageColor(hex: 0xB9B2B4)
        case .plastic: return StageColor(hex: 0x6E6A72)
        case .ceramic: return StageColor(hex: 0xD9D5E0)
        case .upholstery: return StageColor(hex: 0x5C5460)
        case .glass: return StageColor(hex: 0xA9C4D2, alpha: 0.55)
        case .fabric: return StageColor(hex: 0x7A6E72)
        case .stone: return StageColor(hex: 0x9A9299)
        }
    }

    public var roughness: Float {
        switch self {
        case .wood: return 0.68
        case .metal: return 0.38
        case .plastic: return 0.60
        case .ceramic: return 0.42
        case .upholstery: return 0.90
        case .glass: return 0.10
        case .fabric: return 0.95
        case .stone: return 0.55
        }
    }

    public var metallic: Float { self == .metal ? 0.85 : 0.0 }

    public var isTransparent: Bool { self == .glass }
}

public extension ObjectType {
    /// The finish this archetype reads as on the stage.
    var stageMaterialFamily: StageMaterialFamily {
        switch self {
        case .bookshelfTall, .bookshelfShort, .wardrobe, .dresser, .nightstand,
             .highboy, .chinaCabinet, .trunk, .desk, .diningTable, .coffeeTable,
             .kitchenCabinetUpper, .diningChair, .pianoUpright, .books,
             .framedPicture, .stairs, .fireplace:
            return .wood
        case .filingCabinet, .refrigerator, .dishwasher, .rangeElectric,
             .rangeGas, .oven, .microwave, .washingMachine, .clothesDryer,
             .waterHeater, .waterHeaterGas, .sink, .floorLamp:
            return .metal
        case .storageBin, .officeChair, .speaker, .plantPotSmall, .tableLamp,
             .computerMonitor:
            return .plastic
        case .toilet, .bathtub, .vaseCeramic, .plantPotLarge:
            return .ceramic
        case .sofa, .armchair, .bed, .crib:
            return .upholstery
        case .mirrorWall, .mirrorLeaning, .vaseGlass, .aquarium:
            return .glass
        case .television, .televisionWallMounted:
            return .plastic
        case .unknown:
            return .plastic
        }
    }
}

// MARK: - Palette

/// The full set of colours the stage draws with.
public struct StagePalette: Sendable, Equatable {
    public var background: StageColor
    public var floor: StageColor
    public var wall: StageColor
    public var wallTrim: StageColor
    public var window: StageColor
    public var door: StageColor
    public var grid: StageColor
    public var selection: StageColor

    /// Risk-band tints, from SPEC §2.2.4's on-ink variants — the ones designed
    /// to read on the dark stage rather than on white.
    public var riskLow: StageColor
    public var riskModerate: StageColor
    public var riskHigh: StageColor
    public var riskSevere: StageColor

    /// How far an object is dragged towards its band colour, 0…1.
    public var riskTintAmount: Float

    public func colour(for band: RiskBand) -> StageColor {
        switch band {
        case .low: return riskLow
        case .moderate: return riskModerate
        case .high: return riskHigh
        case .severe: return riskSevere
        }
    }

    /// SPEC §2.7.12. The stage is always ink; it ignores light/dark mode.
    /// The default stage look.
    ///
    /// Everything is lifted a step out of the ink: at the original values the
    /// floor sat 6 % above the background and the walls 11 %, which on a phone
    /// in daylight collapsed into one dark field with furniture floating in it.
    /// The room has to read as an enclosure before any of the simulation means
    /// anything, so the surfaces now separate clearly from the backdrop and
    /// from each other while staying in the aubergine family.
    public static let stage = StagePalette(
        background: StageColor(hex: 0x241035),
        floor: StageColor(hex: 0x4A3A5E),
        wall: StageColor(hex: 0x63527A),
        wallTrim: StageColor(hex: 0x7C6A94),
        window: StageColor(hex: 0xB8DCE8, alpha: 0.45),
        door: StageColor(hex: 0x8A76A2),
        grid: StageColor(hex: 0x8877A0),
        selection: StageColor(hex: 0xAA8FFF),
        riskLow: StageColor(hex: 0x5ECA8F),
        riskModerate: StageColor(hex: 0xFFC249),
        riskHigh: StageColor(hex: 0xFFA489),
        riskSevere: StageColor(hex: 0xFF999A),
        riskTintAmount: 0.55
    )

    /// A light, warm, matte alternative for print-style stills and thumbnails.
    public static let architectural = StagePalette(
        background: StageColor(hex: 0xF1F0EC),
        floor: StageColor(hex: 0xE8E2D9),
        wall: StageColor(hex: 0xF4EFE7),
        wallTrim: StageColor(hex: 0xDED6C9),
        window: StageColor(hex: 0xBFD9E4, alpha: 0.40),
        door: StageColor(hex: 0xCDBFAD),
        grid: StageColor(hex: 0xD6CEC1),
        selection: StageColor(hex: 0x6542BE),
        riskLow: StageColor(hex: 0x197849),
        riskModerate: StageColor(hex: 0x8A5A00),
        riskHigh: StageColor(hex: 0xC13800),
        riskSevere: StageColor(hex: 0xC81534),
        riskTintAmount: 0.45
    )
}

// MARK: - Materials

@MainActor
public enum StageMaterials {

    /// A matte physically-based material. Everything on the stage is PBR — the
    /// scene has to read as an architectural model, not as debug primitives.
    public static func matte(
        _ colour: StageColor, roughness: Float = 0.7, metallic: Float = 0
    ) -> RealityKit.Material {
        #if canImport(UIKit)
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: colour.uiColor)
        material.roughness = .init(floatLiteral: min(max(roughness, 0), 1))
        material.metallic = .init(floatLiteral: min(max(metallic, 0), 1))
        material.specular = .init(floatLiteral: 0.35)
        if colour.alpha < 0.999 {
            material.blending = .transparent(opacity: .init(floatLiteral: colour.alpha))
        }
        return material
        #else
        return SimpleMaterial(color: .gray, roughness: 0.7, isMetallic: false)
        #endif
    }

    /// The finish for one object, tinted by its risk band when an assessment is
    /// available.
    public static func object(
        type: ObjectType, band: RiskBand?, palette: StagePalette
    ) -> RealityKit.Material {
        let family = type.stageMaterialFamily
        var colour = family.baseColor
        if let band, palette.riskTintAmount > 0 {
            let tint = palette.colour(for: band)
            colour = colour.blended(with: tint, amount: palette.riskTintAmount)
            // Keep the object's own transparency; only the hue is borrowed.
            colour.alpha = family.baseColor.alpha
        }
        return matte(colour, roughness: family.roughness, metallic: family.metallic)
    }
}
