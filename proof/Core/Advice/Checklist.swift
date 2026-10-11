import Foundation
import simd

/// One line of the fix-it plan: a specific fix, for a specific object, with the
/// score it buys back.
public struct ChecklistItem: Codable, Hashable, Sendable, Identifiable {
    /// Stable across re-assessments, so a ticked box stays ticked.
    public var id: String
    public var objectID: UUID
    public var objectName: String
    public var objectSymbolName: String
    public var mitigation: Mitigation

    public var currentScore: Double
    public var currentBand: RiskBand
    /// The score this object has once its fixes are done — computed by
    /// re-running the risk engine on a mitigated copy of the room, not asserted.
    /// Carried on the object's leading fix; the others repeat the current score
    /// rather than double-count the same improvement.
    public var projectedScore: Double
    public var projectedBand: RiskBand
    /// True when this is the fix the score change is attributed to.
    public var isPrimary: Bool
    /// True when the risk engine has an actual number for the "after".
    public var isScored: Bool

    public init(
        id: String, objectID: UUID, objectName: String, objectSymbolName: String,
        mitigation: Mitigation, currentScore: Double, projectedScore: Double,
        isPrimary: Bool, isScored: Bool
    ) {
        self.id = id
        self.objectID = objectID
        self.objectName = objectName
        self.objectSymbolName = objectSymbolName
        self.mitigation = mitigation
        self.currentScore = currentScore
        self.currentBand = RiskBand(score: currentScore)
        self.projectedScore = projectedScore
        self.projectedBand = RiskBand(score: projectedScore)
        self.isPrimary = isPrimary
        self.isScored = isScored
    }

    /// Points of risk score this fix removes.
    public var pointsSaved: Double { max(currentScore - projectedScore, 0) }

    public var changesBand: Bool { projectedBand < currentBand }

    /// "Severe → Low" for the before/after chip.
    public var bandTransition: String {
        changesBand
            ? "\(currentBand.displayName) → \(projectedBand.displayName)"
            : currentBand.displayName
    }
}

/// One shopping line, aggregated across every fix in the plan that needs it.
public struct HardwareLine: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var specification: String
    public var quantity: Int
    public var approxCostUSD: Double

    public var displayLine: String {
        quantity > 1 ? "\(quantity) × \(name) — \(specification)"
                     : "\(name) — \(specification)"
    }
}

/// Everything the user can buy or do in one go.
public struct ShoppingTrip: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var venue: SupplyVenue
    public var itemIDs: [String]
    public var hardware: [HardwareLine]
    public var estimatedCostUSD: ClosedRange<Double>
    public var totalMinutes: Int

    public var title: String { venue.displayName }
    public var costBand: CostBand { CostBand(estimatedUSD: estimatedCostUSD) }

    /// A plain-text list the user can copy into their notes.
    public var copyableList: String {
        hardware.isEmpty
            ? "Nothing to buy."
            : hardware.map { "• \($0.displayLine)" }.joined(separator: "\n")
    }
}

/// The ordered action plan for one room.
public struct FixItPlan: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var roomID: UUID
    public var roomName: String
    public var intensity: MercalliIntensity

    /// Highest-impact first.
    public var items: [ChecklistItem]
    /// The same items, grouped by what the user would buy in one trip.
    public var trips: [ShoppingTrip]

    public var estimatedCostUSD: ClosedRange<Double>
    public var totalMinutes: Int

    public var currentScore: Double
    public var currentBand: RiskBand
    /// The room's score once every fix in this plan is done. The single most
    /// motivating number the app has, so it is computed by re-running the whole
    /// assessment on a mitigated copy of the room rather than estimated.
    public var projectedScore: Double
    public var projectedBand: RiskBand

    public init(
        id: UUID = UUID(), roomID: UUID, roomName: String,
        intensity: MercalliIntensity, items: [ChecklistItem], trips: [ShoppingTrip],
        estimatedCostUSD: ClosedRange<Double>, totalMinutes: Int,
        currentScore: Double, projectedScore: Double
    ) {
        self.id = id
        self.roomID = roomID
        self.roomName = roomName
        self.intensity = intensity
        self.items = items
        self.trips = trips
        self.estimatedCostUSD = estimatedCostUSD
        self.totalMinutes = totalMinutes
        self.currentScore = currentScore
        self.currentBand = RiskBand(score: currentScore)
        self.projectedScore = projectedScore
        self.projectedBand = RiskBand(score: projectedScore)
    }

    public var isEmpty: Bool { items.isEmpty }

    public var pointsSaved: Double { max(currentScore - projectedScore, 0) }

    public var costBand: CostBand { CostBand(estimatedUSD: estimatedCostUSD) }

    /// "6 fixes · about $74 · 2 hours" — the header card.
    public var headline: String {
        guard !items.isEmpty else { return "Nothing to fix in here." }
        let fixes = items.count == 1 ? "1 fix" : "\(items.count) fixes"
        return "\(fixes) · \(costSummary) · \(timeSummary)"
    }

    public var costSummary: String {
        if estimatedCostUSD.upperBound < 0.01 { return "free" }
        return String(format: "about $%.0f–%.0f",
                      estimatedCostUSD.lowerBound, estimatedCostUSD.upperBound)
    }

    public var timeSummary: String {
        if totalMinutes < 60 { return "\(totalMinutes) min" }
        let hours = Double(totalMinutes) / 60
        return hours.rounded() == hours
            ? "\(Int(hours)) hours"
            : String(format: "%.1f hours", hours)
    }

    /// "Severe (82) → Low (14)". The before-and-after.
    public var beforeAndAfter: String {
        String(format: "%@ (%.0f) → %@ (%.0f)",
               currentBand.displayName, currentScore,
               projectedBand.displayName, projectedScore)
    }

    /// The free fixes, called out because they are the ones people actually do.
    public var freeItems: [ChecklistItem] { items.filter { $0.mitigation.isFree } }

    /// The whole shopping list across every trip, ready to paste.
    public var shoppingList: String {
        let sections = trips.compactMap { trip -> String? in
            guard !trip.hardware.isEmpty else { return nil }
            return "\(trip.venue.displayName)\n\(trip.copyableList)"
        }
        return sections.isEmpty ? "Nothing to buy." : sections.joined(separator: "\n\n")
    }

    public func item(id: String) -> ChecklistItem? { items.first { $0.id == id } }

    public func items(forObject objectID: UUID) -> [ChecklistItem] {
        items.filter { $0.objectID == objectID }
    }
}

/// Turns a `RoomAssessment` into an ordered action plan, and prices the plan in
/// the only currency that matters: the room's score after the work is done.
public enum Checklist {

    /// The most fixes we show for a single object. Three is the point at which
    /// a detail sheet stops reading as advice and starts reading as a manual.
    public static let maximumFixesPerObject = 3

    /// Build the plan.
    ///
    /// - Parameters:
    ///   - assessment: the assessment to plan against.
    ///   - room: the room it was computed from.
    ///   - engine: the engine used for the "after" pass. Pass the same
    ///     configuration the assessment used, or the two numbers are not
    ///     comparable.
    ///   - minimumBand: the lowest band that earns a place in the plan.
    ///     Regulatory overrides are always included regardless.
    public static func plan(
        for assessment: RoomAssessment,
        room: ScannedRoom,
        engine: RiskEngine = RiskEngine(),
        minimumBand: RiskBand = .moderate
    ) -> FixItPlan {

        // ---- 1. Which objects are worth a plan entry, and what to do ----

        struct Candidate {
            let object: ScannedObject
            let risk: ObjectRisk
            let advice: [Mitigation]
            let primary: Mitigation?
        }

        var candidates: [Candidate] = []
        for object in room.objects {
            guard let risk = assessment.risk(for: object.id) else { continue }
            guard risk.band >= minimumBand || risk.hasRegulatoryOverride else { continue }
            let advice = Array(
                MitigationLibrary.advice(for: object, risk: risk, in: room)
                    .prefix(maximumFixesPerObject))
            guard !advice.isEmpty else { continue }
            candidates.append(Candidate(
                object: object, risk: risk, advice: advice,
                primary: advice.first { $0.effect.isModelled }))
        }

        guard !candidates.isEmpty else {
            return FixItPlan(
                roomID: room.id, roomName: room.name, intensity: assessment.intensity,
                items: [], trips: [], estimatedCostUSD: 0...0, totalMinutes: 0,
                currentScore: assessment.overallScore,
                projectedScore: assessment.overallScore)
        }

        // ---- 2. Re-run the engine on a mitigated copy of the room ----
        //
        // One pass, not one per fix. The risk engine scores each object from its
        // own geometry plus the room's beds, doors and floor, so anchoring the
        // bookcase does not perturb the dresser's number — which means a single
        // fully-mitigated assessment gives every object its own honest "after"
        // score, and gives the room its overall one.
        //
        // Every fix listed for an object is applied, because the plan asks the
        // user to do all of them. The resulting number is attributed to that
        // object's leading fix, which is what the detail sheet shows.

        var mitigatedObjects = room.objects
        for candidate in candidates {
            guard let index = mitigatedObjects.firstIndex(where: { $0.id == candidate.object.id })
            else { continue }
            for mitigation in candidate.advice where mitigation.effect.isModelled {
                mitigatedObjects[index] = apply(
                    mitigation.effect, to: mitigatedObjects[index], in: room)
            }
        }
        var mitigatedRoom = room
        mitigatedRoom.objects = mitigatedObjects

        let after = engine.assess(
            room: mitigatedRoom, intensity: assessment.intensity, seed: assessment.seed)

        // ---- 3. Items ----

        var grouped: [(candidate: Candidate, items: [ChecklistItem], saved: Double)] = []
        for candidate in candidates {
            let current = candidate.risk.score
            // Never advertise a fix as making things worse. The relocation
            // search maximises distance from the people in the room, so this
            // clamp should not bind; it exists so a pathological geometry can
            // never produce a plan that reads as a downgrade.
            let projected = min(after.risk(for: candidate.object.id)?.score ?? current, current)

            var items: [ChecklistItem] = []
            for mitigation in candidate.advice {
                let isPrimary = mitigation.id == candidate.primary?.id
                items.append(ChecklistItem(
                    id: "\(candidate.object.id.uuidString).\(mitigation.id)",
                    objectID: candidate.object.id,
                    objectName: candidate.object.type.displayName,
                    objectSymbolName: candidate.object.type.symbolName,
                    mitigation: mitigation,
                    currentScore: current,
                    projectedScore: isPrimary ? projected : current,
                    isPrimary: isPrimary,
                    isScored: isPrimary))
            }
            grouped.append((candidate, items, max(current - projected, 0)))
        }

        // Highest-impact object first, but keep an object's own fixes together:
        // a plan that scatters "anchor the bookcase" and "put the heavy books
        // low" across the list is a plan nobody follows.
        grouped.sort { a, b in
            if a.saved != b.saved { return a.saved > b.saved }
            if a.candidate.risk.score != b.candidate.risk.score {
                return a.candidate.risk.score > b.candidate.risk.score
            }
            return a.candidate.object.id.uuidString < b.candidate.object.id.uuidString
        }
        let items = grouped.flatMap(\.items)

        // ---- 4. Trips ----

        let trips = shoppingTrips(for: items)

        let cost = items.reduce(0.0...0.0) { total, item in
            let lower = total.lowerBound + item.mitigation.estimatedCostUSD.lowerBound
            let upper = total.upperBound + item.mitigation.estimatedCostUSD.upperBound
            return lower...upper
        }
        let minutes = items.reduce(0) { $0 + $1.mitigation.minutes }

        return FixItPlan(
            roomID: room.id, roomName: room.name, intensity: assessment.intensity,
            items: items, trips: trips,
            estimatedCostUSD: cost, totalMinutes: minutes,
            currentScore: assessment.overallScore,
            projectedScore: min(after.overallScore, assessment.overallScore))
    }

    // MARK: - Trips

    static func shoppingTrips(for items: [ChecklistItem]) -> [ShoppingTrip] {
        let byVenue = Dictionary(grouping: items) { $0.mitigation.venue }
        return byVenue.keys.sorted { $0.order < $1.order }.map { venue in
            let venueItems = byVenue[venue] ?? []
            // Aggregate hardware across the fixes in this trip, so the user buys
            // one box of lag screws rather than reading "4 lag screws" in four
            // different places.
            var lines: [String: HardwareLine] = [:]
            var order: [String] = []
            // A part is bought once per fix that needs it, but only once per
            // object–fix pair, which is exactly what `items` already is.
            for item in venueItems {
                for part in item.mitigation.hardware {
                    if var existing = lines[part.id] {
                        existing.quantity += part.quantity
                        existing.approxCostUSD += part.totalCostUSD
                        lines[part.id] = existing
                    } else {
                        lines[part.id] = HardwareLine(
                            id: part.id, name: part.name,
                            specification: part.specification,
                            quantity: part.quantity,
                            approxCostUSD: part.totalCostUSD)
                        order.append(part.id)
                    }
                }
            }
            let cost = venueItems.reduce(0.0...0.0) { total, item in
                let lower = total.lowerBound + item.mitigation.estimatedCostUSD.lowerBound
                let upper = total.upperBound + item.mitigation.estimatedCostUSD.upperBound
                return lower...upper
            }
            return ShoppingTrip(
                id: venue.rawValue,
                venue: venue,
                itemIDs: venueItems.map(\.id),
                hardware: order.compactMap { lines[$0] },
                estimatedCostUSD: cost,
                totalMinutes: venueItems.reduce(0) { $0 + $1.mitigation.minutes })
        }
    }

    // MARK: - Applying a fix to the model

    /// Produce the object as it would be after the fix, so the risk engine can
    /// score it honestly.
    ///
    /// Only the three effects the rigid-block model can actually represent do
    /// anything here. A positive latch on a cabinet door is worth doing and the
    /// app says so, but nothing in a block solution knows about china, so it
    /// changes no number and the plan does not pretend it does.
    public static func apply(
        _ effect: MitigationEffect,
        to object: ScannedObject,
        in room: ScannedRoom
    ) -> ScannedObject {
        var result = object

        if effect.setsAnchored {
            result.isAnchored = true
        }

        if let delta = effect.centreOfMassFractionDelta {
            let height = Double(result.extents.height)
            result.centreOfMassHeight = min(
                max(result.centreOfMassHeight + delta * height, 0.05 * height), height)
        }

        if effect.relocates {
            result = relocated(result, in: room)
        }

        return result
    }

    /// Move an object to the spot in the room that is furthest from anyone who
    /// might be under it and from the way out.
    ///
    /// This is what "move the bookcase away from the head of the bed" means in
    /// numbers. The search is a coarse grid rather than an optimiser because the
    /// answer only has to be good enough to show the user that rearranging the
    /// room earns most of what anchoring it would.
    public static func relocated(_ object: ScannedObject, in room: ScannedRoom) -> ScannedObject {
        var targets: [SIMD2<Float>] = room.occupantZones
            .filter { $0.id != object.id }
            .map(\.groundPosition)
        targets += room.egressOpenings.map { SIMD2($0.placement.centre.x, $0.placement.centre.z) }
        guard !targets.isEmpty else { return object }

        let walls = room.walls
        let xs = walls.map(\.placement.centre.x)
        let zs = walls.map(\.placement.centre.z)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minZ = zs.min(), let maxZ = zs.max(), maxX > minX, maxZ > minZ
        else { return object }

        let inset = max(object.extents.width, object.extents.depth) / 2 + 0.1
        let loX = minX + inset, hiX = maxX - inset
        let loZ = minZ + inset, hiZ = maxZ - inset
        guard hiX > loX, hiZ > loZ else { return object }

        let steps = 12
        var best = object.placement.centre
        var bestClearance = -Float.greatestFiniteMagnitude
        for i in 0...steps {
            for j in 0...steps {
                let x = loX + (hiX - loX) * Float(i) / Float(steps)
                let z = loZ + (hiZ - loZ) * Float(j) / Float(steps)
                let here = SIMD2(x, z)
                let clearance = targets.map { simd_distance(here, $0) }.min() ?? 0
                if clearance > bestClearance {
                    bestClearance = clearance
                    best = SIMD3(x, object.placement.centre.y, z)
                }
            }
        }

        var result = object
        result.placement = Placement(centre: best, yaw: object.placement.yaw)
        return result
    }
}
