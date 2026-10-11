//
//  ProofMethodView.swift
//  proof — How proof works
//
//  The answers to the questions a judge or a careful parent will ask (CLAUDE.md §12),
//  written down once so the app and the pitch say the same thing.
//

import SwiftUI

struct ProofMethodView: View {

    @Environment(AppState.self) private var appState

    private var sky: ConstellationModel { appState.addRoomFlow.sky }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TremorSpacing.xl) {
                VStack(alignment: .leading, spacing: TremorSpacing.sm) {
                    Text("How proof works")
                        .tremorType(.displayM)
                        .foregroundStyle(TremorColor.ink)
                    Text("proof rebuilds a room in 3D, flags what a small child could reach, and lights up the climbing paths — a stool, then a counter, then a glass — that a single photo can't show.")
                        .tremorType(.body)
                        .foregroundStyle(TremorColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                section("1. From video to flags", symbol: "video", lines: [
                    "A walkthrough video is turned into camera poses, then a 3D Gaussian splat of the room.",
                    "SAM 3 is prompted with noun phrases — “stove”, “bar stool”, “chair” — and its masks are lifted into 3D boxes. Each box is a flag.",
                    "Every object's concept maps to a category through a list a person approves, not a model's guess."
                ])

                section("2. The engine", symbol: "point.3.connected.trianglepath.dotted", lines: [
                    "Reach: a hazard is within reach from a surface if its lowest point is close enough above it and close enough across.",
                    "Climb: a child can step from one surface to another if the rise and the gap are small enough for their stage.",
                    "Climbing paths: the fewest steps from the floor to a surface where something out of reach comes within reach.",
                    "All of it is deterministic geometry with unit tests. The same room gives the same paths every time."
                ])

                section("3. Where the language model fits", symbol: "text.bubble", lines: [
                    "It turns your concern into the noun phrases SAM 3 looks for, shown as a step you can read.",
                    "It may draft fix-plan wording from the measured data. In this build the drafts come from a fixed template, so nothing depends on a network.",
                    "It never decides what is connected to what."
                ])

                section("4. What proof can't see", symbol: "eye.slash", lines: ChecklistView.limitations)

                VStack(alignment: .leading, spacing: TremorSpacing.xs) {
                    TremorSectionHeader("5. Parameters", subtitle: "\(sky.stage.title) stage — change it in the room")
                    ForEach(sky.analysis.parameters.all) { p in
                        HStack {
                            Text(p.title).tremorType(.footnote).foregroundStyle(TremorColor.ink)
                            Spacer()
                            Text(p.formatted).tremorType(.footnote, numeric: true)
                                .foregroundStyle(TremorColor.inkSecondary)
                            if p.provenance.isAssumption { Badge("Assumption") }
                        }
                    }
                    Text("None of these has a cited source yet. They are placeholders, labelled wherever they are used, until docs/HAZARDS.md records one.")
                        .tremorType(.caption).foregroundStyle(TremorColor.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }


                TremorBanner(
                    "Flags to check, not a safety guarantee.",
                    message: "proof never calls a room safe and never gives it a score.",
                    kind: .highlight)
            }
            .padding(.horizontal, TremorSpacing.pageInset)
            .padding(.vertical, TremorSpacing.lg)
        }
        .background(TremorColor.canvas.ignoresSafeArea())
    }

    private func section(_ title: String, symbol: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: TremorSpacing.sm) {
            Label(title, systemImage: symbol)
                .tremorType(.headline)
                .foregroundStyle(TremorColor.ink)
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: TremorSpacing.xs) {
                    Circle().fill(TremorColor.primary).frame(width: 5, height: 5)
                    Text(line)
                        .tremorType(.footnote)
                        .foregroundStyle(TremorColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
