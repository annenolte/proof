//
//  SafetyParameters.swift
//  proof — Core / Safety
//
//  Every threshold the engine uses, in one place.
//
//  CLAUDE.md §3 rule 2: no invented numbers. None of these values has a cited source yet,
//  so every one of them is marked `.assumption` and the UI says so wherever a number
//  derived from it is shown. When `docs/HAZARDS.md` gains a source for a value, change its
//  provenance to `.sourced` with the citation, and the "Assumption" badge goes away.
//

import Foundation

/// The developmental stage the caregiver is preparing for.
enum AgeStage: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case crawling
    case walking
    case climbing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .crawling: return "Crawling"
        case .walking: return "Walking"
        case .climbing: return "Climbing"
        }
    }

    /// The concern as a caregiver would say it — the translator's input.
    var concern: String {
        switch self {
        case .crawling: return "Getting ready for a baby who is starting to crawl"
        case .walking: return "Getting ready for a toddler who is pulling up and walking"
        case .climbing: return "Getting ready for a toddler who climbs on things"
        }
    }

    var symbol: String {
        switch self {
        case .crawling: return "figure.child"
        case .walking: return "figure.walk"
        case .climbing: return "figure.climbing"
        }
    }
}

/// Where a number came from.
enum ParameterProvenance: Codable, Hashable, Sendable {
    /// Placeholder chosen by the developer, not from a source. Shown as "Assumption".
    case assumption(note: String)
    /// From a cited source recorded in `docs/HAZARDS.md`.
    case sourced(citation: String)

    var isAssumption: Bool {
        if case .assumption = self { return true }
        return false
    }
}

struct SafetyParameter: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    var value: Float
    var unit: String
    var provenance: ParameterProvenance

    var formatted: String {
        unit == "m" ? String(format: "%.2f m", value) : String(format: "%.1f %@", value, unit)
    }
}

/// The engine's knobs for one age stage.
struct SafetyParameters: Codable, Hashable, Sendable {
    var stage: AgeStage
    /// How far above the surface a child is on they can reach.
    var reachHeight: SafetyParameter
    /// How far out horizontally from that surface they can reach.
    var horizontalReach: SafetyParameter
    /// The tallest step up a child can make from one surface to the next.
    var stepMax: SafetyParameter
    /// The widest horizontal gap they will cross between two surfaces.
    var gapMax: SafetyParameter
    /// Height ÷ narrowest footprint above which a free-standing object is a tip-over candidate.
    var tipRatio: SafetyParameter
    /// Minimum height for a tip-over candidate; below this a fall is not a crush.
    var tipMinHeight: SafetyParameter
    /// Hazards closer than this are drawn as a cluster.
    var clusterDistance: SafetyParameter
    /// Range of table heights whose corners are flagged.
    var cornerLow: SafetyParameter
    var cornerHigh: SafetyParameter

    var all: [SafetyParameter] {
        [reachHeight, horizontalReach, stepMax, gapMax, tipRatio, tipMinHeight,
         clusterDistance, cornerLow, cornerHigh]
    }

    var hasAssumptions: Bool { all.contains { $0.provenance.isAssumption } }

    /// The defaults. Placeholders until Stage 4 records sources — see the file header.
    static func forStage(_ stage: AgeStage) -> SafetyParameters {
        let note = "Placeholder. Needs a source in docs/HAZARDS.md."
        func p(_ id: String, _ title: String, _ value: Float, _ unit: String = "m") -> SafetyParameter {
            SafetyParameter(id: id, title: title, value: value, unit: unit,
                            provenance: .assumption(note: note))
        }
        let (reach, horizontal, step, gap, cornerHigh): (Float, Float, Float, Float, Float)
        switch stage {
        case .crawling: (reach, horizontal, step, gap, cornerHigh) = (0.55, 0.30, 0.20, 0.10, 0.60)
        case .walking: (reach, horizontal, step, gap, cornerHigh) = (0.90, 0.40, 0.30, 0.20, 0.80)
        case .climbing: (reach, horizontal, step, gap, cornerHigh) = (1.05, 0.50, 0.50, 0.30, 0.95)
        }
        return SafetyParameters(
            stage: stage,
            reachHeight: p("reachHeight", "Reach above standing surface", reach),
            horizontalReach: p("horizontalReach", "Horizontal reach", horizontal),
            stepMax: p("stepMax", "Largest climb step", step),
            gapMax: p("gapMax", "Largest gap crossed", gap),
            tipRatio: p("tipRatio", "Tip-over height ÷ base", 3.0, "×"),
            tipMinHeight: p("tipMinHeight", "Tip-over minimum height", 0.60),
            clusterDistance: p("clusterDistance", "Cluster distance", 0.60),
            cornerLow: p("cornerLow", "Corner flag, lowest table", 0.30),
            cornerHigh: p("cornerHigh", "Corner flag, highest table", cornerHigh)
        )
    }
}
