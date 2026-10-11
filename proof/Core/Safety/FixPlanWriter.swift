//
//  FixPlanWriter.swift
//  proof — Core / Safety
//
//  Writes a constellation's fix plan from its structured data.
//
//  CLAUDE.md §9 Stage 8 puts a Claude call here, server side and cached. This is the
//  deterministic version that runs with no network and no key: it uses only the objects,
//  measured relations and categories it is handed, invents nothing, and speaks in "check"
//  and "consider". It is also the fallback the server version must degrade to.
//

import Foundation

enum FixPlanWriter {

    static let disclaimer = "These are flags to check, not a safety guarantee."

    static func plan(
        name: String, starIDs: [String], analysis: SafetyAnalysis, chain: Chain? = nil
    ) -> String {
        var lines: [String] = []
        if let chain {
            lines.append("The path: \(chain.why).")
        }
        var number = 1
        for id in starIDs {
            guard let object = analysis.object(id) else { continue }
            let flags = analysis.flags(for: id)
            var line = "\(number). Check the \(object.label.lowercased())"
            if let surface = SafetyEngine.standableSurfaces(of: object).last, object.role.isClimbable {
                line += String(format: " — a child can stand on it at %.2f m", surface)
            }
            let kinds = flags.map(\.kind.title).map { $0.lowercased() }
            if !kinds.isEmpty { line += " (\(kinds.joined(separator: ", ")))" }
            line += "."
            let fixes = (flags.flatMap(\.fixTypes) + (object.role.isClimbable && chain != nil ? HazardKind.falls.fixTypes : []))
            let unique = fixes.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            if !unique.isEmpty {
                line += " Consider: " + unique.prefix(2).map { $0.lowercased() }.joined(separator: "; ") + "."
            }
            lines.append(line)
            number += 1
        }
        if chain != nil {
            lines.append("Removing any one step breaks the path. Moving the first thing a child climbs is often the quickest check.")
        }
        lines.append(disclaimer)
        return lines.joined(separator: "\n")
    }

    /// Suggested constellations: chains that share a climbing route become one group, named
    /// after the route. The caregiver keeps, renames or ignores them.
    static func suggestions(for analysis: SafetyAnalysis) -> [Constellation] {
        let grouped = Dictionary(grouping: analysis.chains) { Array($0.nodeIDs.dropLast()) }
        return grouped.keys.sorted { $0.joined() < $1.joined() }.compactMap { route in
            guard let chains = grouped[route], let first = chains.first else { return nil }
            let routeNames = route.compactMap { analysis.object($0)?.label }
            let hazards = chains.map(\.hazardID)
            let hazardNames = hazards.compactMap { analysis.object($0)?.label }
            // Labels keep their numbers here: two stools make two different plans, and two
            // constellations with the same name in the sky would be impossible to tell apart.
            let name = "Up \((routeNames.first ?? "the furniture").lowercased())"
                + (hazardNames.count == 1 ? " to \(hazardNames[0].lowercased())" : "")
            let stars = route + hazards
            return Constellation(
                id: "suggested:" + route.joined(separator: ">"),
                name: name,
                starIDs: stars,
                relationIDs: chains.flatMap { $0.relations.map(\.id) },
                fixPlan: plan(name: name, starIDs: stars, analysis: analysis, chain: first),
                status: .open,
                origin: .engine)
        }
    }

    /// The whole checklist as Markdown, for export (CLAUDE.md §7a.7).
    static func markdown(
        roomName: String, analysis: SafetyAnalysis, state: CraftState
    ) -> String {
        var md = "# \(roomName) — flags to check\n\n"
        md += "> \(disclaimer) proof flags what its geometry and concept list can see. It cannot see whether furniture is anchored or cabinets are latched, and small objects may be missing.\n\n"
        md += "Stage: \(analysis.parameters.stage.title). "
        let done = analysis.flags.filter { state.doneFlagIDs.contains($0.id) }.count
        md += "\(done) of \(analysis.flags.count) flags marked done.\n\n"

        if !state.constellations.isEmpty {
            md += "## Fix plans\n\n"
            for c in state.constellations {
                md += "### \(c.status == .done ? "[x]" : "[ ]") \(c.name)\n\n\(c.fixPlan)\n\n"
            }
        }
        if !analysis.chains.isEmpty {
            md += "## Climbing paths\n\n"
            for chain in analysis.chains { md += "- \(chain.why)\n" }
            md += "\n"
        }
        md += "## All flags\n\n"
        for kind in HazardKind.allCases {
            let flags = analysis.flags.filter { $0.kind == kind }
            guard !flags.isEmpty else { continue }
            md += "### \(kind.title)\n\n"
            for flag in flags {
                let box = state.doneFlagIDs.contains(flag.id) ? "[x]" : "[ ]"
                md += "- \(box) **\(flag.label)** — \(flag.detail)\(flag.isHeuristic ? " _(heuristic)_" : "") Consider: \(flag.fixTypes.joined(separator: "; ")).\n"
            }
            md += "\n"
        }
        md += "## Parameters\n\n"
        for p in analysis.parameters.all {
            md += "- \(p.title): \(p.formatted)\(p.provenance.isAssumption ? " — assumption" : "")\n"
        }
        return md
    }
}

/// Plain names for sentences: "Counter stool 1" → "counter stool".
enum PlainNames {
    static func plain(_ label: String) -> String {
        label.replacingOccurrences(of: #" \d+$"#, with: "", options: .regularExpression).lowercased()
    }
}
