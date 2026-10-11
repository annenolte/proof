//
//  AddRoomConcernView.swift
//  proof — Add Room, step 2
//
//  The caregiver states the concern; the translator turns it into the noun phrases SAM 3
//  is prompted with (CLAUDE.md §9 Stage 8). Shown as a visible step, so nobody has to take
//  on trust what the segmentation was asked to look for.
//
//  For the demo the translation is the cached result that matches the concept catalog —
//  it cannot fail on a network, and it says so in one quiet line.
//

import SwiftUI

struct AddRoomConcernView: View {

    let roomName: String
    @Binding var stage: AgeStage
    var onBack: () -> Void
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(TremorColor.ink)
                            .frame(width: TremorSize.minimumTapTarget, height: TremorSize.minimumTapTarget,
                                   alignment: .leading)
                    }
                    .accessibilityLabel("Back")

                    header
                        .padding(.top, TremorSpacing.xs)

                    VStack(spacing: TremorSpacing.xs) {
                        ForEach(AgeStage.allCases) { option in
                            stageCard(option)
                        }
                    }
                    .padding(.top, TremorSpacing.xl)

                    translator
                        .padding(.top, TremorSpacing.xxl)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, TremorSpacing.pageInset)
                .padding(.bottom, TremorSpacing.xl)
            }
            .scrollBounceBehavior(.basedOnSize)

            TremorButton(
                "Film the room",
                leadingIcon: "video",
                hint: "Opens the camera"
            ) { onContinue() }
            .padding(.horizontal, TremorSpacing.pageInset)
            .padding(.top, TremorSpacing.sm)
            .padding(.bottom, TremorSpacing.ctaBottomInset)
        }
        .tremorScreen(inset: 0)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.sm) {
            Text(roomName)
                .tremorType(.overline)
                .foregroundStyle(TremorColor.inkTertiary)

            Text("What are you\ngetting ready for?")
                .tremorType(.displayM)
                .foregroundStyle(TremorColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text("Reach and climbing change fast. proof checks the room against the stage you pick, and you can switch later.")
                .tremorType(.body)
                .foregroundStyle(TremorColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stageCard(_ option: AgeStage) -> some View {
        TremorCard.tappable(
            padding: TremorSpacing.md,
            isSelected: stage == option,
            accessibilityHint: "Checks the room for this stage"
        ) {
            stage = option
        } content: {
            HStack(spacing: TremorSpacing.md) {
                Image(systemName: option.symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(TremorColor.primary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(TremorColor.primarySoft))
                VStack(alignment: .leading, spacing: TremorSpacing.hair) {
                    Text(option.title)
                        .tremorType(.headline)
                        .foregroundStyle(TremorColor.ink)
                    Text(option.concern)
                        .tremorType(.footnote)
                        .foregroundStyle(TremorColor.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: stage == option ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(stage == option ? TremorColor.primary : TremorColor.strokeStrong)
            }
        }
    }

    private var translator: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.sm) {
            TremorSectionHeader("What SAM 3 will look for",
                                subtitle: "Your concern, turned into object prompts")

            Text("“\(stage.concern)”")
                .tremorType(.callout)
                .foregroundStyle(TremorColor.ink)
                .fixedSize(horizontal: false, vertical: true)

            NounPhraseCloud(phrases: ConceptCatalog.nounPhrases(for: stage))

            Label("Which objects connect is decided by geometry, not by the language model.",
                  systemImage: "info.circle")
                .tremorType(.caption)
                .foregroundStyle(TremorColor.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The translator's output as a wrap of quiet capsules. Read-only: these are prompts, not
/// filters the caregiver toggles.
struct NounPhraseCloud: View {
    let phrases: [String]
    var onDark = false

    var body: some View {
        FlowLayout(spacing: TremorSpacing.xs) {
            ForEach(phrases, id: \.self) { phrase in
                Text(phrase)
                    .tremorType(.caption)
                    .foregroundStyle(onDark ? TremorColor.inkInverse : TremorColor.primary)
                    .padding(.horizontal, TremorSpacing.sm)
                    .padding(.vertical, TremorSpacing.xxs + 1)
                    .background(Capsule().fill(onDark ? TremorColor.inkInverse.opacity(0.14) : TremorColor.primarySoft))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Prompts: " + phrases.joined(separator: ", "))
    }
}

/// Left-aligned wrapping layout.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += lineHeight + spacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: min(widest, width), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += lineHeight + spacing
                x = bounds.minX
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
