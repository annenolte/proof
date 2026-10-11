import Foundation

// Which fix to do first, if money is the constraint.
//
// The analysis already says what each object needs. This answers the question a person
// standing in a hardware store actually has: *which of these buys the most safety for the
// least money?* — "this $10 tub of putty does more than that $35 bracket".
//
// Two things are measured and one is assumed:
//
//   * **Risk removed** is measured. It is the room's safety score recomputed, with the same
//     arithmetic the score itself uses (`RoomAnalysisModel.safetyScore(for:)`), without the
//     findings this fix covers — minus the score as it stands.
//   * **Cost** is the real range already on each `Mitigation` from `Core/Advice`, built
//     from its hardware list. Nothing is priced here.
//   * **That the fix works** is assumed: a fixed object is taken not to fail at all in this
//     earthquake. That is what FEMA E-74 intends each fix to achieve, and it is stated on
//     screen rather than left implicit.
//
// The one policy authored here is which fixes are bought once for the room and which once
// per object. A tub of putty or a roll of shelf lip covers everything; an L-bracket covers
// one bookcase.

struct RetrofitOption: Identifiable, Equatable {

    let mitigation: Mitigation
    /// The objects this fix covers, worst first.
    let findings: [RoomFinding]
    /// What doing it costs for all of `findings`.
    let costUSD: ClosedRange<Double>
    /// Room safety points gained by doing only this fix.
    let pointsGained: Int

    var id: String { mitigation.id }

    var isFree: Bool { costUSD.upperBound < 0.01 }

    /// Points per dollar at the middle of the cost range. `nil` for a free fix, which
    /// always ranks ahead of anything that costs money.
    var pointsPerDollar: Double? {
        guard !isFree else { return nil }
        let middle = (costUSD.lowerBound + costUSD.upperBound) / 2
        return Double(pointsGained) / max(middle, 1)
    }

    /// "Wine glass, Vase and 2 more"
    var objectSummary: String {
        let names = findings.map(\.name)
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return "\(names[0]), \(names[1]) and \(names.count - 2) more"
        }
    }

    /// Fixes bought once and used across the whole room.
    static let roomWideSupplies: Set<String> = ["museum-putty", "anti-slip-mat", "shelf-lip"]

    // MARK: - Ranking

    /// Every distinct fix the findings call for, best value first: free fixes by points,
    /// then paid fixes by points per dollar, ties to the bigger gain.
    static func ranked(findings: [RoomFinding], currentScore: Int) -> [RetrofitOption] {
        let groups = Dictionary(grouping: findings, by: \.mitigation.id)

        let options = groups.values.map { covered -> RetrofitOption in
            let mitigation = covered[0].mitigation
            let ids = Set(covered.map(\.id))
            let remaining = findings.filter { !ids.contains($0.id) }
            let gained = RoomAnalysisModel.safetyScore(for: remaining) - currentScore

            let unit = mitigation.estimatedCostUSD
            let copies = roomWideSupplies.contains(mitigation.id) ? 1.0 : Double(covered.count)
            return RetrofitOption(
                mitigation: mitigation,
                findings: covered.sorted { $0.score > $1.score },
                costUSD: (unit.lowerBound * copies)...(unit.upperBound * copies),
                pointsGained: max(gained, 0))
        }

        return options.sorted { a, b in
            switch (a.pointsPerDollar, b.pointsPerDollar) {
            case (nil, nil):
                if a.pointsGained != b.pointsGained { return a.pointsGained > b.pointsGained }
            case (nil, _): return true
            case (_, nil): return false
            case let (x?, y?):
                if x != y { return x > y }
                if a.pointsGained != b.pointsGained { return a.pointsGained > b.pointsGained }
            }
            return a.mitigation.title < b.mitigation.title
        }
    }

    /// The cost of doing every option.
    static func totalCost(_ options: [RetrofitOption]) -> ClosedRange<Double> {
        let low = options.reduce(0) { $0 + $1.costUSD.lowerBound }
        let high = options.reduce(0) { $0 + $1.costUSD.upperBound }
        return low...high
    }
}
