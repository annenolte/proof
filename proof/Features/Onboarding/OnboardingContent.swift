//
//  OnboardingContent.swift
//  proof — Features / Onboarding
//
//  The vocabulary the first-run screens share: the three carousel pages as a
//  value, the animated-width page control, the text button that survives sitting
//  on the ink field, and the wrapper that drives a looping illustration.
//
//  Everything here is deliberately data rather than view code, so the copy and
//  the page graph are testable without rendering anything (`OnboardingScreenTests`).
//

import SwiftUI

// MARK: - The three pages

/// SPEC §1.4 S-02. Three pages, in this order, and the order is the argument:
/// *a room becomes stars* → *see the path up* → *craft the fix plan*.
///
/// The headlines carry a hard line break on purpose. They are set in the display
/// face at `displayL` and the break is what gives the Zip onboarding its shape —
/// a short, punchy two-line stack against a flat brand field.
enum OnboardingPage: Int, CaseIterable, Identifiable, Hashable, Sendable {
    case scan
    case shake
    case fix

    var id: Int { rawValue }

    var headline: String {
        switch self {
        case .scan: return "Your kitchen.\nIn stars."
        case .shake: return "See the path\nup."
        case .fix: return "Craft the\nfix plan."
        }
    }

    var message: String {
        switch self {
        case .scan:
            return "Film a slow lap of a room. proof rebuilds it in 3D with Gaussian splatting, finds the objects in it with SAM 3, and marks each one — a star in your room's sky."
        case .shake:
            return "A photo can tell you a stove is hot. It can't tell you a stool, a counter and a glass form a path. proof finds the climbing paths to what's out of reach."
        case .fix:
            return "You decide what counts and group flags into fix plans you can tick off. Flags to check — never a safety guarantee."
        }
    }

    /// What VoiceOver hears in place of the animation. The illustrations carry
    /// meaning — they are the argument for the product — so they are described,
    /// not hidden.
    var heroDescription: String {
        switch self {
        case .scan:
            return "An animation of a kitchen drawing itself in 3D — counter, island, stools and table — with a star appearing on each object."
        case .shake:
            return "An animation of a path lighting up from the floor, onto a stool's footrail, up to its seat, and across to a glass on the counter."
        case .fix:
            return "An animation of an anchor bracket and two screws fitting a shelf to the wall."
        }
    }

    /// Loop length in seconds, from the SPEC S-02 table.
    var heroDuration: Double {
        switch self {
        case .scan: return 4.4
        case .shake: return 4.2
        case .fix: return 3.4
        }
    }

    /// The single frame the illustration freezes on when Reduce Motion is on or
    /// the page is off-screen.
    ///
    /// Each is chosen to be the *finished* state — an assembled room, a fallen
    /// bookcase, a fitted bracket — so a user who never sees the motion still
    /// sees the point being made.
    var heroRestPhase: Double {
        switch self {
        case .scan: return 0.90
        case .shake: return 0.80
        case .fix: return 0.92
        }
    }

    var ctaTitle: String { isLast ? "Get started" : "Next" }

    var ctaHint: String {
        isLast ? "Goes to sign in. You can carry on without an account." : "Shows the next page"
    }

    var isLast: Bool { self == OnboardingPage.allCases.last }

    var next: OnboardingPage? { OnboardingPage(rawValue: rawValue + 1) }
    var previous: OnboardingPage? { OnboardingPage(rawValue: rawValue - 1) }

    /// "Page 2 of 3", for the pager's accessibility value.
    var positionDescription: String {
        "Page \(rawValue + 1) of \(OnboardingPage.allCases.count)"
    }
}

// MARK: - Metrics

/// Numbers that belong to the first-run screens specifically. Everything that
/// is a *system* value — spacing, radii, button heights — comes from the design
/// system; these are the two or three proportions the onboarding composition
/// needs and the design system has no opinion about.
enum OnboardingMetric {
    /// Zip's page control: 8 pt dots, the active one animating its width to 24.
    static let dot: CGFloat = TremorSpacing.xs
    static let activeDot: CGFloat = TremorSpacing.xl

    /// SPEC S-05: an 88 pt icon well.
    static let iconWell: CGFloat = 88

    /// Fraction of the screen width a swipe must cover to turn the page.
    static let pageTurnThreshold: CGFloat = 0.22

    /// Floor for a hero's height, so the illustration never collapses to a
    /// sliver on a small phone at an accessibility text size.
    static let heroMinimumHeight: CGFloat = 200

    /// Same, for the shorter diagram on page 3, which shares its space with the
    /// verdict card and must not crowd it out.
    static let diagramMinimumHeight: CGFloat = 110
    static let diagramMaximumHeight: CGFloat = 260

    /// Vertical room reserved at the foot of every page for the dots and the
    /// CTA, so nothing meaningful is ever printed underneath them.
    /// = 8 (dots) + 20 (gap) + 56 (CTA) + 16 (inset) + one 32 pt breath.
    static let footerReserve: CGFloat = 132

    /// What a page must clear when it ends in something that has to stay
    /// *legible* rather than merely visible — page 3's verdict card. The scrim
    /// behind the footer starts 64 pt above it, so anything readable has to end
    /// above that too.
    static let cardBottomReserve: CGFloat = footerReserve + TremorSpacing.hero
}

// MARK: - Loop clock

/// Turns wall-clock time into a 0…1 loop phase.
///
/// Derived from the clock rather than accumulated, so a dropped frame shifts the
/// loop by nothing instead of by one frame forever. Pulled out of the view so
/// the wrap-around is unit-testable.
///
/// `origin` is what makes the *first* loop worth watching. Page 1's whole
/// argument is a room drawing itself out of nothing, and page 2's is a bookcase
/// going over — neither means anything if you arrive halfway through. Measuring
/// from the moment the page appeared rather than from the absolute clock means
/// every user sees frame zero first. (Without it the entry phase is uniform on
/// 0…1: most arrivals land mid-assembly, and roughly one in twenty lands inside
/// the loop veil and shows an empty screen under the headline.)
enum LoopClock {
    static func phase(at date: Date, duration: Double, since origin: Date? = nil) -> Double {
        guard duration > 0 else { return 0 }
        let seconds = date.timeIntervalSinceReferenceDate
            - (origin?.timeIntervalSinceReferenceDate ?? 0)
        let remainder = seconds.truncatingRemainder(dividingBy: duration)
        let positive = remainder < 0 ? remainder + duration : remainder
        return positive / duration
    }
}

// MARK: - Page dots

/// Zip's animated-width page control: 8 pt dots, the active dot growing to
/// 24 pt over 250 ms **linear** (Zip does not ease colour or width changes).
///
/// Hidden from VoiceOver — the pager itself publishes "Page 2 of 3" as its
/// accessibility value, and a second announcement of the same fact is noise.
struct OnboardingPageDots: View {

    let count: Int
    let index: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: TremorSpacing.xs) {
            ForEach(0..<count, id: \.self) { position in
                Capsule(style: .continuous)
                    .fill(position == index
                          ? TremorColor.primarySoft
                          : TremorColor.primarySoft.opacity(0.28))
                    .frame(width: position == index ? OnboardingMetric.activeDot : OnboardingMetric.dot,
                           height: OnboardingMetric.dot)
            }
        }
        .animation(TremorMotion.resolved(TremorMotion.colorShift, reduceMotion: reduceMotion),
                   value: index)
        .accessibilityHidden(true)
    }
}

// MARK: - Text button on ink

/// A tertiary text button that reads correctly on the `ink` field.
///
/// `TremorButton(variant: .tertiary)` sets its own label colour to `primary`
/// (#6542BE), which is a 2.2:1 contrast on the ink background — fine on the warm
/// canvas it was designed for, unreadable here. The design system has no
/// on-dark button variant, so this composes the two tokens that do work:
/// `primarySoft` type on nothing, at the standard 44 pt tap target.
struct InkTextButton: View {

    let title: String
    var hint: String?
    var isProminent: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            TremorHaptic.light.play()
            action()
        } label: {
            Text(title)
                .tremorType(isProminent ? .bodyEmphasis : .subheadline)
                .foregroundStyle(TremorColor.primarySoft)
                .padding(.horizontal, TremorSpacing.sm)
                .frame(minHeight: TremorSize.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(hint ?? "")
    }
}

// MARK: - Looping illustration host

/// Drives a looping, phase-parameterised illustration.
///
/// Three properties make this safe to put on an onboarding carousel:
///
/// * It only ticks while `isActive` is true, so the two off-screen pages of a
///   three-page carousel cost nothing.
/// * Under `accessibilityReduceMotion` it never ticks at all; it renders the
///   page's `restPhase` — the *finished* frame — once. Reduce Motion removes the
///   movement, not the information.
/// * The phase is derived from the wall clock rather than accumulated, so a
///   dropped frame does not desynchronise the loop — but it is measured from the
///   moment the page became active, so the loop always *starts at frame zero*.
///   These illustrations are arguments, not decoration: the room has to be seen
///   assembling and the bookcase has to be seen going over.
struct LoopingIllustration<Content: View>: View {

    let duration: Double
    let restPhase: Double
    var isActive: Bool = true
    /// How far into the loop the clock starts, as a fraction.
    ///
    /// The loop veil fades the illustration in over the first few per cent of
    /// the phase so a restart is invisible. That makes phase 0 fully
    /// transparent — correct for a seam, disastrous for a *first* frame. Rather
    /// than weaken the veil, the clock simply begins just past it, so the very
    /// first frame a user sees is already opaque and no arrangement of dropped
    /// frames, throttled timelines or static renders can produce a blank hero.
    var leadIn: Double = 0.08
    @ViewBuilder let content: (Double) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// When this illustration last started running. Re-armed every time the page
    /// becomes active, so swiping back to page 1 replays the assembly rather
    /// than resuming it wherever the absolute clock happens to be.
    @State private var startedAt: Date?

    private var isAnimating: Bool { isActive && !reduceMotion }

    var body: some View {
        Group {
            if isAnimating, let startedAt {
                TimelineView(.animation) { context in
                    content(LoopClock.phase(
                        at: context.date, duration: duration, since: startedAt))
                }
            } else {
                // Until the clock has actually started — the very first frame,
                // a static `ImageRenderer` pass, a snapshot test — show the rest
                // frame rather than phase 0.
                //
                // Phase 0 is deliberately *invisible*: the loop veil fades in at
                // the head to hide the restart. So anything that renders this
                // view without a running animation clock gets a blank hero and
                // no error, which is precisely how an empty hole shipped on the
                // most important screen in the app. Never render phase 0.
                content(restPhase)
            }
        }
        .onAppear { if isAnimating { startedAt = clockOrigin() } }
        .onChange(of: isActive) { _, active in startedAt = active ? clockOrigin() : nil }
        .onChange(of: reduceMotion) { _, reduced in
            startedAt = reduced ? nil : (isActive ? clockOrigin() : nil)
        }
    }

    /// A start date backdated by the lead-in, so the first frame is already
    /// past the veil's fade.
    private func clockOrigin() -> Date {
        Date().addingTimeInterval(-duration * leadIn)
    }
}

// MARK: - Preview host

/// Wires the three environment values a first-run screen reads, against the
/// fixture-backed preview environment.
///
/// The launch-phase screens (S-02, S-03, S-05) are shown *outside* the tab
/// shell, so `RootPreviewHost` — which renders the whole root — is the wrong
/// tool for previewing them in isolation. This is the smaller one.
@MainActor
struct OnboardingPreviewHost<Content: View>: View {

    private let env: TremorEnvironment
    @State private var router: Router
    @State private var appState: AppState
    private let content: Content

    init(
        env: TremorEnvironment,
        path: [Route] = [],
        @ViewBuilder content: () -> Content
    ) {
        self.env = env
        let router = Router()
        router.replacePath(with: path)
        _router = State(initialValue: router)
        _appState = State(initialValue: AppState(env: env))
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.tremor, env)
            .environment(router)
            .environment(appState)
    }
}

// MARK: - Easing

/// The easing the illustrations share.
///
/// These are plain functions rather than `Animation` values because the
/// illustrations are drawn in a `Canvas` from a single phase number — there is
/// no view property to animate, so there is nothing for SwiftUI's curves to
/// apply to.
enum Ease {

    /// 0 before `start`, 1 after `end`, linear in between.
    static func ramp(_ t: Double, _ start: Double, _ end: Double) -> Double {
        guard end > start else { return t >= end ? 1 : 0 }
        return min(1, max(0, (t - start) / (end - start)))
    }

    /// Smooth Hermite step — the ramp with its corners taken off.
    static func smooth(_ t: Double, _ start: Double, _ end: Double) -> Double {
        let u = ramp(t, start, end)
        return u * u * (3 - 2 * u)
    }

    /// Lyft's `enter` feel: instant start, hard deceleration.
    static func out(_ u: Double) -> Double {
        let c = min(1, max(0, u))
        return 1 - pow(1 - c, 3)
    }

    /// Accelerating, for anything falling. A toppling body's angle grows faster
    /// than linearly, so a linear rotation reads as a hinge rather than a fall.
    static func fall(_ u: Double) -> Double {
        let c = min(1, max(0, u))
        return pow(c, 1.8)
    }

    /// The fade that hides a loop's restart: in at the head, out at the tail.
    static func loopVeil(_ t: Double, headEnd: Double = 0.04, tailStart: Double = 0.93) -> Double {
        min(smooth(t, 0, headEnd), 1 - smooth(t, tailStart, 1))
    }
}
