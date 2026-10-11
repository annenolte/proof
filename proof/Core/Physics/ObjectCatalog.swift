import Foundation

/// How an object is held in place.
public enum Mounting: String, Codable, CaseIterable, Sendable {
    /// Standing free on the floor or a shelf. The default, and the dangerous one.
    case freestanding
    /// Hung on a wall — a picture, mirror, or wall-mounted TV. Fails by its
    /// fixing pulling out, not by tipping.
    case wallMounted
    /// Leaning against a wall — a full-length mirror, a headboard, a canvas.
    /// Not a block and not anchored; it fails when its base slides out.
    case leaning
    /// Built in, bolted, strapped or screwed down. Effectively cannot move.
    case anchored
    /// Suspended from the ceiling — a pendant light, a hanging plant.
    case suspended

    public var displayName: String {
        switch self {
        case .freestanding: return "Free-standing"
        case .wallMounted: return "Wall-mounted"
        case .leaning: return "Leaning on a wall"
        case .anchored: return "Anchored"
        case .suspended: return "Hanging"
        }
    }
}

/// The kind of secondary harm an object can do beyond being heavy.
public enum SecondaryHazard: String, Codable, CaseIterable, Sendable {
    case none
    /// Live mains electrical — lamps, heaters, appliances.
    case electrical
    /// Holds water that will flood — aquarium, water heater.
    case water
    /// Gas-fired or gas-connected. Historically the largest post-earthquake
    /// loss driver: over half of residential fires after Northridge 1994 began
    /// at a water heater whose gas connector ruptured.
    case gas
    /// Fuel, solvents, or chemicals.
    case chemical

    /// Consequence factor f₇ in the risk rubric.
    public var severity: Double {
        switch self {
        case .none: return 0.0
        case .electrical: return 0.7
        case .water: return 0.6
        case .chemical: return 0.9
        case .gas: return 1.0
        }
    }
}

/// How much brittle material the object presents, which drives laceration risk.
public enum BreakageClass: String, Codable, CaseIterable, Sendable {
    case none
    /// A picture frame's glass, a small pane.
    case smallGlass
    /// A glass cabinet door, a modest mirror: 0.1–0.5 m².
    case mediumGlass
    /// A large unlaminated mirror, an aquarium wall, a display cabinet front.
    case largeGlass
    /// Ceramic or porcelain — breaks into sharp pieces but not sheets.
    case ceramic

    /// Consequence factor f₅ in the risk rubric.
    public var severity: Double {
        switch self {
        case .none: return 0.0
        case .smallGlass: return 0.15
        case .ceramic: return 0.4
        case .mediumGlass: return 0.7
        case .largeGlass: return 1.0
        }
    }
}

/// A specific kind of household object, with the physical priors needed to turn
/// a RoomPlan bounding box into a rigid block the solver can integrate.
///
/// RoomPlan itself only reports 16 coarse categories (and calls both a bookcase
/// and a dresser "storage"), so this richer taxonomy is what the vision and
/// language models refine *into*. Every value below is sourced from the compiled
/// table in `docs/research/science-seismic.md` §6, which draws on manufacturer
/// specification sheets (IKEA, Samsung, LG, Whirlpool, Herman Miller), ASHRAE
/// equipment weights, and FEMA E-74 Chapter 6.
public enum ObjectType: String, Codable, CaseIterable, Sendable, Identifiable {
    // Storage and case goods
    case bookshelfTall
    case bookshelfShort
    case wardrobe
    case dresser
    case nightstand
    case highboy
    case chinaCabinet
    case filingCabinet
    case kitchenCabinetUpper
    case trunk
    case storageBin

    // Tables and seating
    case desk
    case diningTable
    case coffeeTable
    case diningChair
    case officeChair
    case sofa
    case armchair
    case bed
    case crib

    // Displays and electronics
    case television
    case televisionWallMounted
    case computerMonitor
    case speaker

    // Appliances
    case refrigerator
    case dishwasher
    case rangeElectric
    case rangeGas
    case oven
    case microwave
    case washingMachine
    case clothesDryer
    case waterHeater
    case waterHeaterGas

    // Fixtures the scanner reports but that cannot move
    case sink
    case toilet
    case bathtub
    case fireplace
    case stairs

    // Decor and small objects
    case floorLamp
    case tableLamp
    case mirrorWall
    case mirrorLeaning
    case framedPicture
    case vaseCeramic
    case vaseGlass
    case plantPotLarge
    case plantPotSmall
    case books
    case aquarium
    case pianoUpright

    /// Anything the pipeline could not resolve. Uses conservative mid-range
    /// priors so an unknown object is neither dismissed nor over-flagged.
    case unknown

    public var id: String { rawValue }

    // MARK: - Presentation

    public var displayName: String {
        switch self {
        case .bookshelfTall: return "Tall bookshelf"
        case .bookshelfShort: return "Low bookshelf"
        case .wardrobe: return "Wardrobe"
        case .dresser: return "Dresser"
        case .nightstand: return "Nightstand"
        case .highboy: return "Tall chest of drawers"
        case .chinaCabinet: return "China cabinet"
        case .filingCabinet: return "Filing cabinet"
        case .kitchenCabinetUpper: return "Upper kitchen cabinet"
        case .trunk: return "Trunk"
        case .storageBin: return "Storage bin"
        case .desk: return "Desk"
        case .diningTable: return "Dining table"
        case .coffeeTable: return "Coffee table"
        case .diningChair: return "Chair"
        case .officeChair: return "Office chair"
        case .sofa: return "Sofa"
        case .armchair: return "Armchair"
        case .bed: return "Bed"
        case .crib: return "Crib"
        case .television: return "Television"
        case .televisionWallMounted: return "Wall-mounted TV"
        case .computerMonitor: return "Monitor"
        case .speaker: return "Speaker"
        case .refrigerator: return "Refrigerator"
        case .dishwasher: return "Dishwasher"
        case .rangeElectric: return "Electric range"
        case .rangeGas: return "Gas range"
        case .oven: return "Oven"
        case .microwave: return "Microwave"
        case .washingMachine: return "Washing machine"
        case .clothesDryer: return "Dryer"
        case .waterHeater: return "Water heater"
        case .waterHeaterGas: return "Gas water heater"
        case .sink: return "Sink"
        case .toilet: return "Toilet"
        case .bathtub: return "Bathtub"
        case .fireplace: return "Fireplace"
        case .stairs: return "Stairs"
        case .floorLamp: return "Floor lamp"
        case .tableLamp: return "Table lamp"
        case .mirrorWall: return "Wall mirror"
        case .mirrorLeaning: return "Leaning mirror"
        case .framedPicture: return "Framed picture"
        case .vaseCeramic: return "Ceramic vase"
        case .vaseGlass: return "Glass vase"
        case .plantPotLarge: return "Large plant"
        case .plantPotSmall: return "Small plant"
        case .books: return "Books"
        case .aquarium: return "Aquarium"
        case .pianoUpright: return "Upright piano"
        case .unknown: return "Object"
        }
    }

    /// SF Symbol used throughout the UI for this object.
    public var symbolName: String {
        switch self {
        case .bookshelfTall, .bookshelfShort, .books: return "books.vertical.fill"
        case .wardrobe, .dresser, .highboy, .nightstand, .chinaCabinet,
             .filingCabinet, .kitchenCabinetUpper, .trunk, .storageBin:
            return "cabinet.fill"
        case .desk, .diningTable, .coffeeTable: return "table.furniture.fill"
        case .diningChair, .officeChair, .armchair: return "chair.fill"
        case .sofa: return "sofa.fill"
        case .bed, .crib: return "bed.double.fill"
        case .television, .televisionWallMounted: return "tv.fill"
        case .computerMonitor: return "display"
        case .speaker: return "hifispeaker.fill"
        case .refrigerator: return "refrigerator.fill"
        case .dishwasher, .washingMachine, .clothesDryer: return "washer.fill"
        case .rangeElectric, .rangeGas, .oven: return "oven.fill"
        case .microwave: return "microwave.fill"
        case .waterHeater, .waterHeaterGas: return "water.waves"
        case .sink: return "sink.fill"
        case .toilet: return "toilet.fill"
        case .bathtub: return "bathtub.fill"
        case .fireplace: return "fireplace.fill"
        case .stairs: return "stairs"
        case .floorLamp, .tableLamp: return "lamp.floor.fill"
        case .mirrorWall, .mirrorLeaning, .framedPicture: return "photo.fill"
        case .vaseCeramic, .vaseGlass: return "vase.fill"
        case .plantPotLarge, .plantPotSmall: return "leaf.fill"
        case .aquarium: return "fish.fill"
        case .pianoUpright: return "pianokeys"
        case .unknown: return "cube.fill"
        }
    }

    // MARK: - Physical priors

    /// Effective density in kg per m³ of *bounding box* volume — not of the
    /// material. A wardrobe is mostly air, so its effective density is a tenth
    /// of the particleboard it is made from.
    public var densityPrior: Double {
        switch self {
        case .bookshelfTall: return 307      // loaded; empty is ~70
        case .bookshelfShort: return 278
        case .wardrobe: return 103
        case .dresser: return 160
        case .nightstand: return 167
        case .highboy: return 132
        case .chinaCabinet: return 131
        case .filingCabinet: return 263
        case .kitchenCabinetUpper: return 191
        case .trunk: return 197
        case .storageBin: return 214
        case .desk: return 52
        case .diningTable: return 37
        case .coffeeTable: return 74
        case .diningChair: return 35
        case .officeChair: return 33
        case .sofa: return 47
        case .armchair: return 43
        case .bed: return 45
        case .crib: return 40
        case .television: return 62
        case .televisionWallMounted: return 62
        case .computerMonitor: return 97
        case .speaker: return 180
        case .refrigerator: return 115
        case .dishwasher: return 147
        case .rangeElectric: return 152
        case .rangeGas: return 195
        case .oven: return 160
        case .microwave: return 250
        case .washingMachine: return 223
        case .clothesDryer: return 91
        case .waterHeater: return 873       // full — the only state worth modelling
        case .waterHeaterGas: return 873
        case .sink: return 200
        case .toilet: return 350
        case .bathtub: return 180
        case .fireplace: return 1800
        case .stairs: return 500
        case .floorLamp: return 35
        case .tableLamp: return 50
        case .mirrorWall: return 571
        case .mirrorLeaning: return 294
        case .framedPicture: return 208
        case .vaseCeramic: return 317
        case .vaseGlass: return 278
        case .plantPotLarge: return 619
        case .plantPotSmall: return 579
        case .books: return 510
        case .aquarium: return 356
        case .pianoUpright: return 215
        case .unknown: return 150
        }
    }

    /// The plausible mass envelope in kg. The density estimate is clamped into
    /// this range, which is what makes an absurd estimate — from a bad bounding
    /// box or a hallucinated model answer — impossible to act on.
    public var massRange: ClosedRange<Double> {
        switch self {
        case .bookshelfTall: return 20...220
        case .bookshelfShort: return 12...110
        case .wardrobe: return 40...260
        case .dresser: return 25...180
        case .nightstand: return 5...45
        case .highboy: return 25...150
        case .chinaCabinet: return 45...260
        case .filingCabinet: return 20...200
        case .kitchenCabinetUpper: return 10...90
        case .trunk: return 8...100
        case .storageBin: return 1...45
        case .desk: return 12...110
        case .diningTable: return 12...140
        case .coffeeTable: return 6...70
        case .diningChair: return 2.5...18
        case .officeChair: return 7...30
        case .sofa: return 25...180
        case .armchair: return 12...80
        case .bed: return 30...220
        case .crib: return 12...60
        case .television: return 2...70
        case .televisionWallMounted: return 2...70
        case .computerMonitor: return 1.5...20
        case .speaker: return 1...60
        case .refrigerator: return 45...320
        case .dishwasher: return 25...80
        case .rangeElectric: return 35...130
        case .rangeGas: return 45...160
        case .oven: return 25...110
        case .microwave: return 8...30
        case .washingMachine: return 45...140
        case .clothesDryer: return 25...90
        case .waterHeater: return 40...400
        case .waterHeaterGas: return 40...400
        case .sink: return 5...60
        case .toilet: return 20...70
        case .bathtub: return 25...300
        case .fireplace: return 100...3000
        case .stairs: return 100...3000
        case .floorLamp: return 2...20
        case .tableLamp: return 0.5...9
        case .mirrorWall: return 2...45
        case .mirrorLeaning: return 4...45
        case .framedPicture: return 0.3...20
        case .vaseCeramic: return 0.2...15
        case .vaseGlass: return 0.2...12
        case .plantPotLarge: return 5...120
        case .plantPotSmall: return 0.5...15
        case .books: return 0.3...60
        case .aquarium: return 10...600
        case .pianoUpright: return 130...450
        case .unknown: return 0.5...200
        }
    }

    /// Height of the centre of mass as a fraction of total height. This matters
    /// more than mass: it sets the slenderness α, and therefore the whole
    /// rocking response. Weighted-base items sit low; loaded cabinets sit high.
    public var centreOfMassFraction: Double {
        switch self {
        case .bookshelfTall: return 0.52     // loaded shelves are top-heavy
        case .bookshelfShort: return 0.50
        case .wardrobe: return 0.50
        case .dresser: return 0.48
        case .nightstand: return 0.48
        case .highboy: return 0.48
        case .chinaCabinet: return 0.55      // glass and china up top
        case .filingCabinet: return 0.48
        case .kitchenCabinetUpper: return 0.50
        case .trunk: return 0.48
        case .storageBin: return 0.45
        case .desk: return 0.62              // the mass is the worktop
        case .diningTable: return 0.62
        case .coffeeTable: return 0.55
        case .diningChair: return 0.45
        case .officeChair: return 0.35       // heavy five-star base
        case .sofa: return 0.42
        case .armchair: return 0.42
        case .bed: return 0.50
        case .crib: return 0.45
        case .television: return 0.55
        case .televisionWallMounted: return 0.50
        case .computerMonitor: return 0.50
        case .speaker: return 0.45
        case .refrigerator: return 0.45
        case .dishwasher: return 0.45
        case .rangeElectric, .rangeGas, .oven: return 0.45
        case .microwave: return 0.45
        case .washingMachine: return 0.45
        case .clothesDryer: return 0.45
        case .waterHeater, .waterHeaterGas: return 0.50
        case .sink: return 0.50
        case .toilet: return 0.40
        case .bathtub: return 0.45
        case .fireplace: return 0.45
        case .stairs: return 0.50
        case .floorLamp: return 0.28         // deliberately weighted base
        case .tableLamp: return 0.35
        case .mirrorWall: return 0.50
        case .mirrorLeaning: return 0.50
        case .framedPicture: return 0.50
        case .vaseCeramic: return 0.42
        case .vaseGlass: return 0.40
        case .plantPotLarge: return 0.42
        case .plantPotSmall: return 0.42
        case .books: return 0.50
        case .aquarium: return 0.55          // the water sits high on the stand
        case .pianoUpright: return 0.45
        case .unknown: return 0.50
        }
    }

    /// What the object stands on.
    public var footing: Footing {
        switch self {
        case .bookshelfTall, .bookshelfShort, .storageBin, .television,
             .computerMonitor, .speaker, .microwave:
            return .plasticGlide
        case .wardrobe, .dresser, .nightstand, .highboy, .chinaCabinet,
             .trunk, .desk, .diningTable, .coffeeTable, .diningChair,
             .sofa, .armchair, .bed, .crib, .books:
            return .wood
        case .officeChair, .pianoUpright:
            return .castor
        case .filingCabinet, .rangeElectric, .rangeGas, .oven, .clothesDryer,
             .waterHeater, .waterHeaterGas, .dishwasher, .refrigerator:
            return .metal
        case .washingMachine:
            return .rubber
        case .vaseCeramic, .plantPotLarge, .plantPotSmall, .toilet, .sink:
            return .ceramic
        case .vaseGlass, .aquarium:
            return .glass
        case .floorLamp:
            return .felt
        case .tableLamp:
            return .felt
        case .mirrorWall, .framedPicture, .televisionWallMounted,
             .kitchenCabinetUpper, .bathtub, .fireplace, .stairs:
            return .wood            // irrelevant: these are not free-standing
        case .mirrorLeaning:
            return .wood
        case .unknown:
            return .wood
        }
    }

    /// How this kind of object is normally held in place.
    public var defaultMounting: Mounting {
        switch self {
        case .televisionWallMounted, .mirrorWall, .framedPicture, .kitchenCabinetUpper:
            return .wallMounted
        case .mirrorLeaning:
            return .leaning
        case .sink, .toilet, .bathtub, .fireplace, .stairs, .dishwasher:
            return .anchored
        default:
            return .freestanding
        }
    }

    public var secondaryHazard: SecondaryHazard {
        switch self {
        case .rangeGas, .waterHeaterGas, .fireplace: return .gas
        case .waterHeater, .aquarium: return .water
        case .television, .televisionWallMounted, .computerMonitor, .floorLamp,
             .tableLamp, .microwave, .rangeElectric, .oven, .washingMachine,
             .clothesDryer, .dishwasher, .refrigerator, .speaker:
            return .electrical
        default: return .none
        }
    }

    public var breakage: BreakageClass {
        switch self {
        case .mirrorWall, .mirrorLeaning, .aquarium, .chinaCabinet: return .largeGlass
        case .television, .televisionWallMounted, .computerMonitor: return .mediumGlass
        case .framedPicture: return .smallGlass
        case .vaseCeramic, .vaseGlass, .plantPotLarge, .plantPotSmall,
             .sink, .toilet: return .ceramic
        default: return .none
        }
    }

    /// True when the object has shelves or drawers whose contents become
    /// separate projectiles. The app calls these out because latching a cabinet
    /// is cheap and stops most of the mess.
    public var hasSpillableContents: Bool {
        switch self {
        case .bookshelfTall, .bookshelfShort, .wardrobe, .dresser, .highboy,
             .chinaCabinet, .filingCabinet, .kitchenCabinetUpper, .nightstand,
             .trunk, .storageBin, .desk:
            return true
        default: return false
        }
    }

    /// A place where a person is lying or sitting, and so cannot react. Used to
    /// find what is inside an object's strike zone.
    public var isOccupantZone: Bool {
        switch self {
        case .bed, .crib, .sofa, .armchair, .officeChair, .diningChair: return true
        default: return false
        }
    }

    /// True for a bed or crib specifically: an occupant here is asleep, prone,
    /// and cannot move out of the way. FEMA E-74's single strongest piece of
    /// advice is to put nothing heavy above or beside one.
    public var isSleepingPlace: Bool {
        self == .bed || self == .crib
    }

    /// Loading multiplier applied to the density prior when the user or the
    /// vision model reports the object as full. Case goods and shelving change
    /// mass by a factor of three or more between empty and full, which moves
    /// them across risk bands.
    public var respondsToLoading: Bool { hasSpillableContents }

    // MARK: - RoomPlan mapping

    /// The plausible refinements of a coarse RoomPlan category. The vision and
    /// language layers choose from this list rather than from the full
    /// taxonomy, which keeps the model from renaming a sofa into a wardrobe.
    public static func candidates(forRoomPlanCategory raw: String) -> [ObjectType] {
        switch raw {
        case "storage":
            return [.bookshelfTall, .bookshelfShort, .wardrobe, .dresser,
                    .nightstand, .highboy, .chinaCabinet, .filingCabinet,
                    .kitchenCabinetUpper, .trunk, .storageBin]
        case "refrigerator": return [.refrigerator]
        case "stove": return [.rangeElectric, .rangeGas]
        case "oven": return [.oven, .rangeElectric, .rangeGas]
        case "bed": return [.bed, .crib]
        case "sink": return [.sink]
        case "washerDryer": return [.washingMachine, .clothesDryer]
        case "toilet": return [.toilet]
        case "bathtub": return [.bathtub]
        case "dishwasher": return [.dishwasher]
        case "table": return [.diningTable, .desk, .coffeeTable, .nightstand]
        case "sofa": return [.sofa, .armchair]
        case "chair": return [.diningChair, .officeChair, .armchair]
        case "fireplace": return [.fireplace]
        case "television": return [.television, .televisionWallMounted, .computerMonitor]
        case "stairs": return [.stairs]
        default: return [.unknown]
        }
    }

    /// The safe default when nothing better is known — used before the vision
    /// pass returns, and whenever it fails.
    public static func fallback(forRoomPlanCategory raw: String) -> ObjectType {
        candidates(forRoomPlanCategory: raw).first ?? .unknown
    }
}
