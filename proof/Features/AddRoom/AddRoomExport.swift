//
//  AddRoomExport.swift
//  Tremor — Add Room / turning the reconstructed room into a room the library owns
//
//  WHY THIS EXISTS
//  ---------------
//  Until this file, the Add Room flow ended at the report and nothing was written to disk.
//  That was defensible while the flow was a demo, and indefensible the moment it became the
//  product's front door: a user who names a room "Living room", watches it get built,
//  shakes it and reads its report goes back to the Rooms tab and finds… the seeded sample
//  that happens to carry the same name. The flow looked like it had saved. It had not, and
//  the collision made the failure invisible, which is the worst version of it.
//
//  So the reconstructed apartment is converted, here, into an ordinary `ScannedRoom` and
//  handed to the ordinary `RoomStore`. From that point on it is not special: the library
//  card, the room detail, the report and the delete all work on it the way they work on
//  anything else, because it is the same type.
//
//  WHAT IS HONEST ABOUT THE CONVERSION, AND WHAT IS NOT
//  ----------------------------------------------------
//  Everything written here is measured off the scene that was actually built and actually
//  shaken: the prop's settled pose, its collider extents and its authored mass. Nothing is
//  invented to fill a field.
//
//  What it is *not* is a scan of the user's own room. The apartment is hand-authored, and
//  the honest label for where its objects came from is `.scanner` — the geometry pipeline
//  the app itself produced — at a confidence that says so, never `.cloudVision`, which
//  would put an "Identified by Tremor" badge on values a person typed into a Swift file.
//  That mistake has been made once in this repository already; see §5 of
//  docs/handoff/01-CURRENT-STATE.md.
//
//  Only the props the earthquake is allowed to move are exported. The walls, the floor and
//  the built-in cabinetry are structure: the shell becomes four `RoomSurface` walls, which
//  is what `floorArea` and `ceilingHeight` read, and the rest is not an object in the sense
//  the risk engine means.
//

import Foundation
import RealityKit
import simd

/// Converts the finished demo apartment into a `ScannedRoom` the library can hold.
@MainActor
enum AddRoomExport {

    /// Builds the room record. Pure — it writes nothing and touches no store, so it can be
    /// unit-tested against a scene without a disk.
    ///
    /// - Parameters:
    ///   - name: what the user called it on the naming screen.
    ///   - scene: the apartment, after it has settled.
    static func room(named name: String, from scene: ApartmentScene?) -> ScannedRoom {
        ScannedRoom(
            name: name,
            kind: kind(for: name),
            building: BuildingContext(),
            surfaces: shellSurfaces(),
            objects: scene.map(objects(in:)) ?? []
        )
    }

    // MARK: - The shell

    /// The apartment's four walls, taken from `Plan` so they cannot drift from the geometry
    /// the user just walked around. A floor and a ceiling are not included: `ScannedRoom`
    /// derives floor area from the wall extent, and a floor surface would double-count it.
    private static func shellSurfaces() -> [RoomSurface] {
        let h = Plan.ceilingHeight
        let w = Plan.width
        let l = Plan.length
        // Walls are authored centre-out, with `yaw` meaning "the width axis points this
        // way" — the same convention `Placement.transform` uses.
        return [
            wall(centre: SIMD3(w / 2, h / 2, 0), yaw: 0, width: w, height: h),
            wall(centre: SIMD3(w / 2, h / 2, l), yaw: 0, width: w, height: h),
            wall(centre: SIMD3(0, h / 2, l / 2), yaw: .pi / 2, width: l, height: h),
            wall(centre: SIMD3(w, h / 2, l / 2), yaw: .pi / 2, width: l, height: h)
        ]
    }

    private static func wall(
        centre: SIMD3<Float>, yaw: Float, width: Float, height: Float
    ) -> RoomSurface {
        RoomSurface(
            kind: .wall,
            placement: Placement(centre: centre, yaw: yaw),
            extents: Extents(width: width, height: height, depth: wallThickness)
        )
    }

    /// 0.10 m. Nominal, and it only feeds the wall's own bounding box.
    private static let wallThickness: Float = 0.10

    // MARK: - The objects

    /// One `ScannedObject` per movable prop, measured off the scene.
    ///
    /// Ordered by the scene's own build order rather than by a dictionary's iteration, so
    /// two exports of the same room produce the same list — the library's object count and
    /// the report's ordering must not change because a hash seed did.
    private static func objects(in scene: ApartmentScene) -> [ScannedObject] {
        var built: [ScannedObject] = []
        for id in scene.order {
            guard let prop = scene.props[id], prop.isMovable, prop.mass.isFinite else { continue }
            let transform = prop.restTransform
            let half = prop.halfExtents
            // A prop's origin is the centre of its footprint on its own floor; `Placement`
            // wants the centre of the bounding box, so the vertical is lifted by half the
            // height.
            let centre = SIMD3(
                transform.translation.x,
                transform.translation.y + half.y,
                transform.translation.z)
            built.append(ScannedObject(
                type: type(for: prop),
                placement: Placement(centre: centre, yaw: yaw(of: transform)),
                extents: Extents(width: half.x * 2, height: half.y * 2, depth: half.z * 2),
                provenance: IdentificationProvenance(
                    source: .scanner,
                    confidence: geometryConfidence,
                    scannerCategory: prop.category.rawValue),
                mass: prop.mass,
                supportHeight: Double(transform.translation.y)))
        }
        return built
    }

    /// 0.7 — the confidence a geometry-only identification earns. High enough that the UI
    /// does not flag every object as uncertain, low enough that it never claims a vision
    /// pass happened. `IdentificationProvenance.isUncertain` cuts at 0.6.
    private static let geometryConfidence: Double = 0.7

    /// Yaw about world Y, recovered from the settled rotation. Rotating the local +X axis
    /// and reading its bearing is the inverse of what `Placement.transform` does, so a
    /// round trip through the store returns the object facing the way it faced.
    private static func yaw(of transform: Transform) -> Float {
        let axis = transform.rotation.act(SIMD3<Float>(1, 0, 0))
        return atan2(axis.z, axis.x)
    }

    // MARK: - Naming the type

    /// The prop's display name decides its catalogue type, within a shortlist its category
    /// allows.
    ///
    /// The matcher is the product's own `ObjectTypeMatcher`, not a second table written
    /// here: the room says "Navy tufted sofa" and "Ladder shelf", and those are exactly the
    /// free-text strings the classifier's keyword tier is built to resolve. Shortlisting by
    /// category is what stops "Counter stool" being read as a dining chair's cousin from a
    /// completely different family.
    private static func type(for prop: ApartmentScene.PropEntity) -> ObjectType {
        let shortlist = shortlist(for: prop.category)
        if let matched = ObjectTypeMatcher.match(freeText: prop.name, within: shortlist) {
            return matched
        }
        return shortlist.first ?? .unknown
    }

    /// The catalogue types each authored category is allowed to resolve to. First entry is
    /// the fallback, so it is the one that is right when the name says nothing useful.
    private static func shortlist(for category: DemoProp.Category) -> [ObjectType] {
        switch category {
        case .storage:
            return [.bookshelfTall, .bookshelfShort, .chinaCabinet, .dresser, .trunk,
                    .storageBin, .nightstand]
        case .cabinetry:
            return [.kitchenCabinetUpper, .chinaCabinet, .filingCabinet]
        case .appliance:
            return [.refrigerator, .dishwasher, .rangeGas, .rangeElectric, .oven,
                    .microwave, .washingMachine, .clothesDryer]
        case .seating:
            return [.armchair, .sofa, .diningChair, .officeChair]
        case .table:
            return [.coffeeTable, .diningTable, .desk, .nightstand]
        case .lighting:
            return [.tableLamp, .floorLamp]
        case .art:
            return [.framedPicture, .mirrorWall, .mirrorLeaning]
        case .softFurnishing:
            return [.storageBin]
        case .tableware, .decor:
            return [.vaseCeramic, .vaseGlass, .books, .plantPotSmall, .plantPotLarge,
                    .speaker, .television, .computerMonitor]
        case .glazing, .structure:
            return [.unknown]
        }
    }

    // MARK: - Naming the room

    /// Reads the user's own words for a room kind, defaulting to `.other` rather than
    /// guessing. The kind only affects the library card's glyph and the report's phrasing;
    /// nothing in the physics depends on it, so a wrong guess would cost more than a blank.
    private static func kind(for name: String) -> RoomKind {
        let lowered = name.lowercased()
        for (needle, kind) in kindKeywords where lowered.contains(needle) { return kind }
        return .other
    }

    private static let kindKeywords: [(String, RoomKind)] = [
        ("living", .livingRoom), ("lounge", .livingRoom), ("sitting", .livingRoom),
        ("bed", .bedroom), ("nursery", .nursery), ("kitchen", .kitchen),
        ("dining", .diningRoom), ("office", .office), ("study", .office),
        ("bath", .bathroom), ("hall", .hallway), ("garage", .garage),
        ("basement", .basement), ("studio", .livingRoom)
    ]
}
