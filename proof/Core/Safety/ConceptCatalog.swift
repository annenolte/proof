//
//  ConceptCatalog.swift
//  proof — Core / Safety
//
//  The concept map of CLAUDE.md §5 (`concepts/kitchen.yaml`): which SAM 3 noun phrase found
//  each object, and what that object is to a small child.
//
//  This is data a person approves, not something a model decides. `concepts/kitchen.yaml`
//  in the repo mirrors this table for review; if the two disagree, this file is what runs.
//
//  Surface heights come from the kitchen model's own authored dimensions (`Plan` and the
//  module geometry), so a chair's seat — not its backrest — is the step a child climbs.
//

import Foundation

struct ConceptEntry: Hashable, Sendable {
    /// Matched against the object id: exact, or as a prefix when it ends in ".".
    var idPattern: String
    /// The SAM 3 prompt that finds it.
    var concept: String
    var role: ObjectRole
    var hazards: [HazardKind]
    /// Standable surface heights in metres. `nil` means "the top of the bounds" for a
    /// climbable object, and nothing for anything else.
    var surfaces: [Float]?

    func matches(_ id: String) -> Bool {
        idPattern.hasSuffix(".") ? id.hasPrefix(idPattern) : id == idPattern
    }
}

enum ConceptCatalog {

    /// Shelf board heights of the ladder shelving, from `Plan.Shelf`.
    private static let shelfBoards: [Float] = (0..<5).map { 0.30 + Float($0) * (2.32 - 0.44) / 4 }

    static let kitchen: [ConceptEntry] = [
        // ── Kitchen run ──────────────────────────────────────────────────
        .init(idPattern: "kitchen.range", concept: "stove", role: .hazard, hazards: [.heat]),
        .init(idPattern: "kitchen.pan", concept: "pan", role: .hazard, hazards: [.heat]),
        .init(idPattern: "kitchen.kettle", concept: "kettle", role: .hazard, hazards: [.heat, .cords]),
        .init(idPattern: "kitchen.microwave", concept: "microwave", role: .hazard, hazards: [.heat]),
        .init(idPattern: "kitchen.oilBottle", concept: "bottle", role: .hazard, hazards: [.breakable]),
        .init(idPattern: "kitchen.plates", concept: "plate", role: .hazard, hazards: [.breakable]),
        .init(idPattern: "kitchen.mug.", concept: "mug", role: .hazard, hazards: [.breakable, .heat]),
        .init(idPattern: "kitchen.spiceRack", concept: "spice jar", role: .hazard, hazards: [.choking, .breakable]),
        .init(idPattern: "kitchen.cuttingBoard", concept: "cutting board", role: .hazard, hazards: [.sharp]),
        .init(idPattern: "kitchen.baseCabinets", concept: "cabinet", role: .hazard, hazards: [.chemicals]),
        .init(idPattern: "kitchen.dishwasher", concept: "dishwasher", role: .hazard, hazards: [.sharp, .chemicals]),
        .init(idPattern: "kitchen.sink", concept: "sink", role: .hazard, hazards: [.water, .chemicals]),
        .init(idPattern: "kitchen.countertop", concept: "countertop", role: .climbable, hazards: [], surfaces: [0.92]),
        .init(idPattern: "kitchen.fridge", concept: "refrigerator", role: .neutral, hazards: []),

        // ── Island and breakfast bar ─────────────────────────────────────
        .init(idPattern: "island.top", concept: "kitchen island", role: .climbable, hazards: [], surfaces: [0.92]),
        .init(idPattern: "island.stool.", concept: "bar stool", role: .both, hazards: [.tipOver, .falls], surfaces: [0.20, 0.676]),
        .init(idPattern: "island.wineBottle", concept: "wine bottle", role: .hazard, hazards: [.breakable]),
        .init(idPattern: "island.wineGlass.", concept: "wine glass", role: .hazard, hazards: [.breakable]),
        .init(idPattern: "island.tumbler", concept: "glass", role: .hazard, hazards: [.breakable]),
        .init(idPattern: "island.setting.", concept: "place setting", role: .hazard, hazards: [.sharp, .breakable]),
        .init(idPattern: "island.sidePlates", concept: "plate", role: .hazard, hazards: [.breakable]),
        .init(idPattern: "island.fruitBowl", concept: "bowl", role: .neutral, hazards: []),

        // ── Dining ───────────────────────────────────────────────────────
        .init(idPattern: "dining.table", concept: "dining table", role: .both, hazards: [.corners], surfaces: [0.74]),
        .init(idPattern: "dining.chair.", concept: "chair", role: .climbable, hazards: [], surfaces: [0.452]),
        .init(idPattern: "dining.hurricane", concept: "candle", role: .hazard, hazards: [.heat, .breakable]),
        .init(idPattern: "dining.carafe", concept: "glass carafe", role: .hazard, hazards: [.breakable]),
        .init(idPattern: "dining.servingBowl", concept: "bowl", role: .hazard, hazards: [.breakable]),

        // ── Living area, in the same scan ────────────────────────────────
        .init(idPattern: "living.sofa", concept: "sofa", role: .climbable, hazards: [], surfaces: [0.45]),
        .init(idPattern: "living.armchair", concept: "armchair", role: .climbable, hazards: [], surfaces: [0.44]),
        .init(idPattern: "living.pouf", concept: "ottoman", role: .climbable, hazards: []),
        .init(idPattern: "living.coffeeTable", concept: "coffee table", role: .both, hazards: [.corners], surfaces: [0.35]),
        .init(idPattern: "living.console", concept: "console table", role: .both, hazards: [.corners], surfaces: [0.796]),
        .init(idPattern: "living.ladderShelf", concept: "shelf", role: .both, hazards: [.tipOver, .falls], surfaces: shelfBoards),
        .init(idPattern: "living.tv", concept: "television", role: .hazard, hazards: [.tipOver, .cords]),
        .init(idPattern: "living.floorLamp", concept: "floor lamp", role: .hazard, hazards: [.tipOver, .cords]),
        .init(idPattern: "living.consoleLamp", concept: "lamp", role: .hazard, hazards: [.cords, .breakable]),
        .init(idPattern: "living.shelf.speaker", concept: "speaker", role: .hazard, hazards: [.cords]),
        .init(idPattern: "living.coffee.remotes", concept: "remote control", role: .hazard, hazards: [.choking]),
        .init(idPattern: "living.vase.", concept: "vase", role: .hazard, hazards: [.breakable]),
        .init(idPattern: "living.shelf.vase.", concept: "vase", role: .hazard, hazards: [.breakable]),
        .init(idPattern: "living.coffee.bowl", concept: "bowl", role: .hazard, hazards: [.breakable]),
        .init(idPattern: "living.shelf.bowl", concept: "bowl", role: .hazard, hazards: [.breakable]),
        .init(idPattern: "living.shelf.brassDish", concept: "dish", role: .hazard, hazards: [.choking]),

        // ── The envelope ─────────────────────────────────────────────────
        .init(idPattern: "shell.window.", concept: "window", role: .hazard, hazards: [.falls]),
    ]

    static func entry(for objectID: String) -> ConceptEntry? {
        // Longest pattern wins, so "living.shelf.vase." beats "living.shelf." if both exist.
        kitchen.filter { $0.matches(objectID) }.max { $0.idPattern.count < $1.idPattern.count }
    }

    /// The translator's output: the noun phrases SAM 3 is prompted with, in catalog order,
    /// without repeats. For the demo this is the cached result (CLAUDE.md §3 rule 9).
    static var nounPhrases: [String] {
        var seen = Set<String>()
        return kitchen.compactMap { seen.insert($0.concept).inserted ? $0.concept : nil }
    }

    /// The phrases a given stage cares most about, for the translator step. Deterministic:
    /// every stage gets the full vocabulary, ordered so the ones that matter most come first.
    static func nounPhrases(for stage: AgeStage) -> [String] {
        let priority: [String]
        switch stage {
        case .crawling:
            priority = ["cabinet", "dishwasher", "spice jar", "remote control", "floor lamp", "television", "window"]
        case .walking:
            priority = ["stove", "kettle", "coffee table", "dining table", "floor lamp", "shelf", "candle"]
        case .climbing:
            priority = ["chair", "bar stool", "shelf", "countertop", "kitchen island", "stove", "window"]
        }
        let rest = nounPhrases.filter { !priority.contains($0) }
        return priority + rest
    }
}
