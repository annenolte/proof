//
//  ProofRoomsView.swift
//  proof — the Rooms tab
//
//  Tremor's library, cut down to what proof has: one prepared kitchen and the caregiver's
//  progress on it. Same chrome — the collapsing title, the ink hero card with its round
//  arrow, the lavender summary card, the rich room row — so the app reads as one system.
//
//  The kitchen's state lives in `AppState.addRoomFlow`, so this tab and the Add Room tab
//  are always looking at the same sky.
//

import SwiftUI

struct ProofRoomsView: View {

    @Environment(Router.self) private var router
    @Environment(AppState.self) private var appState

    private var flow: AddRoomFlowModel { appState.addRoomFlow }
    private var sky: ConstellationModel { flow.sky }

    var body: some View {
        VStack(spacing: 0) {
            TremorNavBar(title: "Rooms", collapseProgress: 0)

            ScrollView {
                VStack(alignment: .leading, spacing: TremorSpacing.md) {
                    heroCard
                    summaryCard

                    TremorSectionHeader("Your rooms")
                        .padding(.top, TremorSpacing.sm)

                    kitchenCard

                    Text("proof flags things to check. It never says a room is safe.")
                        .tremorType(.caption)
                        .foregroundStyle(TremorColor.inkTertiary)
                        .padding(.top, TremorSpacing.xs)

                    TremorButton("How proof works", variant: .tertiary, size: .medium,
                                 leadingIcon: "function") {
                        router.openMethod()
                    }
                }
                .padding(.horizontal, TremorSpacing.pageInset)
                .padding(.bottom, TremorSpacing.xxl)
            }
        }
        .background(TremorColor.canvas.ignoresSafeArea())
    }

    // MARK: Actions

    /// Straight to the concern step with the room already named.
    private func startKitchen() {
        if flow.step == .naming {
            flow.roomName = "Kitchen"
            flow.chooseConcern()
        }
        router.select(.addRoom)
    }

    private func openKitchen() {
        if flow.demo.isSceneReady {
            flow.reopenRoom()
            router.select(.addRoom)
        } else {
            startKitchen()
        }
    }

    // MARK: Hero

    private var heroCard: some View {
        Button(action: startKitchen) {
            HStack(alignment: .center, spacing: TremorSpacing.md) {
                VStack(alignment: .leading, spacing: TremorSpacing.xxs) {
                    Text("Check a room")
                        .tremorType(.title2)
                        .foregroundStyle(TremorColor.primarySoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Film a ten-second walkthrough and see it rebuilt in 3D")
                        .tremorType(.callout)
                        .foregroundStyle(TremorColor.inkInverse.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Image(systemName: "arrow.right")
                    .font(.system(size: TremorControlMetrics.glyphMedium, weight: .semibold))
                    .foregroundStyle(TremorColor.onPrimary)
                    .frame(width: TremorSize.minimumTapTarget, height: TremorSize.minimumTapTarget)
                    .background(TremorColor.primary, in: Circle())
            }
            .padding(TremorSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TremorColor.ink, in: RoundedRectangle(cornerRadius: TremorRadius.card, style: .continuous))
            .tremorShadow(.raised)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Asks what you are getting ready for, then opens the camera")
    }

    // MARK: Summary

    private var summaryCard: some View {
        let plans = sky.constellations.count
        let started = sky.doneCount > 0 || plans > 0
        return TremorCard(padding: TremorSpacing.md, fill: TremorColor.primarySoft, shadow: nil) {
            HStack(alignment: .top, spacing: TremorSpacing.sm) {
                Image(systemName: started ? "checklist" : "sparkles")
                    .font(.system(size: TremorControlMetrics.glyphMedium, weight: .medium))
                    .foregroundStyle(TremorColor.primary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: TremorSpacing.hair) {
                    Text(started ? sky.progressText : "Nothing checked yet")
                        .tremorType(.bodyEmphasis)
                        .foregroundStyle(TremorColor.ink)
                    Text(started
                         ? "\(plans) fix plan\(plans == 1 ? "" : "s") · \(sky.stage.title) stage. Progress, not a score."
                         : "Open the kitchen to see how a small child could climb to what's out of reach.")
                        .tremorType(.footnote)
                        .foregroundStyle(TremorColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: The kitchen

    private var kitchenCard: some View {
        return TremorCard.tappable(
            padding: TremorSpacing.sm,
            accessibilityHint: flow.demo.isSceneReady ? "Opens the kitchen in 3D" : "Starts a walkthrough"
        ) {
            openKitchen()
        } content: {
            HStack(spacing: TremorSpacing.md) {
                RoomIsometricGlyph(band: nil, objectCount: 9, seed: 0x4B1C)
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: TremorRadius.thumbnail, style: .continuous))
                VStack(alignment: .leading, spacing: TremorSpacing.xxs) {
                    Text("Kitchen")
                        .tremorType(.headline)
                        .foregroundStyle(TremorColor.ink)
                    Text("\(sky.analysis.flags.count) flags · \(sky.analysis.chains.count) climbing paths · \(sky.stage.title.lowercased())")
                        .tremorType(.footnote)
                        .foregroundStyle(TremorColor.inkTertiary)
                    HStack(spacing: 4) {
                        Image(systemName: sky.doneCount > 0 ? "checkmark.circle" : "circle.dashed")
                            .font(.system(size: 10, weight: .semibold))
                        Text("\(sky.doneCount) of \(sky.analysis.flags.count) flags done")
                            .tremorType(.caption, numeric: true)
                    }
                    .foregroundStyle(TremorColor.inkSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(TremorColor.surfaceSunken))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TremorColor.inkTertiary)
            }
        }
    }
}
