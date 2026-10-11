import Foundation

// What the things in the demo apartment are made of.
//
// This is **authored ground truth**, not inference. Every prop in this room was modelled
// by hand from a known material — the wine glasses were authored as glass, the plates as
// stoneware, the chairs as oak — so "what is it made of" is a fact recorded in the scene
// file, exactly like its dimensions are. Nothing in this file is estimated from the
// walkthrough video, and nothing here is predicted at runtime. It is a lookup table.
//
// (The shipping product infers material from a scan and reports its confidence. That is a
// different problem living in `Core/`. Do not quote this file as evidence for it.)
//
// Densities are handbook bulk values, cited per entry. Restitution and friction are for
// the pairings that actually occur here — crockery on quartz, timber on an oak floor.

struct PhysicalMaterial {

    /// Stable key, used to seed the per-material sound variants.
    let id: String
    /// Bulk density, kg/m³.
    let density: Double
    /// Coefficient of restitution against a hard surface.
    let restitution: Float
    /// Kinetic friction against the surfaces in this room.
    let friction: Float
    /// 0 = fully ductile, 1 = fails with no plastic deformation at all.
    let brittleness: Double

    /// Specific fracture impulse, in N·s **per kg** of object mass.
    ///
    /// Stored per unit mass rather than absolute because brittle failure of geometrically
    /// similar objects is governed by impact *speed*, not by how much the object weighs:
    /// a heavy tumbler and a light one both survive the same knock and both break in the
    /// same fall. Since J = m·Δv·(1 + e), dividing out the mass leaves a threshold that
    /// reads directly as a critical impact speed. Multiply by the prop's mass to get the
    /// N·s figure the collision handler compares against.
    let specificFractureImpulse: Double

    /// How this material comes apart, and therefore what it sounds like. `nil` means it
    /// does not break in this demo at any impulse the earthquake can produce.
    let failure: Failure?

    enum Failure {
        /// Thin-walled, many small sharp shards, bright noise.
        case glass
        /// Thicker, fewer and chunkier shards, a duller and shorter report.
        case ceramic
    }

    var isBrittle: Bool { failure != nil }

    /// The absolute impulse, in N·s, above which a prop of this mass shatters.
    func fractureImpulse(forMass mass: Double) -> Double {
        specificFractureImpulse * max(mass, 0.01)
    }

    /// The threshold read the way it is actually meant to be read: a **critical impact
    /// speed**, in m/s.
    ///
    /// This is the number to argue about, not the impulse. The collision handler compares
    /// `m · v · (1 + e)` against `specificFractureImpulse · m`, and the mass cancels
    /// exactly — which is the whole point of storing the threshold per kilogram. What is
    /// left is `v > specificFractureImpulse / (1 + e)`. Writing it out:
    ///
    /// | material  | J/kg | e    | critical v | reached by |
    /// |-----------|------|------|-----------|------------|
    /// | stemware  | 0.9  | 0.34 | 0.67 m/s  | toppling on the island — a 0.21 m glass turning about its foot arrives at roughly 1.1 m/s at the rim |
    /// | glass     | 1.8  | 0.38 | 1.30 m/s  | a bottle toppling (≈1.6 m/s at the shoulder), or any fall over 9 cm |
    /// | ceramic   | 3.4  | 0.30 | 2.62 m/s  | a plate leaving the island (0.92 m ⇒ 4.25 m/s); rattling in place will not do it |
    /// | porcelain | 2.7  | 0.34 | 2.01 m/s  | a 21 cm fall |
    ///
    /// So the thresholds are reachable in this room at MMI VII and above, and reachable
    /// through the two motions the quake actually produces — toppling and sliding off an
    /// edge. They were checked against these numbers rather than lowered until something
    /// broke, and a plate that merely chatters on the quartz correctly survives.
    var criticalImpactSpeed: Double {
        specificFractureImpulse / Double(1 + restitution)
    }

    /// How many pieces this material comes apart into, before the global shard budget has
    /// its say. Bounds rather than a single number because the count also scales with the
    /// size of the object: a pane throws far more glass than a tumbler.
    ///
    /// The lower bounds are the interesting ones. Three or four fragments does not read as
    /// breaking — it reads as an object splitting, which is a different and much less
    /// convincing event. Fifteen is about where a pane stops looking cracked and starts
    /// looking shattered; eight is the floor for stoneware, which genuinely does come apart
    /// into a handful of chunks.
    var shardCountRange: ClosedRange<Int> {
        switch failure {
        case .glass:   return 15...40
        case .ceramic: return 8...20
        case nil:      return 0...0
        }
    }

    /// Which synthesised break this material makes. Deliberately finer-grained than
    /// `failure`: a wine glass, a wine bottle and a dropped plate are three different
    /// sounds, and giving thin and thick glass the same sample is the tell that the audio
    /// is a library rather than the object.
    var breakCue: DemoAudio.Cue {
        switch id {
        case "stemware":  return .stemwareShatter
        case "porcelain": return .porcelainBreak
        default:
            return failure == .glass ? .glassShatter : .ceramicBreak
        }
    }
}

// MARK: - The library

extension PhysicalMaterial {

    /// Soda-lime container glass — bottles, the vase, the hurricane vessel. Density
    /// 2500 kg/m³ (Corning soda-lime datasheet, 2.44–2.52 g/cm³). Walls of 2–4 mm;
    /// 1.8 N·s/kg is about a 1.3 m/s impact, so a bottle knocked over on stone breaks and
    /// one that merely slides does not.
    static let glass = PhysicalMaterial(
        id: "glass", density: 2500, restitution: 0.38, friction: 0.28,
        brittleness: 0.97, specificFractureImpulse: 1.8, failure: .glass
    )

    /// The same soda-lime glass, blown thin. Stemware walls run under a millimetre at the
    /// bowl, and wall thickness — not material — is what decides whether a glass survives
    /// being knocked over: 0.9 N·s/kg is a 0.65 m/s impact, about a 2 cm fall onto stone,
    /// which is genuinely where thin stemware goes.
    static let stemware = PhysicalMaterial(
        id: "stemware", density: 2500, restitution: 0.34, friction: 0.28,
        brittleness: 0.98, specificFractureImpulse: 0.9, failure: .glass
    )

    /// Glazed stoneware — the plates, the bowls, the terracotta. Density 2300 kg/m³
    /// (stoneware body, 2.2–2.4 g/cm³ fired). Thicker section than stemware, so it takes
    /// about twice the impact speed.
    static let ceramic = PhysicalMaterial(
        id: "ceramic", density: 2300, restitution: 0.30, friction: 0.34,
        brittleness: 0.92, specificFractureImpulse: 3.4, failure: .ceramic
    )

    /// Vitrified porcelain. Density 2400 kg/m³. Harder and more brittle than stoneware,
    /// and thinner in section, so it sits between glass and stoneware. Nothing currently
    /// in the room is authored as porcelain — the place settings are explicitly matte
    /// stoneware — but it is here for the next piece of tableware that is.
    static let porcelain = PhysicalMaterial(
        id: "porcelain", density: 2400, restitution: 0.34, friction: 0.30,
        brittleness: 0.95, specificFractureImpulse: 2.7, failure: .ceramic
    )

    /// White oak, the floor and most of the furniture. Density 750 kg/m³ (Wood Handbook,
    /// FPL-GTR-190: white oak 0.68–0.77 g/cm³ at 12% MC). Splits rather than shatters, and
    /// nothing in this room hits hard enough to split a chair, so it does not break.
    static let hardwood = PhysicalMaterial(
        id: "hardwood", density: 750, restitution: 0.24, friction: 0.52,
        brittleness: 0.22, specificFractureImpulse: 46, failure: nil
    )

    /// Foam-and-fabric seating. Effective density 90 kg/m³ for the assembly — the sofa is
    /// mostly air. Absorbs almost everything it hits. A sofa must never shatter.
    static let upholstery = PhysicalMaterial(
        id: "upholstery", density: 90, restitution: 0.08, friction: 0.68,
        brittleness: 0.02, specificFractureImpulse: .infinity, failure: nil
    )

    /// Austenitic stainless, the appliances and the table pedestal. Density 7900 kg/m³
    /// (AISI 304, 7.85–8.0 g/cm³). Dents; does not fracture.
    static let steel = PhysicalMaterial(
        id: "steel", density: 7900, restitution: 0.42, friction: 0.36,
        brittleness: 0.10, specificFractureImpulse: .infinity, failure: nil
    )

    /// Brass fittings — lamp stems, shelf uprights. Density 8500 kg/m³ (C260 cartridge
    /// brass, 8.53 g/cm³).
    static let brass = PhysicalMaterial(
        id: "brass", density: 8500, restitution: 0.40, friction: 0.34,
        brittleness: 0.12, specificFractureImpulse: .infinity, failure: nil
    )

    /// Engineered quartz — the island slab and the kitchen counter. Density 2450 kg/m³
    /// (~93% quartz aggregate in polyester resin). Brittle in principle, but it is a fixed
    /// prop bonded to cabinetry: nothing in this demo can load it enough to matter.
    static let stone = PhysicalMaterial(
        id: "stone", density: 2450, restitution: 0.32, friction: 0.44,
        brittleness: 0.80, specificFractureImpulse: 140, failure: nil
    )

    /// Injection-moulded ABS and polypropylene — jar caps, appliance trim. Density
    /// 1050 kg/m³ (ABS 1.04, PP 0.90–0.91). Bounces and scuffs.
    static let plastic = PhysicalMaterial(
        id: "plastic", density: 1050, restitution: 0.44, friction: 0.38,
        brittleness: 0.18, specificFractureImpulse: .infinity, failure: nil
    )

    /// Book blocks, labels, napkins. Density 800 kg/m³ for a bound page block (uncoated
    /// offset stock, compressed). Tears; does not fracture.
    static let paper = PhysicalMaterial(
        id: "paper", density: 800, restitution: 0.06, friction: 0.50,
        brittleness: 0.05, specificFractureImpulse: .infinity, failure: nil
    )

    /// Wool pile and cotton weave — the rug, the pouf, the shades.
    static let textile = PhysicalMaterial(
        id: "textile", density: 260, restitution: 0.05, friction: 0.72,
        brittleness: 0.02, specificFractureImpulse: .infinity, failure: nil
    )
}

// MARK: - Which prop is made of what

enum MaterialAssignment {

    /// Authored per prop. Where a prop is made of several materials it is listed under the
    /// one that governs how it fails: the hurricane candle is a wooden coaster, a wax
    /// candle and a glass vessel, and it is the vessel that breaks.
    private static let byPropID: [String: PhysicalMaterial] = [
        // Glass
        "island.wineGlass.a": .stemware,
        "island.wineGlass.b": .stemware,
        "island.wineBottle": .glass,
        "dining.hurricane": .glass,
        "living.vase.amber": .glass,
        "kitchen.oilBottle": .glass,

        // Ceramic and porcelain
        "island.setting.a": .ceramic,
        "island.setting.b": .ceramic,
        // The dining top is authored as a sintered slab on a steel pedestal, not as a
        // scaled-up plate. A 1.1 m slab chips at a corner; it does not come apart into
        // shards, and there are no authored fragments for it.
        "dining.table": .stone,

        // Brittle, but with nothing in the name to say so. Each is listed because the
        // part that governs its failure is not the part the name describes.
        //
        // A framed photograph is a metal frame, a paper print and a sheet of glazing;
        // the glazing is what ends up on the floor. A television is a painted shell and
        // a glass panel, and a 32-inch panel that comes off a 730 mm console does not
        // survive — the shell is intact and the screen is destroyed, which is exactly
        // what the room should show.
        "living.shelf.framedPhoto": .glass,
        "living.tv": .glass,

        // Not brittle, but named after a shape rather than a substance, so the keyword
        // tier below cannot see it. Left unlisted, every one of these was defaulting to
        // ceramic through `.decor`/`.tableware` and shattering: a brass dish, a timber
        // box and a stainless kettle were coming apart into crockery shards.
        "living.shelf.brassDish": .brass,
        "living.shelf.box": .hardwood,
        "living.coffee.remotes": .plastic,
        "kitchen.kettle": .steel,
        // A white-glazed vessel whose name says only that it is short.
        "living.shelf.vase.squat": .ceramic,

        // Everything else that is explicitly not brittle
        "kitchen.pan": .steel,
        "kitchen.cuttingBoard": .hardwood,
        "kitchen.spiceRack": .hardwood,
        "living.books.coffee": .paper,
        "living.pouf": .textile,
        "living.rug": .textile,
        "living.sofa": .upholstery,
        "living.sofa.cushionA": .upholstery,
        "living.sofa.cushionB": .upholstery,
        "living.armchair": .upholstery,
        "living.floorLamp": .brass,
        "living.consoleLamp": .brass,
        "living.ladderShelf": .hardwood,
        "living.console": .hardwood,
        "living.coffeeTable": .hardwood,
        "kitchen.fridge": .steel,
        "kitchen.sink": .steel
    ]

    /// Second tier: what the thing is called.
    ///
    /// The room gains props over time, and the breakage system must pick a new tumbler up
    /// as glass on the day it is authored, without anyone remembering to come back here
    /// and add its id. `DemoProp.Category` alone cannot do that — `.tableware` covers both
    /// a wine glass and a wooden bread board, and `.decor` covers both a vase and a bowl
    /// of books.
    ///
    /// So the prop's own id and display name are read for the noun. This is not inference
    /// in the sense the product means it — there is no model and no confidence interval.
    /// It is a naming convention being honoured: a prop called `island.tumbler.a` was
    /// authored as a tumbler by a person who knew tumblers are glass. Where the convention
    /// is not enough, `byPropID` above still wins outright.
    ///
    /// Order matters, and it matters in two ways.
    ///
    /// First, **a word that names a substance beats a word that names a shape.** "Vase"
    /// is a shape; most vases are glass, so it earns a place in the glass row. But a
    /// *terracotta* vase is fired clay, and the author said so in the name. Running the
    /// shape nouns first classified all three shelf vases — terracotta, stoneware and
    /// clay — as glass, and they would have shattered bright and transparent instead of
    /// dull and opaque. So the substance words are their own tier and they run first;
    /// only when nothing in the name says what the thing is made of does the shape of it
    /// get to guess.
    ///
    /// Second, within a tier, `stemware` before `glass` so a *wine glass* is thin-walled
    /// stemware and not a bottle; the specific words before the general ones throughout.
    ///
    /// Every token here is matched as a **substring** of the id and name run together with
    /// their separators stripped, which is what makes `island.wineGlass.a` match
    /// `wineglass` — and which is also the trap. The obvious short nouns are all wrong:
    /// `cup` matches *cupboard*, `dish` matches *dishwasher*, `pot` matches *spotlight*,
    /// `pan` matches *panel*, `tin` matches *tinted*. Each of those would have quietly
    /// relabelled a built-in appliance as crockery. So the list is deliberately short and
    /// every entry is a word that cannot hide inside another word used in this room. When
    /// in doubt, leave it out and let the category fallback answer — a wrong material here
    /// is worse than no match, because a wrong one is confidently wrong.
    private static let byKeyword: [(tokens: [String], material: PhysicalMaterial)] = [
        // --- Tier one: the name says what it is made of. This always wins.
        (["porcelain", "bonechina"], .porcelain),
        (["terracotta", "stoneware", "earthenware", "clay", "ceramic"], .ceramic),
        (["brass", "bronze", "copper"], .brass),
        (["stainless", "steel", "castiron"], .steel),
        (["walnut", "oak", "teak", "timber", "wooden"], .hardwood),

        // --- Tier two: the name says only what shape it is, so the likeliest substance
        // for that shape is the best available answer.
        (["wineglass", "stemware", "flute", "coupe", "goblet", "champagne"], .stemware),
        (["tumbler", "bottle", "carafe", "decanter", "vase", "mirror",
          "hurricane", "pitcher", "jar", "glass"], .glass),
        (["teacup", "saucer"], .porcelain),
        (["plate", "bowl", "mug", "platter", "ramekin"], .ceramic),
        (["book", "canvas", "poster"], .paper),
        (["cuttingboard", "breadboard", "crate", "stool"], .hardwood)
    ]

    /// Category is the last fallback, for anything neither named nor recognisable, so a
    /// prop added later still gets a defensible material rather than nothing.
    private static func fallback(for category: DemoProp.Category) -> PhysicalMaterial {
        switch category {
        case .seating, .softFurnishing: return .upholstery
        case .table, .storage, .cabinetry: return .hardwood
        case .appliance: return .steel
        case .lighting: return .brass
        case .glazing: return .glass
        case .art: return .paper
        // Loose crockery is the common case on these surfaces, and it is the one that has
        // to be got right — the tableware is what an earthquake actually destroys.
        case .tableware: return .ceramic
        // Changed from hardwood. Every loose `.decor` object authored in this apartment so
        // far is a vessel — a vase, a hurricane candle, an ornament — and the wooden ones
        // (the spice rack, the book stack) are all named in `byPropID` already. Defaulting
        // decor to timber meant a vase added tomorrow would bounce off the floor intact,
        // which is the wrong way round: the safe default for an unrecognised ornament is
        // that it is breakable, because most of them are.
        case .decor: return .ceramic
        case .structure: return .stone
        }
    }

    /// The full lookup: authored id, then the naming convention, then the category.
    ///
    /// There is deliberately no id-only convenience overload. One existed briefly and
    /// both callers in the app disagreed with each other because of it: dropping the
    /// display name throws away half of what the keyword tier reads, so the same prop
    /// could break as glass on screen and be reported as ceramic in the analysis. Making
    /// the name mandatory makes that divergence unrepresentable.
    static func material(
        forPropID id: String, name: String, category: DemoProp.Category
    ) -> PhysicalMaterial {
        if let exact = byPropID[id] { return exact }

        // Both the id and the human name, lowercased and stripped of separators, so
        // "island.wineGlass.a" and "Wine glass" both contain "wineglass".
        let haystack = (id + " " + name).lowercased()
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
        for entry in byKeyword where entry.tokens.contains(where: haystack.contains) {
            return entry.material
        }
        return fallback(for: category)
    }
}
