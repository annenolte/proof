//
//  OnboardingCarouselView.swift
//  proof — Features / Onboarding — S-02
//
//  The three pages that have to sell the idea: *a room becomes stars* → *see the
//  path up* → *craft the fix plan*.
//
//  Layout is Tremor's, unchanged: the top ~35 % is type only on the flat `ink`
//  field, the bottom ~65 % is one hero artifact bleeding off the bottom edge, and
//  the page control plus the single CTA float over the artifact on a gradient of
//  the same ink.
//
//  The third page's card is not a mock-up. It runs the real safety engine over the
//  bundled kitchen at the walking stage and prints the first chain it finds — the
//  hazard, the measured route, and the generic fixes for it. If the app claims to
//  find paths a photo cannot, the first screen that says so should be telling the
//  truth.
//

import Observation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - The real chain behind page 3

/// Runs the engine once so the third onboarding page can show a real result.
/// Never touches the caregiver's own edits.
@MainActor
@Observable
final class OnboardingVerdict {

    struct Result: Equatable {
        var hazardName: String
        var kind: HazardKind
        /// The measured route, one step per line.
        var route: [String]
        var fixTitle: String
        var fixSummary: String
    }

    enum Phase: Equatable {
        case idle
        case computing
        case ready(Result)
        /// The engine found no chain. The card still renders — it just makes the
        /// qualitative claim instead of the measured one.
        case unavailable
    }

    private(set) var phase: Phase = .idle

    static let stage: AgeStage = .walking

    func computeIfNeeded() {
        guard phase == .idle else { return }
        phase = .computing
        guard let package = KitchenScene.bundled() else {
            phase = .unavailable
            return
        }
        let analysis = SafetyEngine.analyze(package.objects, parameters: .forStage(Self.stage))
        // The glass on the breakfast bar is the clearest example; any chain is a real one.
        guard let chain = analysis.chains.first(where: { $0.hazardID.hasPrefix("island.wineGlass") })
                ?? analysis.chains.first,
              let hazard = analysis.object(chain.hazardID),
              let kind = hazard.hazards.first else {
            phase = .unavailable
            return
        }
        var route = ["Floor"]
        for relation in chain.relations {
            let name = analysis.object(relation.toID)?.label ?? relation.toID
            if relation.kind == .climbStep {
                route.append(String(format: "%@ · step %.2f m", name, relation.rise ?? 0))
            } else {
                route.append(String(format: "%@ · %.2f m above, in reach", name, relation.rise ?? 0))
            }
        }
        phase = .ready(Result(
            hazardName: hazard.label,
            kind: hazard.hazards.contains(.breakable) ? .breakable : kind,
            route: route,
            fixTitle: HazardKind.falls.fixTypes[0],
            fixSummary: "or: " + (hazard.hazards.contains(.breakable) ? HazardKind.breakable : kind).fixTypes[0].lowercased()))
    }
}

// MARK: - S-02

struct OnboardingCarouselView: View {

    @Environment(\.tremor) private var tremor
    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var page: OnboardingPage = OnboardingCarouselView.launchPage

    /// `-proofOnboardingPage 2` opens on a given page. Debug only, for screenshots.
    private static var launchPage: OnboardingPage {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let i = arguments.firstIndex(of: "-proofOnboardingPage"), i + 1 < arguments.count,
           let n = Int(arguments[i + 1]), let page = OnboardingPage(rawValue: n) {
            return page
        }
        #endif
        return .scan
    }
    @State private var dragOffset: CGFloat = 0
    @State private var verdict = OnboardingVerdict()

    var body: some View {
        ZStack {
            TremorColor.ink.ignoresSafeArea()

            pager
                .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                footer
            }
        }
        .background(TremorColor.ink)
        .task { verdict.computeIfNeeded() }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Spacer(minLength: 0)
            InkTextButton(
                title: "Skip",
                hint: "Skips the tour and goes to sign in"
            ) {
                finish()
            }
            .opacity(page.isLast ? 0 : 1)
            .allowsHitTesting(!page.isLast)
            .accessibilityHidden(page.isLast)
        }
        .padding(.horizontal, TremorSpacing.md)
        .frame(height: TremorSize.topBar)
        .animation(TremorMotion.resolved(TremorMotion.dismiss, reduceMotion: reduceMotion),
                   value: page)
    }

    // MARK: Pager

    private var pager: some View {
        GeometryReader { geometry in
            let width = geometry.size.width

            Group {
                if reduceMotion {
                    // Reduce Motion removes the translation, not the paging: the
                    // swipe still works, it just crossfades (SPEC §1.5).
                    pageBody(page, in: geometry.size)
                        .frame(width: width)
                        .transition(.opacity)
                        .id(page)
                } else {
                    HStack(spacing: 0) {
                        ForEach(OnboardingPage.allCases) { candidate in
                            pageBody(candidate, in: geometry.size)
                                .frame(width: width)
                                .accessibilityHidden(candidate != page)
                        }
                    }
                    .offset(x: -CGFloat(page.rawValue) * width + dragOffset)
                }
            }
            .contentShape(Rectangle())
            .gesture(pageDrag(width: width))
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(page.positionDescription)
        .accessibilityScrollAction { edge in
            switch edge {
            case .leading: if let previous = page.previous { move(to: previous) }
            case .trailing: if let next = page.next { move(to: next) }
            default: break
            }
        }
    }

    private func pageDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !reduceMotion else { return }
                let raw = value.translation.width
                // Rubber-band past the first and last page rather than allowing
                // the stack to be dragged into empty space.
                let overshoots = (raw > 0 && page.previous == nil) || (raw < 0 && page.next == nil)
                dragOffset = overshoots ? raw * 0.28 : raw
            }
            .onEnded { value in
                let threshold = width * OnboardingMetric.pageTurnThreshold
                if value.translation.width < -threshold, let next = page.next {
                    move(to: next)
                } else if value.translation.width > threshold, let previous = page.previous {
                    move(to: previous)
                } else {
                    withAnimation(TremorMotion.resolved(TremorMotion.change, reduceMotion: reduceMotion)) {
                        dragOffset = 0
                    }
                }
            }
    }

    @ViewBuilder
    private func pageBody(_ candidate: OnboardingPage, in size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: TremorSpacing.sm) {
                Text(candidate.headline)
                    .tremorType(.displayL)
                    .foregroundStyle(TremorColor.primarySoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text(candidate.message)
                    .tremorType(.body)
                    .foregroundStyle(TremorColor.inkInverse.opacity(0.76))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, TremorSpacing.pageInset)
            .padding(.top, TremorSpacing.md)

            // The hero is the only greedy element, so the type block keeps its
            // intrinsic height at the top and the artifact takes everything
            // that is left and bleeds off the bottom edge.
            hero(for: candidate)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, TremorSpacing.lg)
        }
        .padding(.top, TremorSize.topBar)
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    @ViewBuilder
    private func hero(for candidate: OnboardingPage) -> some View {
        let isActive = candidate == page

        switch candidate {
        case .scan:
            LoopingIllustration(duration: candidate.heroDuration,
                                restPhase: candidate.heroRestPhase,
                                isActive: isActive) { phase in
                RoomAssemblyHero(phase: phase)
            }
            .frame(minHeight: OnboardingMetric.heroMinimumHeight)
            .accessibilityElement()
            .accessibilityLabel(candidate.heroDescription)

        case .shake:
            LoopingIllustration(duration: candidate.heroDuration,
                                restPhase: candidate.heroRestPhase,
                                isActive: isActive) { phase in
                ChainHero(phase: phase)
            }
            .frame(minHeight: OnboardingMetric.heroMinimumHeight)
            .accessibilityElement()
            .accessibilityLabel(candidate.heroDescription)

        case .fix:
            VStack(spacing: TremorSpacing.md) {
                Spacer(minLength: 0)

                LoopingIllustration(duration: candidate.heroDuration,
                                    restPhase: candidate.heroRestPhase,
                                    isActive: isActive) { phase in
                    AnchorBracketHero(phase: phase)
                }
                .frame(minHeight: OnboardingMetric.diagramMinimumHeight,
                       maxHeight: OnboardingMetric.diagramMaximumHeight)
                .accessibilityElement()
                .accessibilityLabel(candidate.heroDescription)

                OnboardingVerdictCard(phase: verdict.phase)
                    .padding(.horizontal, TremorSpacing.pageInset)
            }
            // More than the footer's own height: the scrim starts a further
            // 64 pt above it, and a card whose bottom third fades into the ink
            // reads as a rendering fault rather than as depth.
            .padding(.bottom, OnboardingMetric.cardBottomReserve)
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: TremorSpacing.lg) {
            OnboardingPageDots(count: OnboardingPage.allCases.count, index: page.rawValue)

            TremorButton(page.ctaTitle, variant: .accent, hint: page.ctaHint) {
                if let next = page.next {
                    move(to: next)
                } else {
                    finish()
                }
            }
            .padding(.horizontal, TremorSpacing.pageInset)
        }
        .padding(.top, TremorSpacing.xxl)
        .padding(.bottom, TremorSpacing.ctaBottomInset)
        .background {
            // The hero bleeds up behind the CTA, so the scrim has to start well
            // above the footer and be opaque by the time it reaches the dots.
            // A plain two-stop fade leaves the page control sitting on top of a
            // piece of furniture.
            LinearGradient(
                stops: [
                    .init(color: TremorColor.ink.opacity(0), location: 0),
                    .init(color: TremorColor.ink.opacity(0.72), location: 0.42),
                    .init(color: TremorColor.ink, location: 0.78),
                ],
                startPoint: .top,
                endPoint: .bottom)
            .padding(.top, -TremorSpacing.hero)
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        }
    }

    // MARK: Behaviour

    private func move(to newPage: OnboardingPage) {
        guard newPage != page else { return }
        TremorHaptic.selection.play()
        withAnimation(TremorMotion.resolved(TremorMotion.change, reduceMotion: reduceMotion)) {
            page = newPage
            dragOffset = 0
        }
        #if canImport(UIKit)
        UIAccessibility.post(notification: .pageScrolled, argument: newPage.positionDescription)
        #endif
    }

    /// The only exit. Recording that onboarding is done is what lets the launch
    /// gate move on; the gate itself decides where to (SPEC §1.3 — sign in next).
    private func finish() {
        tremor.settings.hasCompletedOnboarding = true
        router.advanceLaunch(with: tremor)
    }
}

// MARK: - The verdict card

/// The concrete payoff on page 3: one real object, one real band, one real
/// sentence, one real fix.
struct OnboardingVerdictCard: View {

    let phase: OnboardingVerdict.Phase

    var body: some View {
        TremorCard(padding: TremorSpacing.md, shadow: .lifted) {
            VStack(alignment: .leading, spacing: TremorSpacing.sm) {
                switch phase {
                case .idle, .computing:
                    placeholder
                case .ready(let result):
                    ready(result)
                case .unavailable:
                    unavailable
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: States

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.sm) {
            HStack(spacing: TremorSpacing.sm) {
                Text("Measuring…")
                    .tremorType(.headline)
                    .foregroundStyle(TremorColor.inkSecondary)
                Spacer(minLength: 0)
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(TremorColor.primary)
            }
            Text("proof is running its engine on a sample kitchen right now, so what you see next is a real result.")
                .tremorType(.footnote)
                .foregroundStyle(TremorColor.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityLabel("Working out an example climbing path")
    }

    private func ready(_ result: OnboardingVerdict.Result) -> some View {
        VStack(alignment: .leading, spacing: TremorSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: TremorSpacing.xs) {
                Image(systemName: result.kind.symbol)
                    .foregroundStyle(TremorColor.primary)
                Text(result.hazardName)
                    .tremorType(.headline)
                    .foregroundStyle(TremorColor.ink)
                    .lineLimit(1)
                Spacer(minLength: TremorSpacing.xs)
                Text("Reachable by climbing")
                    .tremorType(.caption)
                    .foregroundStyle(TremorColor.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(TremorColor.accent))
            }

            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(result.route.enumerated()), id: \.offset) { index, step in
                    HStack(spacing: TremorSpacing.xs) {
                        Circle()
                            .fill(index == result.route.count - 1 ? TremorColor.accent : TremorColor.primarySoft)
                            .overlay(Circle().stroke(TremorColor.ink.opacity(0.5), lineWidth: 0.75))
                            .frame(width: 8, height: 8)
                        Text(step)
                            .tremorType(.footnote, numeric: true)
                            .foregroundStyle(TremorColor.inkSecondary)
                            .lineLimit(1)
                    }
                }
            }

            Rectangle()
                .fill(TremorColor.divider)
                .frame(height: TremorSize.hairline)

            HStack(spacing: TremorSpacing.sm) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: TremorControlMetrics.glyphSmall, weight: .semibold))
                    .foregroundStyle(TremorColor.primary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: TremorSpacing.hair) {
                    Text(result.fixTitle)
                        .tremorType(.subheadline)
                        .foregroundStyle(TremorColor.ink)
                        .lineLimit(2)
                    Text(result.fixSummary)
                        .tremorType(.caption)
                        .foregroundStyle(TremorColor.inkTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityLabel(
            "\(result.hazardName), reachable by climbing. Route: \(result.route.joined(separator: ", ")). "
            + "Consider: \(result.fixTitle), \(result.fixSummary).")
    }

    private var unavailable: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.xs) {
            Text("A stool beside a counter")
                .tremorType(.headline)
                .foregroundStyle(TremorColor.ink)
            Text("One photo shows a stool. proof measures whether it is a step up to something out of reach. You'll see your own climbing paths after your first walkthrough.")
                .tremorType(.footnote)
                .foregroundStyle(TremorColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Previews

#Preview("S-02 carousel") {
    OnboardingCarouselView()
        .environment(\.tremor, .makePreview(onboarded: false, signedIn: false, seedsFixtures: false))
        .environment(Router())
}

/// Reduce Motion cannot be injected through the environment (the key is
/// read-only), so this previews what it actually produces: the settled rest
/// frame of every hero, which is what the setting freezes each page on.
#Preview("S-02 reduce-motion rest frames") {
    ZStack {
        TremorColor.ink.ignoresSafeArea()
        VStack(spacing: 0) {
            RoomAssemblyHero(phase: OnboardingPage.scan.heroRestPhase)
            ChainHero(phase: OnboardingPage.shake.heroRestPhase)
            AnchorBracketHero(phase: OnboardingPage.fix.heroRestPhase)
        }
    }
}

#Preview("S-02 large text") {
    OnboardingCarouselView()
        .environment(\.tremor, .makePreview(onboarded: false, signedIn: false, seedsFixtures: false))
        .environment(Router())
        .environment(\.dynamicTypeSize, .accessibility2)
}

#Preview("Verdict card — states") {
    VStack(spacing: TremorSpacing.md) {
        OnboardingVerdictCard(phase: .computing)
        OnboardingVerdictCard(phase: .ready(.init(
            hazardName: "Wine glass 1",
            kind: .breakable,
            route: ["Floor", "Counter stool 1 · step 0.20 m", "Wine glass 1 · 0.72 m above, in reach"],
            fixTitle: "Move climbable furniture away",
            fixSummary: "or: move breakables above reach")))
        OnboardingVerdictCard(phase: .unavailable)
    }
    .padding(TremorSpacing.md)
    .frame(maxHeight: .infinity)
    .background(TremorColor.ink)
}
