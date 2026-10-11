//
//  Components+Containers.swift
//  Tremor — Design System / Surfaces & Containers
//
//  The container family: everything that *holds* content, plus the feedback
//  surfaces (banner, toast, progress) that sit on top of it.
//
//  WHERE THE ANATOMY COMES FROM
//
//  Structure is Lyft's. Lyft's whole app is one composition — a warm off-white
//  field, generous white plates, and a single softly-glowing bottom sheet that
//  resizes between detents — so `TremorCard`, `TremorListRow`, `TremorSheet` and
//  `TremorNavBar` copy Lyft's measured geometry almost verbatim (design-lyft.md
//  §6.2–6.6): 56/72/88pt rows, a 16pt row inset, a 36 × 4pt grabber 8pt from the
//  sheet top, a 24pt header block, a pinned CTA dock whose top hairline appears
//  only once content scrolls under it, and a large title that collapses to an
//  inline one on scroll.
//
//  Confidence is Zip's. The aubergine ink, the lavender surface, the
//  purple-tinted shadow on every plate, and the willingness to let a display
//  numeral be enormous (design-zip.md §7.3, §8).
//
//  Three rules this file never breaks:
//
//   1. **No literals.** Every colour, size, radius, duration and type step comes
//      from `Theme.swift` / `Typography.swift` / `Layout.swift`. Values those
//      files do not name are *derived* from ones they do — see `Metric` below,
//      where each derivation cites the research line it implements.
//   2. **Colour is never the only carrier.** Every risk band, banner kind and
//      toast style ships a distinct SF Symbol *shape* and a spoken role word
//      ("Severe risk", "Warning") alongside its hue.
//   3. **One-line call sites.** Every initialiser gives every parameter a
//      sensible default, so the common case is a single line and the rare case
//      is still one initialiser rather than a builder. (Access level is
//      `internal`, matching `Theme.swift`/`Layout.swift`: Tremor is a single
//      app module, so `internal` *is* the shared surface — marking these
//      `public` would be illegal anyway, because a public signature cannot name
//      an internal token type.)
//   4. **Reduce Motion is honoured everywhere.** Every animation in this file
//      routes through `Motion.animation(_:reduceMotion:)`, which returns `nil`
//      when the user has asked for less motion, so the change lands instantly
//      rather than being animated at a shorter duration.
//
//  Nothing here reaches outside the design system: no networking, no models, no
//  singletons, no shared state. Data comes in through the initialiser, intent
//  goes out through closures.
//

import SwiftUI
import UIKit

// MARK: - Derived metrics
//
// Values the token files do not name, each derived from one that they do so the
// system stays single-sourced. The comment on each is the research line it
// implements.

private enum Metric {
    /// 24pt — Lyft list-row leading icon is 24 × 24 (design-lyft.md §6.3).
    static let icon = TremorSpacing.xl
    /// 16pt — Lyft chevron / trailing glyph is 16 × 16 (§6.3).
    static let glyph = TremorSpacing.md
    /// 40pt — Lyft row avatar / icon well (§6.3).
    static let well = TremorSpacing.xxxl
    /// 56pt — Lyft rich-row thumbnail, the same measure as a single-line row (§6.3).
    static let thumbnail = TremorSize.row
    /// 4pt — Lyft progress bar is 4pt tall, radius 2 (§6.9).
    static let barHeight = TremorSpacing.xxs
    /// 120pt — the scan-processing ring. Big enough to carry a display numeral
    /// inside it; sized off the rich row so it lines up with list rhythm.
    static let ring = TremorSize.rowRich + TremorSpacing.xxl
    /// 8pt — ring stroke. Lyft's own indeterminate work is a halo, not a hairline
    /// spinner, so the ring is drawn heavy enough to read as a solid object.
    static let ringStroke = TremorSpacing.xs
    /// 80pt — empty-state illustration well.
    static let illustration = TremorSpacing.hero + TremorSpacing.md
    /// 20pt — sheet gutter. Lyft `space-6`, "sheet horizontal padding on large
    /// sheets" (design-lyft.md §3).
    static let sheetGutter = TremorSpacing.lg
    /// 2pt — grabber corner radius (half its 4pt height), per Lyft §6.4.
    static let grabberRadius = TremorSize.grabberHeight / 2
}

// MARK: - Derived washes
//
// Lyft applies interaction state as an *overlay* on top of the base fill rather
// than by swapping colours (design-lyft.md §1.6 "Interaction states"), which is
// what lets one press treatment work on white, on lavender and on a tinted risk
// chip. Tremor re-tints those overlays to its own aubergine ink.

private enum Wash {
    /// Lyft pressed overlay on light surfaces: ink @ 10%.
    static let pressed = TremorColor.ink.opacity(0.10)
    /// Lyft pressed overlay on saturated fills: white @ 22%.
    static let pressedOnFill = TremorColor.surface.opacity(0.22)
    /// Lyft disabled treatment: a 62% white veil over the component, not a grey
    /// swap. "Worth copying" — design-lyft.md §1.6.
    static let disabledVeil = TremorColor.surface.opacity(0.62)
    /// Lyft grabber: ink @ 20% (§6.4).
    static let grabber = TremorColor.ink.opacity(0.20)
    /// Soft tint for semantic banner fills — the mark at low alpha, the same
    /// move Lyft uses for `surface-secondary`.
    static func tint(_ color: Color) -> Color { color.opacity(0.12) }
}

// MARK: - Motion helper

private enum Motion {
    /// The single gate for every animation in this file.
    ///
    /// `@Environment(\.accessibilityReduceMotion)` means *no* motion, not
    /// *faster* motion, so this returns `nil` — SwiftUI then applies the change
    /// instantly instead of interpolating it.
    static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }

    /// Repeating animations are suppressed entirely under Reduce Motion.
    static func loop(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

// MARK: - Haptics

private enum Haptics {
    /// Light impact on press. Lyft/Zip both pair the 0.97 press scale with a
    /// physical tick; without it a pill button on a flat canvas feels dead.
    static func press() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }

    /// Selection tick — segmented changes, row selection, toggles.
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}

// MARK: - Press style

/// The one press treatment used by every tappable container in this file:
/// Lyft's 0.97 scale over 100ms on the `change` curve, plus an ink wash clipped
/// to the component's own shape, plus a light haptic on touch-down.
private struct PressStyle: ButtonStyle {
    var shape: AnyShape = AnyShape(Rectangle())
    var wash: Color = Wash.pressed
    var scales: Bool = true
    var haptics: Bool = true

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        PressBody(configuration: configuration, shape: shape, wash: wash, scales: scales, haptics: haptics)
    }
}

/// The style's body lives outside `PressStyle` because a type nested inside a
/// `ButtonStyle` and named `Body` would be mistaken for its `associatedtype`.
private struct PressBody: View {
    let configuration: ButtonStyleConfiguration
    let shape: AnyShape
    let wash: Color
    let scales: Bool
    let haptics: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .overlay {
                shape.fill(wash).opacity(configuration.isPressed ? 1 : 0)
            }
            .clipShape(shape)
            .scaleEffect(scaleFactor)
            .overlay {
                // Lyft's disabled treatment: a white veil over the whole
                // component rather than a desaturated repaint.
                shape.fill(Wash.disabledVeil).opacity(isEnabled ? 0 : 1)
            }
            .animation(Motion.animation(configuration.isPressed ? TremorMotion.tap : TremorMotion.release,
                                        reduceMotion: reduceMotion),
                       value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed && haptics && isEnabled { Haptics.press() }
            }
    }

    private var scaleFactor: CGFloat {
        guard scales, !reduceMotion, configuration.isPressed else { return 1 }
        return TremorMotion.pressScale
    }
}

// MARK: - Risk band presentation
//
// The band already carries a name and two colours (Theme.swift). What it needs
// here is a *shape* — colour-blind users, and anyone glancing at the screen for
// half a second, get severity from the silhouette before they get it from hue.
// Circle → circle-with-bang → triangle → octagon is a deliberate escalation of
// visual "spikiness".

private extension TremorRiskBand {
    var symbolName: String {
        switch self {
        case .low: return "checkmark.circle.fill"
        case .moderate: return "exclamationmark.circle.fill"
        case .high: return "exclamationmark.triangle.fill"
        case .severe: return "exclamationmark.octagon.fill"
        }
    }

    /// Spoken form. Colour never travels alone into VoiceOver either.
    var spokenLabel: String { "\(title) risk" }
}

// MARK: - Risk chip
//
// A private chip rather than a public badge component: badges belong to the
// badge family, and `TremorListRow` must not depend on a sibling file's API.
// Callers who want the shared badge pass `.custom(_:)` instead.

private struct RiskChip: View {
    let band: TremorRiskBand

    var body: some View {
        HStack(spacing: TremorSpacing.xxs) {
            Image(systemName: band.symbolName)
                .font(.system(size: TremorType.caption.spec.size))
            Text(band.title)
                .tremorType(.captionEmphasis)
        }
        .foregroundStyle(band.mark)
        .padding(.horizontal, TremorSpacing.xs)
        .padding(.vertical, TremorSpacing.xxs)
        .background(band.surface, in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(band.spokenLabel)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - TremorCard
// ─────────────────────────────────────────────────────────────────────────────

/// The workhorse container: a generous white plate on the warm canvas.
///
/// Lyft's structure in one view — `surface-primary` fill, 16pt radius, 16pt
/// inner padding, and the L2 card shadow (design-lyft.md §6.2) — tinted with
/// Zip's aubergine so it never reads as dirty grey on `#F1F0EC`.
///
/// ```swift
/// TremorCard { Text("Bookcase").tremorType(.title3) }
///
/// TremorCard.tappable(accessibilityHint: "Opens the object detail") {
///     openObject()
/// } content: {
///     Text("Bookcase").tremorType(.title3)
/// }
/// ```
///
/// Selection is expressed with **ink, not colour** — a 1.5pt `#1A0826` border,
/// exactly as Lyft selects a ride (design-lyft.md §6.2). Reserve the purple for
/// things that are about to *do* something.
struct TremorCard<Content: View>: View {

    private let padding: CGFloat
    private let fill: Color
    private let radius: CGFloat
    private let shadow: TremorShadow?
    private let isSelected: Bool
    private let action: (() -> Void)?
    private let accessibilityLabel: String?
    private let accessibilityHint: String?
    private let content: Content

    private init(padding: CGFloat,
                 fill: Color,
                 radius: CGFloat,
                 shadow: TremorShadow?,
                 isSelected: Bool,
                 action: (() -> Void)?,
                 accessibilityLabel: String?,
                 accessibilityHint: String?,
                 content: Content) {
        self.padding = padding
        self.fill = fill
        self.radius = radius
        self.shadow = shadow
        self.isSelected = isSelected
        self.action = action
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.content = content
    }

    /// A static, non-interactive card.
    ///
    /// - Parameters:
    ///   - padding: inner padding on all sides. 16pt standard, 12pt for dense
    ///     variants (Lyft §6.2).
    ///   - fill: plate colour. `surface` on canvas; `primarySoft` for the
    ///     lavender informational variant; a risk band `surface` for a tinted
    ///     result card.
    ///   - radius: 16pt card radius by default.
    ///   - shadow: pass `nil` for the flat, tinted-fill treatment Lyft uses when
    ///     a card sits on white rather than on the canvas.
    ///   - isSelected: draws the 1.5pt ink selection border.
    init(padding: CGFloat = TremorSpacing.md,
                fill: Color = TremorColor.surface,
                radius: CGFloat = TremorRadius.card,
                shadow: TremorShadow? = .card,
                isSelected: Bool = false,
                @ViewBuilder content: () -> Content) {
        self.init(padding: padding,
                  fill: fill,
                  radius: radius,
                  shadow: shadow,
                  isSelected: isSelected,
                  action: nil,
                  accessibilityLabel: nil,
                  accessibilityHint: nil,
                  content: content())
    }

    /// The tappable variant: identical plate, plus a press state (0.97 scale +
    /// ink wash clipped to the card's own corners), a light haptic, and the
    /// `.isButton` trait.
    ///
    /// - Parameters:
    ///   - accessibilityLabel: overrides the label VoiceOver would otherwise
    ///     assemble from the card's contents. Supply one when the card is
    ///     mostly graphics.
    ///   - accessibilityHint: what happens on tap, when it is not obvious from
    ///     the label. "Opens the room", "Starts the simulation".
    static func tappable(padding: CGFloat = TremorSpacing.md,
                                fill: Color = TremorColor.surface,
                                radius: CGFloat = TremorRadius.card,
                                shadow: TremorShadow? = .card,
                                isSelected: Bool = false,
                                accessibilityLabel: String? = nil,
                                accessibilityHint: String? = nil,
                                action: @escaping () -> Void,
                                @ViewBuilder content: () -> Content) -> TremorCard {
        TremorCard(padding: padding,
                  fill: fill,
                  radius: radius,
                  shadow: shadow,
                  isSelected: isSelected,
                  action: action,
                  accessibilityLabel: accessibilityLabel,
                  accessibilityHint: accessibilityHint,
                  content: content())
    }

    var body: some View {
        if let action {
            Button(action: action) { plate }
                .buttonStyle(PressStyle(shape: AnyShape(shape)))
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .modifier(OptionalLabel(label: accessibilityLabel))
                .modifier(OptionalHint(hint: accessibilityHint))
        } else {
            plate
        }
    }

    private var plate: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(fill, in: shape)
            .overlay {
                shape.strokeBorder(TremorColor.ink,
                                   lineWidth: isSelected ? TremorSize.strokeEmphasis : 0)
            }
            .modifier(OptionalShadow(shadow: shadow))
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}

// Small conditional modifiers — cheaper and more legible than `if` ladders that
// change the view's type.

private struct OptionalShadow: ViewModifier {
    let shadow: TremorShadow?
    func body(content: Content) -> some View {
        if let shadow { content.tremorShadow(shadow) } else { content }
    }
}

private struct OptionalLabel: ViewModifier {
    let label: String?
    func body(content: Content) -> some View {
        if let label { content.accessibilityLabel(label) } else { content }
    }
}

private struct OptionalHint: ViewModifier {
    let hint: String?
    func body(content: Content) -> some View {
        if let hint { content.accessibilityHint(hint) } else { content }
    }
}

#Preview("TremorCard") {
    ScrollView {
        VStack(alignment: .leading, spacing: TremorSpacing.md) {
            Text("Default — surface fill, card shadow")
                .tremorType(.overline).foregroundStyle(TremorColor.inkTertiary)
            TremorCard {
                VStack(alignment: .leading, spacing: TremorSpacing.xxs) {
                    Text("Living room").tremorType(.title3).foregroundStyle(TremorColor.ink)
                    Text("Scanned 2 days ago · 14 objects")
                        .tremorType(.footnote).foregroundStyle(TremorColor.inkTertiary)
                }
            }

            Text("Tappable — press to see the scale + ink wash")
                .tremorType(.overline).foregroundStyle(TremorColor.inkTertiary)
            TremorCard.tappable(accessibilityHint: "Opens the room") {} content: {
                HStack {
                    VStack(alignment: .leading, spacing: TremorSpacing.xxs) {
                        Text("Bedroom").tremorType(.title3).foregroundStyle(TremorColor.ink)
                        Text("Tap and hold").tremorType(.footnote).foregroundStyle(TremorColor.inkTertiary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(TremorColor.inkTertiary)
                }
            }

            Text("Selected — ink border, never a colour fill")
                .tremorType(.overline).foregroundStyle(TremorColor.inkTertiary)
            TremorCard(isSelected: true) {
                Text("Kitchen").tremorType(.title3).foregroundStyle(TremorColor.ink)
            }

            Text("Disabled tappable — 62% white veil")
                .tremorType(.overline).foregroundStyle(TremorColor.inkTertiary)
            TremorCard.tappable {} content: {
                Text("Unavailable until the scan finishes")
                    .tremorType(.body).foregroundStyle(TremorColor.ink)
            }
            .disabled(true)

            Text("Lavender variant, no shadow, dense padding")
                .tremorType(.overline).foregroundStyle(TremorColor.inkTertiary)
            TremorCard(padding: TremorSpacing.sm, fill: TremorColor.primarySoft, shadow: nil) {
                Text("Anchoring a 1.8 m bookcase cuts its topple risk by about 90%.")
                    .tremorType(.callout).foregroundStyle(TremorColor.ink)
            }

            Text("Risk-tinted variant + very long content")
                .tremorType(.overline).foregroundStyle(TremorColor.inkTertiary)
            TremorCard(fill: TremorRiskBand.severe.surface, shadow: nil) {
                Text("This tall bookcase sits directly beside the bed and is not anchored to the wall, so in a magnitude 6.5 event it is likely to topple across the sleeping area within the first four seconds of strong shaking.")
                    .tremorType(.callout).foregroundStyle(TremorColor.ink)
            }
        }
        .padding(.vertical, TremorSpacing.xl)
    }
    .tremorScreen()
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - TremorListRow
// ─────────────────────────────────────────────────────────────────────────────

/// What sits at the leading edge of a `TremorListRow`.
enum TremorRowLeading {
    case none
    /// A 24pt SF Symbol in ink (Lyft §6.3: leading icon 24 × 24, 16pt to text).
    case icon(String)
    /// A 24pt symbol inside a 40pt tinted well — the lavender treatment Zip uses
    /// for category rows.
    case iconWell(symbol: String, tint: Color, fill: Color)
    /// A 56pt image thumbnail at the 12pt thumbnail radius (Lyft rich row).
    case thumbnail(Image)
    /// A risk band expressed as a filled 40pt mark. Carries symbol + colour, and
    /// its band name goes into the row's accessibility value.
    case risk(TremorRiskBand)

    /// Lavender icon well — the default tinted treatment.
    static func iconWell(_ symbol: String) -> TremorRowLeading {
        .iconWell(symbol: symbol, tint: TremorColor.primary, fill: TremorColor.primarySoft)
    }
}

/// What sits at the trailing edge of a `TremorListRow`.
///
/// Every case has an intrinsic width and is laid out at a higher layout priority
/// than the text block, so a long title truncates instead of shoving the
/// accessory off the row.
enum TremorRowAccessory {
    case none
    /// 16pt chevron in tertiary ink (Lyft §6.3).
    case chevron
    /// A right-aligned value, `value-w1-heavy` in Lyft's ramp.
    case value(String)
    /// A risk band chip: tinted capsule, band symbol, band name.
    case risk(TremorRiskBand)
    /// A count badge — pill, primary fill.
    case badge(String)
    /// A switch. The row becomes a `Toggle`, which gives it the correct
    /// `.isToggle` traits and on/off value for free.
    case toggle(Binding<Bool>)
    /// Anything else — a shared badge component, a small chart, a spinner.
    case custom(AnyView)
}

/// The row used by the object list, the room library and the settings screen.
///
/// Lyft's geometry (design-lyft.md §6.3): 16pt leading/trailing inset, 24pt
/// leading icon with a 16pt gap to the text, `title-w1` 17/500 title,
/// `subtitle-w3` 13/400 tertiary subtitle, 56/72/88pt heights, full-row ink
/// wash on press.
///
/// ```swift
/// TremorListRow(title: "Bookcase",
///              subtitle: "1.8 m · not anchored",
///              leading: .iconWell("books.vertical.fill"),
///              accessory: .risk(.severe)) { open() }
/// ```
///
/// It is built to survive the three things that break list rows in practice:
/// a title long enough to wrap twice, a missing subtitle, and a trailing risk
/// badge that must not move when either happens.
struct TremorListRow: View {

    private let title: String
    private let subtitle: String?
    private let leading: TremorRowLeading
    private let accessory: TremorRowAccessory
    private let titleLineLimit: Int
    private let isSelected: Bool
    private let accessibilityHint: String?
    private let action: (() -> Void)?

    /// - Parameters:
    ///   - titleLineLimit: 2 by default. Long titles truncate rather than
    ///     reflowing the row's fixed trailing block.
    ///   - accessibilityHint: what tapping does, when the title alone does not
    ///     say it.
    ///   - action: omit for a static row. A row with a `.toggle` accessory
    ///     ignores `action` — the switch owns the interaction.
    init(title: String,
                subtitle: String? = nil,
                leading: TremorRowLeading = .none,
                accessory: TremorRowAccessory = .none,
                titleLineLimit: Int = 2,
                isSelected: Bool = false,
                accessibilityHint: String? = nil,
                action: (() -> Void)? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.leading = leading
        self.accessory = accessory
        self.titleLineLimit = titleLineLimit
        self.isSelected = isSelected
        self.accessibilityHint = accessibilityHint
        self.action = action
    }

    var body: some View {
        switch accessory {
        case .toggle(let isOn):
            // Toggle supplies `.isToggle` traits, the on/off value and the
            // switch's own tap target — hand-rolling this loses all three.
            Toggle(isOn: toggleBinding(isOn)) {
                HStack(spacing: TremorSpacing.md) {
                    leadingView
                    textBlock
                }
            }
            .tint(TremorColor.primary)
            .padding(.horizontal, TremorSpacing.listInset)
            .padding(.vertical, TremorSpacing.sm)
            .frame(minHeight: minimumHeight)
            .background(rowFill)
            .accessibilityHint(accessibilityHint ?? "")

        default:
            if let action {
                Button(action: action) { rowContent }
                    .buttonStyle(PressStyle(shape: AnyShape(Rectangle()), scales: false))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(title)
                    .accessibilityValue(spokenValue)
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                    .modifier(OptionalHint(hint: accessibilityHint))
            } else {
                rowContent
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(title)
                    .accessibilityValue(spokenValue)
            }
        }
    }

    // MARK: Row body

    private var rowContent: some View {
        HStack(spacing: TremorSpacing.md) {
            leadingView
            textBlock
            accessoryView
                .layoutPriority(1)
        }
        .padding(.horizontal, TremorSpacing.listInset)
        .padding(.vertical, TremorSpacing.sm)
        .frame(minHeight: minimumHeight)
        .background(rowFill)
        .contentShape(Rectangle())
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.xxs) {
            Text(title)
                .tremorType(.bodyEmphasis)
                .foregroundStyle(TremorColor.ink)
                .lineLimit(titleLineLimit)
                .multilineTextAlignment(.leading)
            if let subtitle {
                Text(subtitle)
                    .tremorType(.footnote)
                    .foregroundStyle(TremorColor.inkTertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var leadingView: some View {
        switch leading {
        case .none:
            EmptyView()

        case .icon(let symbol):
            Image(systemName: symbol)
                .font(.system(size: Metric.icon))
                .foregroundStyle(TremorColor.ink)
                .frame(width: Metric.icon, height: Metric.icon)
                .accessibilityHidden(true)

        case .iconWell(let symbol, let tint, let fill):
            Image(systemName: symbol)
                .font(.system(size: TremorType.title3.spec.size))
                .foregroundStyle(tint)
                .frame(width: Metric.well, height: Metric.well)
                .background(fill, in: Circle())
                .accessibilityHidden(true)

        case .thumbnail(let image):
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: Metric.thumbnail, height: Metric.thumbnail)
                .clipShape(RoundedRectangle(cornerRadius: TremorRadius.thumbnail, style: .continuous))
                .accessibilityHidden(true)

        case .risk(let band):
            Image(systemName: band.symbolName)
                .font(.system(size: TremorType.title3.spec.size))
                .foregroundStyle(band.mark)
                .frame(width: Metric.well, height: Metric.well)
                .background(band.surface, in: Circle())
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var accessoryView: some View {
        switch accessory {
        case .none, .toggle:
            EmptyView()

        case .chevron:
            Image(systemName: "chevron.right")
                .font(.system(size: Metric.glyph, weight: .semibold))
                .foregroundStyle(TremorColor.inkTertiary)
                .accessibilityHidden(true)

        case .value(let value):
            Text(value)
                .tremorType(.subheadline, numeric: true)
                .foregroundStyle(TremorColor.inkSecondary)
                .lineLimit(1)
                .fixedSize()
                .accessibilityHidden(true)

        case .risk(let band):
            RiskChip(band: band)
                .accessibilityHidden(true)

        case .badge(let text):
            Text(text)
                .tremorType(.captionEmphasis, numeric: true)
                .foregroundStyle(TremorColor.onPrimary)
                .padding(.horizontal, TremorSpacing.xs)
                .padding(.vertical, TremorSpacing.hair)
                .background(TremorColor.primary, in: Capsule())
                .fixedSize()
                .accessibilityHidden(true)

        case .custom(let view):
            view.fixedSize()
        }
    }

    // MARK: Geometry & semantics

    /// Lyft's three row heights: 56 single-line, 72 two-line, 88 with a 56pt
    /// thumbnail. A `minHeight` rather than a fixed height so accessibility
    /// text sizes can grow the row instead of clipping it.
    private var minimumHeight: CGFloat {
        switch leading {
        case .thumbnail:
            return TremorSize.rowRich
        default:
            return subtitle == nil ? TremorSize.row : TremorSize.rowTwoLine
        }
    }

    private var rowFill: some View {
        // Lyft's row selection is a wash, not a colour fill. It is rounded so a
        // selected row inside a sheet gutter reads as a deliberate shape rather
        // than as a mis-clipped rectangle.
        RoundedRectangle(cornerRadius: TremorRadius.thumbnail, style: .continuous)
            .fill(isSelected ? TremorColor.primarySoft : Color.clear)
    }

    /// Everything the row conveys that is *not* the title — subtitle, value,
    /// risk band, count. This is why colour never carries meaning alone: the
    /// band's name is spoken here whether or not the chip is visible.
    private var spokenValue: String {
        var parts: [String] = []
        if let subtitle { parts.append(subtitle) }
        switch leading {
        case .risk(let band): parts.append(band.spokenLabel)
        default: break
        }
        switch accessory {
        case .value(let value): parts.append(value)
        case .risk(let band): parts.append(band.spokenLabel)
        case .badge(let text): parts.append(text)
        default: break
        }
        return parts.joined(separator: ", ")
    }

    private func toggleBinding(_ binding: Binding<Bool>) -> Binding<Bool> {
        Binding(get: { binding.wrappedValue },
                set: { newValue in
                    Haptics.selection()
                    binding.wrappedValue = newValue
                })
    }
}

/// The hairline between rows inside a card: 1pt `divider`, inset to the row's
/// 16pt leading gutter (Lyft §6.3). Lyft prefers whitespace to rules, so reach
/// for this only when rows genuinely need separating.
struct TremorRowDivider: View {
    private let leadingInset: CGFloat

    init(leadingInset: CGFloat = TremorSpacing.listInset) {
        self.leadingInset = leadingInset
    }

    var body: some View {
        Rectangle()
            .fill(TremorColor.divider)
            .frame(height: TremorSize.hairline)
            .padding(.leading, leadingInset)
            .accessibilityHidden(true)
    }
}

#Preview("TremorListRow") {
    struct Host: View {
        @State private var recordEnabled = true
        @State private var hapticsEnabled = false

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: TremorSpacing.lg) {
                    Group {
                        Text("Object list — icon well + risk chip")
                            .tremorType(.overline).foregroundStyle(TremorColor.inkTertiary)
                        TremorCard(padding: 0) {
                            VStack(spacing: 0) {
                                TremorListRow(title: "Bookcase",
                                             subtitle: "1.8 m · not anchored",
                                             leading: .iconWell("books.vertical.fill"),
                                             accessory: .risk(.severe),
                                             accessibilityHint: "Opens object details") {}
                                TremorRowDivider()
                                TremorListRow(title: "Television",
                                             subtitle: "55 in · on a low stand",
                                             leading: .iconWell("tv.fill"),
                                             accessory: .risk(.high)) {}
                                TremorRowDivider()
                                TremorListRow(title: "Floor lamp",
                                             subtitle: "Tall, narrow base",
                                             leading: .iconWell("lamp.floor.fill"),
                                             accessory: .risk(.moderate)) {}
                                TremorRowDivider()
                                TremorListRow(title: "Coffee table",
                                             subtitle: "Low centre of mass",
                                             leading: .iconWell("table.furniture.fill"),
                                             accessory: .risk(.low)) {}
                            }
                        }

                        Text("Long title, no subtitle, badge still fixed")
                            .tremorType(.overline).foregroundStyle(TremorColor.inkTertiary)
                        TremorCard(padding: 0) {
                            TremorListRow(title: "Antique mahogany display cabinet with glass doors",
                                         leading: .risk(.severe),
                                         accessory: .risk(.severe)) {}
                        }
                    }

                    Group {
                        Text("Settings — switches, values, chevrons")
                            .tremorType(.overline).foregroundStyle(TremorColor.inkTertiary)
                        TremorCard(padding: 0) {
                            VStack(spacing: 0) {
                                TremorListRow(title: "Record simulations",
                                             subtitle: "Saves a video to your photo library",
                                             leading: .icon("video.fill"),
                                             accessory: .toggle($recordEnabled))
                                TremorRowDivider()
                                TremorListRow(title: "Haptics",
                                             leading: .icon("waveform"),
                                             accessory: .toggle($hapticsEnabled))
                                TremorRowDivider()
                                TremorListRow(title: "Default magnitude",
                                             leading: .icon("waveform.path.ecg"),
                                             accessory: .value("6.5 Mw")) {}
                                TremorRowDivider()
                                TremorListRow(title: "About proof",
                                             leading: .icon("info.circle"),
                                             accessory: .chevron,
                                             accessibilityHint: "Opens the about screen") {}
                                TremorRowDivider()
                                TremorListRow(title: "Unsafe objects",
                                             leading: .icon("exclamationmark.triangle"),
                                             accessory: .badge("7")) {}
                            }
                        }

                        Text("Selected row · static row · disabled row")
                            .tremorType(.overline).foregroundStyle(TremorColor.inkTertiary)
                        TremorCard(padding: 0) {
                            VStack(spacing: 0) {
                                TremorListRow(title: "Living room",
                                             subtitle: "Selected",
                                             leading: .icon("sofa.fill"),
                                             accessory: .chevron,
                                             isSelected: true) {}
                                TremorRowDivider()
                                TremorListRow(title: "Static row — no action",
                                             subtitle: "No press state, no button trait",
                                             leading: .icon("circle.dashed"))
                                TremorRowDivider()
                                TremorListRow(title: "Disabled row",
                                             subtitle: "Veiled at 62%",
                                             leading: .icon("nosign"),
                                             accessory: .chevron) {}
                                    .disabled(true)
                            }
                        }
                    }
                }
                .padding(.vertical, TremorSpacing.xl)
            }
            .tremorScreen()
        }
    }
    return Host()
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - TremorSectionHeader
// ─────────────────────────────────────────────────────────────────────────────

/// The overline label above a group, with an optional trailing action.
///
/// The overline itself is Zip's device — `--native-caption` 10/16 set all-caps
/// and tracked to +0.12em (design-zip.md §3.3) — and the trailing "View all" in
/// interactive purple is Zip's dashboard section header (§8).
///
/// ```swift
/// TremorSectionHeader("Unsafe objects", actionTitle: "See all") { showAll() }
/// ```
struct TremorSectionHeader: View {

    private let title: String
    private let subtitle: String?
    private let actionTitle: String?
    private let actionHint: String?
    private let action: (() -> Void)?

    init(_ title: String,
                subtitle: String? = nil,
                actionTitle: String? = nil,
                actionHint: String? = nil,
                action: (() -> Void)? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.actionHint = actionHint
        self.action = action
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TremorSpacing.sm) {
            VStack(alignment: .leading, spacing: TremorSpacing.xxs) {
                Text(title)
                    .tremorType(.overline)
                    .foregroundStyle(TremorColor.inkTertiary)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .tremorType(.footnote)
                        .foregroundStyle(TremorColor.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .tremorType(.subheadline)
                        .foregroundStyle(TremorColor.primary)
                        .padding(.horizontal, TremorSpacing.xs)
                        .padding(.vertical, TremorSpacing.xxs)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle(shape: AnyShape(Capsule()), wash: TremorColor.focusRing))
                .accessibilityHint(actionHint ?? "")
                .fixedSize()
            }
        }
        .padding(.vertical, TremorSpacing.xs)
    }
}

#Preview("TremorSectionHeader") {
    ScrollView {
        VStack(alignment: .leading, spacing: TremorSpacing.xl) {
            TremorSectionHeader("Your rooms")

            TremorSectionHeader("Unsafe objects",
                               actionTitle: "See all",
                               actionHint: "Shows every flagged object") {}

            TremorSectionHeader("Simulation",
                               subtitle: "Magnitude 6.5, 18 seconds of strong shaking",
                               actionTitle: "Change") {}

            TremorSectionHeader("A deliberately long section title that has to wrap on a narrow phone",
                               actionTitle: "Edit") {}
        }
        .padding(.vertical, TremorSpacing.xl)
    }
    .tremorScreen()
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - TremorBanner
// ─────────────────────────────────────────────────────────────────────────────

/// The semantic kinds a banner can take. One per semantic colour in the theme,
/// plus the four risk bands.
///
/// Each kind carries a **symbol**, a **role word** and a colour — three
/// independent channels — so nothing depends on hue alone.
enum TremorBannerKind: Hashable {
    case info
    case success
    case warning
    case danger
    /// The quiet one: sunken surface, ink text. For neutral asides.
    case neutral
    /// The brand one: lavender surface, purple mark. For tips and upsells.
    case highlight
    case risk(TremorRiskBand)

    var mark: Color {
        switch self {
        case .info: return TremorColor.info
        case .success: return TremorColor.success
        case .warning: return TremorColor.warning
        case .danger: return TremorColor.danger
        case .neutral: return TremorColor.inkSecondary
        case .highlight: return TremorColor.primary
        case .risk(let band): return band.mark
        }
    }

    var surface: Color {
        switch self {
        case .neutral: return TremorColor.surfaceSunken
        case .highlight: return TremorColor.primarySoft
        case .risk(let band): return band.surface
        default: return Wash.tint(mark)
        }
    }

    var symbolName: String {
        switch self {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .danger: return "exclamationmark.octagon.fill"
        case .neutral: return "circle.dashed"
        case .highlight: return "sparkles"
        case .risk(let band): return band.symbolName
        }
    }

    /// Spoken prefix. VoiceOver hears the severity before the message.
    var roleLabel: String {
        switch self {
        case .info: return "Information"
        case .success: return "Success"
        case .warning: return "Warning"
        case .danger: return "Error"
        case .neutral: return "Note"
        case .highlight: return "Tip"
        case .risk(let band): return band.spokenLabel
        }
    }
}

/// An inline informational or warning banner.
///
/// Built as a flat tinted plate rather than a shadowed card, because it is a
/// message *about* the content around it, not a peer of it — the same reason
/// Lyft drops the shadow when a card sits on white (design-lyft.md §6.2).
///
/// ```swift
/// TremorBanner("Two objects could not be measured",
///             message: "Rescan the far wall for a complete report.",
///             kind: .warning,
///             actionTitle: "Rescan") { rescan() }
/// ```
struct TremorBanner: View {

    private let title: String
    private let message: String?
    private let kind: TremorBannerKind
    private let actionTitle: String?
    private let action: (() -> Void)?
    private let onDismiss: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ title: String,
                message: String? = nil,
                kind: TremorBannerKind = .info,
                actionTitle: String? = nil,
                action: (() -> Void)? = nil,
                onDismiss: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.kind = kind
        self.actionTitle = actionTitle
        self.action = action
        self.onDismiss = onDismiss
    }

    var body: some View {
        HStack(alignment: .top, spacing: TremorSpacing.sm) {
            Image(systemName: kind.symbolName)
                .font(.system(size: TremorType.title3.spec.size))
                .foregroundStyle(kind.mark)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: TremorSpacing.xxs) {
                Text(title)
                    .tremorType(.bodyEmphasis)
                    .foregroundStyle(TremorColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let message {
                    Text(message)
                        .tremorType(.callout)
                        .foregroundStyle(TremorColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let actionTitle, let action {
                    Button(action: action) {
                        Text(actionTitle)
                            .tremorType(.subheadline)
                            .foregroundStyle(kind.mark)
                            .padding(.vertical, TremorSpacing.xxs)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle(shape: AnyShape(Capsule()), wash: Wash.pressed))
                    .padding(.top, TremorSpacing.hair)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: Metric.glyph, weight: .semibold))
                        .foregroundStyle(TremorColor.inkTertiary)
                        .frame(width: TremorSize.minimumTapTarget, height: TremorSize.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle(shape: AnyShape(Circle()), scales: false))
                .accessibilityLabel("Dismiss")
                .accessibilityHint("Hides this message")
                .offset(x: TremorSpacing.xs, y: -TremorSpacing.xs)
            }
        }
        .padding(TremorSpacing.md)
        .background(kind.surface, in: RoundedRectangle(cornerRadius: TremorRadius.card, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(kind.roleLabel). \(title)")
        .accessibilityValue(message ?? "")
        .animation(Motion.animation(TremorMotion.colorShift, reduceMotion: reduceMotion), value: kind)
    }
}

#Preview("TremorBanner") {
    ScrollView {
        VStack(alignment: .leading, spacing: TremorSpacing.sm) {
            TremorSectionHeader("One per semantic colour")

            TremorBanner("Scan saved", message: "Living room is ready to simulate.", kind: .success)
            TremorBanner("Simulation uses estimated weights",
                        message: "proof guesses mass from object size and material. Numbers are indicative, not certified.",
                        kind: .info)
            TremorBanner("Two objects could not be measured",
                        message: "Rescan the far wall for a complete report.",
                        kind: .warning,
                        actionTitle: "Rescan",
                        action: {})
            TremorBanner("Scan failed",
                        message: "There wasn’t enough light to track the room.",
                        kind: .danger,
                        actionTitle: "Try again",
                        action: {},
                        onDismiss: {})
            TremorBanner("Room not yet simulated", kind: .neutral)
            TremorBanner("Anchoring kits cost about £12",
                        message: "Two straps secure a typical bookcase in under ten minutes.",
                        kind: .highlight,
                        actionTitle: "How to anchor",
                        action: {})

            TremorSectionHeader("Risk bands")
            TremorBanner("Bookcase is likely to topple", kind: .risk(.severe))
            TremorBanner("Television may slide off its stand", kind: .risk(.high))
            TremorBanner("Floor lamp may rock", kind: .risk(.moderate))
            TremorBanner("Coffee table is stable", kind: .risk(.low))

            TremorSectionHeader("Title only · very long body")
            TremorBanner("Rescan recommended", kind: .warning)
            TremorBanner("Why your results changed",
                        message: "proof re-ran the rigid-block solver with the updated friction database, which lowered the estimated sliding threshold for hard flooring and raised it slightly for carpet. Objects near the boundary may have moved a band in either direction.",
                        kind: .info,
                        onDismiss: {})
        }
        .padding(.vertical, TremorSpacing.xl)
    }
    .tremorScreen()
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - TremorEmptyState
// ─────────────────────────────────────────────────────────────────────────────

/// The default illustration slot: a symbol in a lavender well.
///
/// Zip's empty states are inferred rather than observed (design-zip.md §8), so
/// this follows the system rather than a screenshot: `primarySoft` circle,
/// ink glyph, nothing louder.
struct TremorSymbolIllustration: View {
    private let systemName: String
    private let tint: Color
    private let fill: Color

    init(_ systemName: String,
                tint: Color = TremorColor.primary,
                fill: Color = TremorColor.primarySoft) {
        self.systemName = systemName
        self.tint = tint
        self.fill = fill
    }

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: TremorType.displayM.spec.size, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: Metric.illustration, height: Metric.illustration)
            .background(fill, in: Circle())
            .accessibilityHidden(true)
    }
}

/// Illustration, headline, body and one primary action. Used by the empty room
/// library, empty search results and the "no unsafe objects" result.
///
/// ```swift
/// TremorEmptyState(title: "No rooms yet",
///                 message: "Scan a room to see how it behaves in an earthquake.",
///                 systemImage: "arkit",
///                 actionTitle: "Scan a room") { startScan() }
/// ```
struct TremorEmptyState<Illustration: View>: View {

    private let title: String
    private let message: String?
    private let actionTitle: String?
    private let actionHint: String?
    private let action: (() -> Void)?
    private let illustration: Illustration

    init(title: String,
                message: String? = nil,
                actionTitle: String? = nil,
                actionHint: String? = nil,
                action: (() -> Void)? = nil,
                @ViewBuilder illustration: () -> Illustration) {
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.actionHint = actionHint
        self.action = action
        self.illustration = illustration()
    }

    var body: some View {
        VStack(spacing: 0) {
            illustration
                .padding(.bottom, TremorSpacing.xl)

            Text(title)
                .tremorType(.title2)
                .foregroundStyle(TremorColor.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            if let message {
                Text(message)
                    .tremorType(.callout)
                    .foregroundStyle(TremorColor.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, TremorSpacing.xs)
            }

            if let actionTitle, let action {
                PillAction(title: actionTitle, hint: actionHint, action: action)
                    .padding(.top, TremorSpacing.xxxl)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, TremorSpacing.xl)
        .padding(.vertical, TremorSpacing.xxxl)
        .accessibilityElement(children: .contain)
    }
}

extension TremorEmptyState where Illustration == TremorSymbolIllustration {
    /// One-line convenience: an SF Symbol in the standard lavender well.
    init(title: String,
         message: String? = nil,
         systemImage: String,
         actionTitle: String? = nil,
         actionHint: String? = nil,
         action: (() -> Void)? = nil) {
        self.init(title: title,
                  message: message,
                  actionTitle: actionTitle,
                  actionHint: actionHint,
                  action: action) {
            TremorSymbolIllustration(systemImage)
        }
    }
}

/// The 56pt primary pill.
///
/// Deliberately private: the button family lives in its own file, and a
/// container must never depend on a sibling's API to render. Same spec either
/// way — Lyft's 56pt full-pill CTA (design-lyft.md §6.1) filled with Zip's
/// interactive purple.
private struct PillAction: View {
    let title: String
    var hint: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .tremorType(.headline)
                .foregroundStyle(TremorColor.onPrimary)
                .padding(.horizontal, TremorSpacing.xl)
                .frame(minHeight: TremorSize.buttonLarge)
                .frame(maxWidth: .infinity)
                .background(TremorColor.primary, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle(shape: AnyShape(Capsule()), wash: Wash.pressedOnFill))
        .accessibilityHint(hint ?? "")
    }
}

#Preview("TremorEmptyState") {
    ScrollView {
        VStack(spacing: TremorSpacing.xxl) {
            TremorCard(padding: 0, shadow: nil, isSelected: false) {
                TremorEmptyState(title: "No rooms yet",
                                message: "Scan a room to see how your furniture behaves when the ground moves.",
                                systemImage: "arkit",
                                actionTitle: "Scan a room",
                                actionHint: "Opens the camera") {}
            }

            TremorCard(padding: 0, shadow: nil) {
                TremorEmptyState(title: "Nothing unsafe here",
                                message: "Every object in this room stayed put.",
                                systemImage: "checkmark.seal.fill",
                                action: nil)
            }

            TremorCard(padding: 0, shadow: nil) {
                TremorEmptyState(title: "No results",
                                systemImage: "magnifyingglass")
            }

            TremorCard(padding: 0, shadow: nil) {
                TremorEmptyState(title: "This room has an unusually long name and no objects at all yet",
                                message: "The scan finished, but proof could not identify any furniture. Try scanning again more slowly, keeping each surface in view for a couple of seconds, and make sure the room is well lit.",
                                actionTitle: "Rescan the room") {
                    TremorSymbolIllustration("exclamationmark.arrow.trianglehead.2.clockwise.rotate.90",
                                            tint: TremorColor.warning,
                                            fill: Wash.tint(TremorColor.warning))
                }
            }
        }
        .padding(.vertical, TremorSpacing.xl)
    }
    .tremorScreen()
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - TremorProgressBar
// ─────────────────────────────────────────────────────────────────────────────

/// Determinate and indeterminate linear progress.
///
/// Lyft's bar (design-lyft.md §6.9): 4pt tall, radius 2, `gray10` track, ink or
/// interactive fill, animated on the `change` curve. Tremor's track is
/// `surfaceSunken` — the warm recessed well — and the fill is the interactive
/// purple.
///
/// ```swift
/// TremorProgressBar(value: 0.4, label: "Reconstructing mesh")
/// TremorProgressBar()                      // indeterminate
/// ```
///
/// Indeterminate mode runs a travelling segment; under Reduce Motion it becomes
/// a static half-tinted track, because a looping animation is exactly what that
/// setting exists to stop.
struct TremorProgressBar: View {

    private let value: Double?
    private let label: String?
    private let tint: Color
    private let showsValueLabel: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    /// - Parameters:
    ///   - value: 0…1, or `nil` for indeterminate.
    ///   - label: caption above the bar. Also becomes the accessibility label.
    ///   - showsValueLabel: shows a right-aligned tabular percentage.
    init(value: Double? = nil,
                label: String? = nil,
                tint: Color = TremorColor.primary,
                showsValueLabel: Bool = false) {
        self.value = value
        self.label = label
        self.tint = tint
        self.showsValueLabel = showsValueLabel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.xs) {
            if label != nil || showsValueLabel {
                HStack(alignment: .firstTextBaseline, spacing: TremorSpacing.xs) {
                    if let label {
                        Text(label)
                            .tremorType(.footnote)
                            .foregroundStyle(TremorColor.inkSecondary)
                    }
                    Spacer(minLength: 0)
                    if showsValueLabel, let value {
                        Text(percentText(value))
                            .tremorType(.footnote, numeric: true)
                            .foregroundStyle(TremorColor.inkSecondary)
                    }
                }
            }

            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(TremorColor.surfaceSunken)

                    if let value {
                        Capsule()
                            .fill(tint)
                            .frame(width: max(0, min(1, CGFloat(value))) * width)
                            .animation(Motion.animation(TremorMotion.change, reduceMotion: reduceMotion),
                                       value: value)
                    } else if reduceMotion {
                        // No loop under Reduce Motion — a steady tinted track
                        // still says "working" without moving.
                        Capsule()
                            .fill(tint.opacity(0.45))
                    } else {
                        Capsule()
                            .fill(tint)
                            .frame(width: width * Self.segmentFraction)
                            .offset(x: phase * width)
                    }
                }
                .frame(height: Metric.barHeight)
                .frame(maxHeight: .infinity, alignment: .center)
                .onAppear { startLoopIfNeeded(width: width) }
            }
            .frame(height: Metric.barHeight)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? "Progress")
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(value == nil ? .updatesFrequently : [])
    }

    /// The travelling segment is ~35% of the track — long enough to read as a
    /// bar rather than a dot, short enough that the gap is obvious.
    private static let segmentFraction: CGFloat = 0.35

    private func startLoopIfNeeded(width: CGFloat) {
        guard value == nil, !reduceMotion else { return }
        phase = -Self.segmentFraction
        withAnimation(.linear(duration: TremorMotion.long * 4).repeatForever(autoreverses: false)) {
            phase = 1
        }
    }

    private func percentText(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    private var accessibilityValue: String {
        guard let value else { return "In progress" }
        return percentText(max(0, min(1, value)))
    }
}

#Preview("TremorProgressBar") {
    struct Host: View {
        @State private var value: Double = 0.42

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: TremorSpacing.xl) {
                    TremorSectionHeader("Determinate")
                    TremorCard {
                        TremorProgressBar(value: value,
                                         label: "Reconstructing mesh",
                                         showsValueLabel: true)
                    }

                    TremorCard {
                        VStack(alignment: .leading, spacing: TremorSpacing.md) {
                            TremorProgressBar(value: 0, label: "Empty")
                            TremorProgressBar(value: 0.5, label: "Half")
                            TremorProgressBar(value: 1, label: "Complete", tint: TremorColor.success)
                            TremorProgressBar(value: 0.8,
                                             label: "A caption long enough to wrap against a percentage label on a narrow phone",
                                             showsValueLabel: true)
                        }
                    }

                    TremorSectionHeader("Indeterminate")
                    TremorCard {
                        TremorProgressBar(label: "Estimating object mass")
                    }

                    // `accessibilityReduceMotion` is read-only in
                    // `EnvironmentValues`, so this case is reviewed by turning
                    // Settings › Accessibility › Motion › Reduce Motion on:
                    // the travelling segment becomes a steady 45% tinted track.
                    TremorSectionHeader("Reduce Motion — static tint, no loop",
                                       subtitle: "Enable Reduce Motion in Settings to review")
                    TremorCard {
                        TremorProgressBar(label: "Estimating object mass")
                    }

                    TremorCard {
                        Button("Advance") {
                            value = value >= 1 ? 0 : min(1, value + 0.2)
                        }
                        .tremorType(.subheadline)
                        .foregroundStyle(TremorColor.primary)
                    }
                }
                .padding(.vertical, TremorSpacing.xl)
            }
            .tremorScreen()
        }
    }
    return Host()
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - TremorProgressRing
// ─────────────────────────────────────────────────────────────────────────────

/// The scan-processing ring. Determinate or indeterminate.
///
/// Lyft explicitly does **not** put a spinner in the sheet — indeterminate
/// waiting is a *pulsing halo* (design-lyft.md §7.3). This ring copies that
/// idea: a breathing halo behind two counter-rotating arcs whose sweep lengths
/// oscillate, so it reads as something working rather than something stalled.
/// The determinate form settles on `TremorMotion.springy`, the one place the
/// system allows physical overshoot.
///
/// ```swift
/// TremorProgressRing(value: 0.62, caption: "Estimating mass")
/// TremorProgressRing(caption: "Reconstructing your room")   // indeterminate
/// ```
struct TremorProgressRing: View {

    private let value: Double?
    private let caption: String?
    private let size: CGFloat
    private let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin: Double = 0
    @State private var counterSpin: Double = 0
    @State private var sweep: CGFloat = Self.minimumSweep
    @State private var halo: CGFloat = 1

    /// - Parameters:
    ///   - value: 0…1, or `nil` for indeterminate.
    ///   - caption: the line under the numeral. Also the accessibility label.
    init(value: Double? = nil,
                caption: String? = nil,
                size: CGFloat = TremorSize.rowRich + TremorSpacing.xxl,   // = Metric.ring
                tint: Color = TremorColor.primary) {
        self.value = value
        self.caption = caption
        self.size = size
        self.tint = tint
    }

    var body: some View {
        VStack(spacing: TremorSpacing.md) {
            ZStack {
                haloLayer
                track
                if let value {
                    determinateArc(value)
                } else {
                    indeterminateArcs
                }
                centreLabel
            }
            .frame(width: size, height: size)

            if let caption {
                Text(caption)
                    .tremorType(.footnote)
                    .foregroundStyle(TremorColor.inkTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear(perform: startAnimating)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption ?? "Progress")
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(value == nil ? .updatesFrequently : [])
    }

    // MARK: Layers

    @ViewBuilder
    private var haloLayer: some View {
        // The Lyft halo, scaled down to ring size: a soft expanding wash rather
        // than a hard glow. Static under Reduce Motion.
        Circle()
            .fill(tint.opacity(0.10))
            .scaleEffect(reduceMotion ? 1 : halo)
    }

    private var track: some View {
        Circle()
            .stroke(TremorColor.surfaceSunken, lineWidth: Metric.ringStroke)
    }

    private func determinateArc(_ value: Double) -> some View {
        Circle()
            .trim(from: 0, to: max(0, min(1, CGFloat(value))))
            .stroke(tint, style: StrokeStyle(lineWidth: Metric.ringStroke, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .animation(Motion.animation(TremorMotion.springy, reduceMotion: reduceMotion), value: value)
    }

    @ViewBuilder
    private var indeterminateArcs: some View {
        if reduceMotion {
            // A fixed quarter-turn arc: unmistakably "in progress", motionless.
            Circle()
                .trim(from: 0, to: 0.25)
                .stroke(tint, style: StrokeStyle(lineWidth: Metric.ringStroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
        } else {
            ZStack {
                Circle()
                    .trim(from: 0, to: sweep)
                    .stroke(tint, style: StrokeStyle(lineWidth: Metric.ringStroke, lineCap: .round))
                    .rotationEffect(.degrees(spin))

                Circle()
                    .trim(from: 0, to: sweep * 0.45)
                    .stroke(tint.opacity(0.40),
                            style: StrokeStyle(lineWidth: Metric.ringStroke / 2, lineCap: .round))
                    .padding(Metric.ringStroke)
                    .rotationEffect(.degrees(counterSpin))
            }
        }
    }

    @ViewBuilder
    private var centreLabel: some View {
        if let value {
            Text(percentText(value))
                .tremorType(.title2, numeric: true)
                .foregroundStyle(TremorColor.ink)
        }
    }

    // MARK: Animation

    private static let minimumSweep: CGFloat = 0.08
    private static let maximumSweep: CGFloat = 0.62

    private func startAnimating() {
        guard value == nil, !reduceMotion else { return }

        withAnimation(.linear(duration: TremorMotion.long * 6).repeatForever(autoreverses: false)) {
            spin = 360
        }
        withAnimation(.linear(duration: TremorMotion.long * 10).repeatForever(autoreverses: false)) {
            counterSpin = -360
        }
        withAnimation(TremorMotion.change.repeatForever(autoreverses: true)) {
            sweep = Self.maximumSweep
        }
        withAnimation(.easeInOut(duration: TremorMotion.long * 3).repeatForever(autoreverses: true)) {
            halo = 1.08
        }
    }

    private func percentText(_ value: Double) -> String {
        max(0, min(1, value)).formatted(.percent.precision(.fractionLength(0)))
    }

    private var accessibilityValue: String {
        guard let value else { return "In progress" }
        return percentText(value)
    }
}

#Preview("TremorProgressRing") {
    struct Host: View {
        @State private var value: Double = 0.62

        var body: some View {
            ScrollView {
                VStack(spacing: TremorSpacing.xxl) {
                    TremorSectionHeader("Indeterminate — scan processing")
                    TremorCard {
                        TremorProgressRing(caption: "Reconstructing your room")
                            .frame(maxWidth: .infinity)
                    }

                    TremorSectionHeader("Determinate")
                    TremorCard {
                        VStack(spacing: TremorSpacing.lg) {
                            TremorProgressRing(value: value, caption: "Estimating object mass")
                            Button("Advance") { value = value >= 1 ? 0 : min(1, value + 0.17) }
                                .tremorType(.subheadline)
                                .foregroundStyle(TremorColor.primary)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    TremorSectionHeader("Edge values · small size · risk tint")
                    TremorCard {
                        HStack(spacing: TremorSpacing.lg) {
                            TremorProgressRing(value: 0, caption: "0%", size: TremorSize.rowRich)
                            TremorProgressRing(value: 1, caption: "Done",
                                              size: TremorSize.rowRich, tint: TremorColor.success)
                            TremorProgressRing(value: 0.87, caption: "Severe",
                                              size: TremorSize.rowRich,
                                              tint: TremorRiskBand.severe.mark)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    // Same here: enable Reduce Motion in Settings and the two
                    // rotating arcs collapse to one static quarter-turn arc and
                    // the halo stops breathing.
                    TremorSectionHeader("Reduce Motion — static arc, no spin",
                                       subtitle: "Enable Reduce Motion in Settings to review")
                    TremorCard {
                        TremorProgressRing(caption: "Reconstructing your room")
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, TremorSpacing.xl)
            }
            .tremorScreen()
        }
    }
    return Host()
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - TremorToast
// ─────────────────────────────────────────────────────────────────────────────

/// Toast styles. On the ink plate every mark is a *light* colour, because the
/// semantic marks (`success`, `danger`, …) are tuned for light backgrounds and
/// would disappear on `#1A0826`.
enum TremorToastStyle: Hashable {
    case success
    case info
    case warning
    case error

    var mark: Color {
        switch self {
        // Yuzu on aubergine is 16.97:1 — Zip's own pairing.
        case .success: return TremorColor.accent
        case .info: return TremorColor.primarySoft
        case .warning: return TremorColor.riskModerateSurface
        case .error: return TremorColor.riskSevereSurface
        }
    }

    var symbolName: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "exclamationmark.octagon.fill"
        }
    }

    var roleLabel: String {
        switch self {
        case .success: return "Success"
        case .info: return "Information"
        case .warning: return "Warning"
        case .error: return "Error"
        }
    }

    var haptic: UINotificationFeedbackGenerator.FeedbackType {
        switch self {
        case .success: return .success
        case .info, .warning: return .warning
        case .error: return .error
        }
    }
}

/// The payload a toast presents. Value type, `Identifiable` so the host can key
/// its auto-dismiss task off it and re-arm cleanly when a new toast replaces a
/// visible one.
struct TremorToastMessage: Identifiable, Equatable {
    let id: UUID
    var title: String
    var message: String?
    var style: TremorToastStyle
    /// Seconds on screen before auto-dismissal.
    var duration: Double

    init(_ title: String,
                message: String? = nil,
                style: TremorToastStyle = .success,
                duration: Double = 2.6) {
        self.id = UUID()
        self.title = title
        self.message = message
        self.style = style
        self.duration = duration
    }
}

/// A transient confirmation that slides in from the top.
///
/// Lyft's toast (design-lyft.md §6.9): 12pt radius, inverse surface, white text,
/// L6 elevation, 16pt padding, 16pt from the edges, in on `enter`/300ms and out
/// on `exit`/250ms. Tremor's inverse surface is the aubergine ink.
///
/// Use the `.tremorToast(_:)` modifier rather than placing this by hand — the
/// modifier owns presentation, the auto-dismiss timer, swipe-to-dismiss and the
/// VoiceOver announcement.
struct TremorToast: View {

    private let message: TremorToastMessage
    private let onDismiss: (() -> Void)?

    init(_ message: TremorToastMessage, onDismiss: (() -> Void)? = nil) {
        self.message = message
        self.onDismiss = onDismiss
    }

    var body: some View {
        HStack(alignment: .top, spacing: TremorSpacing.sm) {
            Image(systemName: message.style.symbolName)
                .font(.system(size: TremorType.title3.spec.size))
                .foregroundStyle(message.style.mark)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: TremorSpacing.hair) {
                Text(message.title)
                    .tremorType(.subheadline)
                    .foregroundStyle(TremorColor.inkInverse)
                    .fixedSize(horizontal: false, vertical: true)
                if let body = message.message {
                    Text(body)
                        .tremorType(.footnote)
                        .foregroundStyle(TremorColor.inkInverse.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(TremorSpacing.md)
        .background(TremorColor.ink,
                    in: RoundedRectangle(cornerRadius: TremorRadius.thumbnail, style: .continuous))
        .tremorShadow(.lifted)
        .contentShape(Rectangle())
        .onTapGesture { onDismiss?() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(message.style.roleLabel). \(message.title)")
        .accessibilityValue(message.message ?? "")
        .accessibilityHint(onDismiss == nil ? "" : "Double tap to dismiss")
    }
}

private struct ToastHost: ViewModifier {
    @Binding var message: TremorToastMessage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message {
                    TremorToast(message) { dismiss() }
                        .padding(.horizontal, TremorSpacing.md)
                        .padding(.top, TremorSpacing.xs)
                        .transition(transition)
                        .gesture(
                            DragGesture(minimumDistance: TremorSpacing.xs)
                                .onEnded { gesture in
                                    if gesture.translation.height < -TremorSpacing.xs { dismiss() }
                                }
                        )
                        .task(id: message.id) {
                            // Announce first — VoiceOver users get the text even
                            // though the toast never takes focus.
                            AccessibilityNotification
                                .Announcement("\(message.style.roleLabel). \(message.title)")
                                .post()
                            Haptics.notify(message.style.haptic)
                            let nanoseconds = UInt64(max(0, message.duration) * 1_000_000_000)
                            try? await Task.sleep(nanoseconds: nanoseconds)
                            guard !Task.isCancelled else { return }
                            dismiss()
                        }
                }
            }
            .animation(Motion.animation(TremorMotion.reveal, reduceMotion: reduceMotion), value: message?.id)
    }

    private var transition: AnyTransition {
        reduceMotion
            ? .opacity
            : .move(edge: .top).combined(with: .opacity)
    }

    private func dismiss() {
        withAnimation(Motion.animation(TremorMotion.dismiss, reduceMotion: reduceMotion)) {
            message = nil
        }
    }
}

extension View {
    /// Hosts a toast at the top of this view: slide-in, auto-dismiss,
    /// swipe-up-to-dismiss, tap-to-dismiss, haptic and VoiceOver announcement.
    ///
    /// ```swift
    /// @State private var toast: TremorToastMessage?
    /// ...
    /// .tremorToast($toast)
    /// ...
    /// toast = TremorToastMessage("Room saved")
    /// ```
    ///
    /// Setting a new message while one is visible replaces it and re-arms the
    /// timer. Apply this once, at the top of a screen.
    func tremorToast(_ message: Binding<TremorToastMessage?>) -> some View {
        modifier(ToastHost(message: message))
    }
}

#Preview("TremorToast") {
    struct Host: View {
        @State private var toast: TremorToastMessage?

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: TremorSpacing.md) {
                    TremorSectionHeader("Live — tap to present, then tap or swipe up to dismiss")

                    TremorCard(padding: 0) {
                        VStack(spacing: 0) {
                            TremorListRow(title: "Present success", leading: .icon("checkmark.circle")) {
                                toast = TremorToastMessage("Room saved")
                            }
                            TremorRowDivider()
                            TremorListRow(title: "Present info with body", leading: .icon("info.circle")) {
                                toast = TremorToastMessage("Simulation queued",
                                                          message: "Results appear as soon as the solver finishes.",
                                                          style: .info)
                            }
                            TremorRowDivider()
                            TremorListRow(title: "Present warning", leading: .icon("exclamationmark.triangle")) {
                                toast = TremorToastMessage("Partial scan",
                                                          message: "One wall is missing.",
                                                          style: .warning)
                            }
                            TremorRowDivider()
                            TremorListRow(title: "Present error, long text", leading: .icon("xmark.octagon")) {
                                toast = TremorToastMessage("Couldn’t save the recording",
                                                          message: "proof needs permission to add videos to your photo library. You can grant it in Settings, then try exporting the simulation again.",
                                                          style: .error,
                                                          duration: 6)
                            }
                        }
                    }

                    TremorSectionHeader("Static — every style")
                    TremorToast(TremorToastMessage("Room saved"))
                    TremorToast(TremorToastMessage("Simulation queued",
                                                 message: "Results appear as soon as the solver finishes.",
                                                 style: .info))
                    TremorToast(TremorToastMessage("Partial scan", message: "One wall is missing.", style: .warning))
                    TremorToast(TremorToastMessage("Couldn’t save the recording",
                                                 message: "proof needs permission to add videos to your photo library.",
                                                 style: .error))
                }
                .padding(.vertical, TremorSpacing.xl)
            }
            .tremorScreen()
            .tremorToast($toast)
        }
    }
    return Host()
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - TremorSheet
// ─────────────────────────────────────────────────────────────────────────────

/// A trailing action in a sheet header — Lyft's right-aligned interactive text
/// (design-lyft.md §6.4).
struct TremorSheetAction {
    let title: String
    let hint: String?
    let action: () -> Void

    init(title: String, hint: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.hint = hint
        self.action = action
    }
}

/// How a `TremorSheet` supplies its own chrome.
enum TremorSheetPresentation {
    /// The sheet draws its own rounded top corners, fill and `panel` glow. Use
    /// when it is composed into a `ZStack` over the 3D viewport rather than
    /// presented modally.
    case inline
    /// The system presents it; corners, fill and scrim come from
    /// `presentationCornerRadius` / `presentationBackground`, so the sheet must
    /// not draw them again.
    case modal
}

/// The Lyft bottom sheet.
///
/// Anatomy, top to bottom, straight from design-lyft.md §6.4:
///
/// 1. **Grabber** — 36 × 4pt pill, ink @ 20%, 8pt from the sheet top.
/// 2. **Header** — 24pt top padding below the grabber, title plus an optional
///    right-aligned interactive action.
/// 3. **Content** — the scrollable body.
/// 4. **Footer / CTA dock** — pinned, non-scrolling, with a 1pt hairline that
///    **appears only once content scrolls under it**. That hairline is the
///    detail that makes a docked CTA feel native rather than stuck on.
///
/// The container is `panel`-elevated: an omnidirectional glow, not a drop
/// shadow, so the sheet floats off the viewport in every direction.
///
/// ```swift
/// TremorSheet(title: "Simulation") {
///     ...controls...
/// } footer: {
///     TremorSheetPrimaryAction(title: "Run") { run() }
/// }
/// ```
///
/// For a modal presentation use `.tremorSheet(isPresented:)`, which wraps this in
/// SwiftUI's detent machinery so every sheet in the app is visually identical.
struct TremorSheet<Content: View, Footer: View>: View {

    private let title: String?
    private let subtitle: String?
    private let showsGrabber: Bool
    private let scrolls: Bool
    private let presentation: TremorSheetPresentation
    private let gutter: CGFloat
    private let action: TremorSheetAction?
    private let content: Content
    private let footer: Footer

    @State private var isScrolled = false

    init(title: String? = nil,
                subtitle: String? = nil,
                showsGrabber: Bool = true,
                scrolls: Bool = true,
                presentation: TremorSheetPresentation = .inline,
                gutter: CGFloat = TremorSpacing.lg,   // = Metric.sheetGutter
                action: TremorSheetAction? = nil,
                @ViewBuilder content: () -> Content,
                @ViewBuilder footer: () -> Footer) {
        self.title = title
        self.subtitle = subtitle
        self.showsGrabber = showsGrabber
        self.scrolls = scrolls
        self.presentation = presentation
        self.gutter = gutter
        self.action = action
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsGrabber { grabber }
            if title != nil || action != nil { header }
            body(for: content)
            footerDock
        }
        .frame(maxWidth: .infinity)
        .background(sheetBackground)
        .accessibilityElement(children: .contain)
    }

    // MARK: Pieces

    private var grabber: some View {
        RoundedRectangle(cornerRadius: Metric.grabberRadius, style: .continuous)
            .fill(Wash.grabber)
            .frame(width: TremorSize.grabberWidth, height: TremorSize.grabberHeight)
            .padding(.top, TremorSpacing.xs)
            .accessibilityHidden(true)
    }

    private var header: some View {
        // The title shares its line with the trailing action; the subtitle drops
        // below and takes the full gutter width, so a short action can never
        // squeeze a supporting line into a narrow column.
        VStack(alignment: .leading, spacing: TremorSpacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: TremorSpacing.sm) {
                if let title {
                    Text(title)
                        .tremorType(.title2)
                        .foregroundStyle(TremorColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                } else {
                    Spacer(minLength: 0)
                }

                if let action {
                    Button(action: action.action) {
                        Text(action.title)
                            .tremorType(.subheadline)
                            .foregroundStyle(TremorColor.primary)
                            .padding(.horizontal, TremorSpacing.xs)
                            .padding(.vertical, TremorSpacing.xxs)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle(shape: AnyShape(Capsule()), wash: TremorColor.focusRing))
                    .accessibilityHint(action.hint ?? "")
                    .fixedSize()
                }
            }

            if let subtitle {
                Text(subtitle)
                    .tremorType(.callout)
                    .foregroundStyle(TremorColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, gutter)
        .padding(.top, TremorSpacing.xl)
    }

    @ViewBuilder
    private func body(for content: Content) -> some View {
        if scrolls {
            ScrollView {
                content
                    .padding(.horizontal, gutter)
                    .padding(.top, TremorSpacing.lg)
                    .padding(.bottom, TremorSpacing.md)
                    .background(scrollProbe)
            }
            .coordinateSpace(name: Self.scrollSpace)
            .scrollBounceBehavior(.basedOnSize)
            .onPreferenceChange(SheetScrollOffsetKey.self) { offset in
                isScrolled = offset < -TremorSize.hairline
            }
        } else {
            content
                .padding(.horizontal, gutter)
                .padding(.top, TremorSpacing.lg)
                .padding(.bottom, TremorSpacing.md)
        }
    }

    private var scrollProbe: some View {
        GeometryReader { geometry in
            Color.clear.preference(
                key: SheetScrollOffsetKey.self,
                value: geometry.frame(in: .named(Self.scrollSpace)).minY
            )
        }
    }

    @ViewBuilder
    private var footerDock: some View {
        if Footer.self != EmptyView.self {
            VStack(spacing: 0) {
                // Lyft: the hairline appears only once content scrolls under it.
                Rectangle()
                    .fill(TremorColor.divider)
                    .frame(height: TremorSize.hairline)
                    .opacity(isScrolled ? 1 : 0)

                footer
                    .padding(.horizontal, gutter)
                    .padding(.top, TremorSpacing.md)
                    .padding(.bottom, TremorSpacing.ctaBottomInset)
            }
            .background(TremorColor.surface)
        }
    }

    @ViewBuilder
    private var sheetBackground: some View {
        switch presentation {
        case .inline:
            UnevenRoundedRectangle(topLeadingRadius: TremorRadius.sheet,
                                   bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 0,
                                   topTrailingRadius: TremorRadius.sheet,
                                   style: .continuous)
                .fill(TremorColor.surface)
                .tremorShadow(.panel)
                .ignoresSafeArea(edges: .bottom)
        case .modal:
            // The system draws the corners and the fill; drawing them again
            // produces a visible double edge at the top radius.
            Color.clear
        }
    }

    private static var scrollSpace: String { "TremorSheetScroll" }
}

private struct SheetScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

extension TremorSheet where Footer == EmptyView {
    /// A sheet with no docked footer.
    init(title: String? = nil,
         subtitle: String? = nil,
         showsGrabber: Bool = true,
         scrolls: Bool = true,
         presentation: TremorSheetPresentation = .inline,
         gutter: CGFloat = TremorSpacing.lg,   // = Metric.sheetGutter
         action: TremorSheetAction? = nil,
         @ViewBuilder content: () -> Content) {
        self.init(title: title,
                  subtitle: subtitle,
                  showsGrabber: showsGrabber,
                  scrolls: scrolls,
                  presentation: presentation,
                  gutter: gutter,
                  action: action,
                  content: content,
                  footer: { EmptyView() })
    }
}

/// The full-width 56pt pill for a sheet's CTA dock, so every sheet's primary
/// action is identical without depending on the button family's API.
struct TremorSheetPrimaryAction: View {
    private let title: String
    private let hint: String?
    private let action: () -> Void

    init(title: String, hint: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.hint = hint
        self.action = action
    }

    var body: some View {
        PillAction(title: title, hint: hint, action: action)
    }
}

// MARK: Modal presentation

private struct TremorSheetModifier<SheetContent: View, SheetFooter: View>: ViewModifier {
    @Binding var isPresented: Bool
    let detents: Set<PresentationDetent>
    let selection: Binding<PresentationDetent>?
    let title: String?
    let subtitle: String?
    let action: TremorSheetAction?
    let showsGrabber: Bool
    let allowsBackgroundInteraction: Bool
    let sheetContent: () -> SheetContent
    let sheetFooter: () -> SheetFooter

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            TremorSheet(title: title,
                       subtitle: subtitle,
                       showsGrabber: showsGrabber,
                       presentation: .modal,
                       action: action,
                       content: sheetContent,
                       footer: sheetFooter)
                .presentationDragIndicator(.hidden)   // we draw Lyft's grabber
                .presentationCornerRadius(TremorRadius.sheet)
                .presentationBackground(TremorColor.surface)
                .modifier(DetentModifier(detents: detents, selection: selection))
                .modifier(BackgroundInteractionModifier(enabled: allowsBackgroundInteraction,
                                                        detents: detents))
        }
    }
}

private struct DetentModifier: ViewModifier {
    let detents: Set<PresentationDetent>
    let selection: Binding<PresentationDetent>?

    func body(content: Content) -> some View {
        if let selection {
            content.presentationDetents(detents, selection: selection)
        } else {
            content.presentationDetents(detents)
        }
    }
}

/// Lyft's scrim rule: the sheet only dims what is behind it once it is expanded.
/// Enabling background interaction up through the *smallest* detent reproduces
/// that — small detents leave the viewport live and un-dimmed, and the scrim
/// fades in as the sheet grows past it.
private struct BackgroundInteractionModifier: ViewModifier {
    let enabled: Bool
    let detents: Set<PresentationDetent>

    func body(content: Content) -> some View {
        if enabled, let smallest = smallestDetent {
            content.presentationBackgroundInteraction(.enabled(upThrough: smallest))
        } else {
            content
        }
    }

    private var smallestDetent: PresentationDetent? {
        if detents.contains(.height(TremorSize.rowRich)) { return .height(TremorSize.rowRich) }
        if detents.contains(.fraction(0.3)) { return .fraction(0.3) }
        if detents.contains(.medium) { return .medium }
        return nil
    }
}

extension View {

    /// Present a visually standard Tremor sheet.
    ///
    /// Built on `presentationDetents` so drag physics, rubber-banding and
    /// velocity snapping stay native, but wrapped so the grabber, radius, fill,
    /// header and gutters are identical everywhere.
    ///
    /// - Parameters:
    ///   - detents: `[.medium, .large]` by default. Include a small detent (e.g.
    ///     `.fraction(0.3)`) for a peek state over the 3D viewport.
    ///   - selection: bind this to drive or observe the detent.
    ///   - allowsBackgroundInteraction: when true, the content behind stays live
    ///     and un-dimmed at the smallest detent, and the scrim fades in as the
    ///     sheet expands — the Lyft behaviour.
    func tremorSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        detents: Set<PresentationDetent> = [.medium, .large],
        selection: Binding<PresentationDetent>? = nil,
        title: String? = nil,
        subtitle: String? = nil,
        action: TremorSheetAction? = nil,
        showsGrabber: Bool = true,
        allowsBackgroundInteraction: Bool = false,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        modifier(TremorSheetModifier(isPresented: isPresented,
                                    detents: detents,
                                    selection: selection,
                                    title: title,
                                    subtitle: subtitle,
                                    action: action,
                                    showsGrabber: showsGrabber,
                                    allowsBackgroundInteraction: allowsBackgroundInteraction,
                                    sheetContent: content,
                                    sheetFooter: { EmptyView() }))
    }

    /// The same sheet with a pinned CTA dock. The dock does not scroll, and its
    /// top hairline appears only once content passes under it.
    func tremorSheet<SheetContent: View, SheetFooter: View>(
        isPresented: Binding<Bool>,
        detents: Set<PresentationDetent> = [.medium, .large],
        selection: Binding<PresentationDetent>? = nil,
        title: String? = nil,
        subtitle: String? = nil,
        action: TremorSheetAction? = nil,
        showsGrabber: Bool = true,
        allowsBackgroundInteraction: Bool = false,
        @ViewBuilder content: @escaping () -> SheetContent,
        @ViewBuilder footer: @escaping () -> SheetFooter
    ) -> some View {
        modifier(TremorSheetModifier(isPresented: isPresented,
                                    detents: detents,
                                    selection: selection,
                                    title: title,
                                    subtitle: subtitle,
                                    action: action,
                                    showsGrabber: showsGrabber,
                                    allowsBackgroundInteraction: allowsBackgroundInteraction,
                                    sheetContent: content,
                                    sheetFooter: footer))
    }

    /// The scrim, for inline sheet compositions where the system is not
    /// supplying one: ink @ 30%, fading in over `reveal` and out over `dismiss`
    /// (design-lyft.md §8: 300ms in, 250ms out).
    func tremorScrim(isVisible: Bool, onTap: (() -> Void)? = nil) -> some View {
        modifier(ScrimModifier(isVisible: isVisible, onTap: onTap))
    }
}

private struct ScrimModifier: ViewModifier {
    let isVisible: Bool
    let onTap: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            TremorColor.scrim
                .ignoresSafeArea()
                .opacity(isVisible ? 1 : 0)
                .allowsHitTesting(isVisible)
                .onTapGesture { onTap?() }
                .accessibilityHidden(!isVisible)
                .accessibilityLabel("Dismiss")
                .accessibilityAddTraits(onTap == nil ? [] : .isButton)
                .animation(Motion.animation(isVisible ? TremorMotion.reveal : TremorMotion.dismiss,
                                            reduceMotion: reduceMotion),
                           value: isVisible)
        }
    }
}

#Preview("TremorSheet — inline") {
    struct Host: View {
        @State private var magnitude: Double = 6.5
        @State private var scrimVisible = false

        var body: some View {
            ZStack(alignment: .bottom) {
                // Stand-in for the 3D viewport.
                LinearGradient(colors: [TremorColor.surfaceSunken, TremorColor.canvas],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                    .overlay(alignment: .top) {
                        Text("3D viewport")
                            .tremorType(.overline)
                            .foregroundStyle(TremorColor.inkTertiary)
                            .padding(.top, TremorSpacing.section)
                    }
                    .tremorScrim(isVisible: scrimVisible) { scrimVisible = false }

                TremorSheet(title: "Simulation",
                           subtitle: "Magnitude \(magnitude.formatted(.number.precision(.fractionLength(1))))",
                           action: TremorSheetAction(title: "Reset", hint: "Restores the default event") {
                               magnitude = 6.5
                           }) {
                    VStack(alignment: .leading, spacing: TremorSpacing.md) {
                        TremorBanner("Estimated weights", message: "Numbers are indicative.", kind: .info)
                        ForEach(["Bookcase", "Television", "Floor lamp", "Coffee table", "Dresser"], id: \.self) { name in
                            TremorListRow(title: name,
                                         subtitle: "Tap to inspect",
                                         leading: .iconWell("cube.fill"),
                                         accessory: .chevron) {}
                        }
                        Button("Toggle scrim") { scrimVisible.toggle() }
                            .tremorType(.subheadline)
                            .foregroundStyle(TremorColor.primary)
                    }
                } footer: {
                    TremorSheetPrimaryAction(title: "Run the earthquake",
                                            hint: "Starts the simulation") {}
                }
                .frame(height: TremorSpacing.hero * 6)
            }
            .background(TremorColor.canvas)
        }
    }
    return Host()
}

#Preview("TremorSheet — modal detents") {
    struct Host: View {
        @State private var showsPlain = false
        @State private var showsDocked = false
        @State private var detent: PresentationDetent = .medium

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: TremorSpacing.md) {
                    TremorSectionHeader("Modal presentation")
                    TremorCard(padding: 0) {
                        VStack(spacing: 0) {
                            TremorListRow(title: "Plain sheet",
                                         subtitle: "medium + large, scrolling content",
                                         leading: .icon("rectangle.portrait.bottomhalf.filled"),
                                         accessory: .chevron) { showsPlain = true }
                            TremorRowDivider()
                            TremorListRow(title: "Sheet with a docked CTA",
                                         subtitle: "peek + medium + large, background stays live",
                                         leading: .icon("rectangle.inset.bottomthird.filled"),
                                         accessory: .chevron) { showsDocked = true }
                        }
                    }
                }
                .padding(.vertical, TremorSpacing.xl)
            }
            .tremorScreen()
            .tremorSheet(isPresented: $showsPlain,
                        title: "About this report",
                        subtitle: "How proof decides what is unsafe") {
                VStack(alignment: .leading, spacing: TremorSpacing.md) {
                    ForEach(0..<8, id: \.self) { index in
                        Text("Paragraph \(index + 1). proof models each object as a rigid block on a frictional floor and integrates its response to the synthesised ground motion.")
                            .tremorType(.body)
                            .foregroundStyle(TremorColor.inkSecondary)
                    }
                }
            }
            .tremorSheet(isPresented: $showsDocked,
                        detents: [.fraction(0.3), .medium, .large],
                        selection: $detent,
                        title: "Choose an event",
                        action: TremorSheetAction(title: "Reset") { detent = .medium },
                        allowsBackgroundInteraction: true) {
                VStack(spacing: 0) {
                    ForEach(["Magnitude 5.0 — light", "Magnitude 6.0 — strong", "Magnitude 6.5 — severe", "Magnitude 7.2 — violent"], id: \.self) { title in
                        TremorListRow(title: title,
                                     subtitle: "Synthesised accelerogram",
                                     leading: .iconWell("waveform.path.ecg"),
                                     accessory: .chevron) {}
                        TremorRowDivider()
                    }
                }
            } footer: {
                TremorSheetPrimaryAction(title: "Run the earthquake") { showsDocked = false }
            }
        }
    }
    return Host()
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - TremorNavBar
// ─────────────────────────────────────────────────────────────────────────────

/// A leading or trailing bar item: 24pt glyph in a 44pt tap target, 16pt from
/// the edge (design-lyft.md §6.6).
struct TremorNavBarItem: Identifiable {
    let id = UUID()
    let systemImage: String
    let label: String
    let hint: String?
    let action: () -> Void

    /// - Parameters:
    ///   - label: the accessibility label. An icon-only control is invisible to
    ///     VoiceOver without one, so it is required, not optional.
    init(systemImage: String,
                label: String,
                hint: String? = nil,
                action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.label = label
        self.hint = hint
        self.action = action
    }
}

/// The custom top bar, with Lyft's large-title-to-inline collapse.
///
/// design-lyft.md §6.6: 56pt bar; no shadow at rest with a 1pt hairline that
/// appears on scroll; large-title variant set in the display face, left aligned,
/// collapsing to the centred inline title as the user scrolls.
///
/// Drive `collapseProgress` yourself (0 = fully expanded, 1 = fully collapsed),
/// or use `TremorNavBarScrollView`, which computes it from its own scroll offset.
struct TremorNavBar: View {

    private let title: String
    private let subtitle: String?
    private let collapseProgress: Double
    private let leading: TremorNavBarItem?
    private let trailing: TremorNavBarItem?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(title: String,
                subtitle: String? = nil,
                collapseProgress: Double = 0,
                leading: TremorNavBarItem? = nil,
                trailing: TremorNavBarItem? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.collapseProgress = collapseProgress
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        VStack(spacing: 0) {
            inlineBar
            largeTitleBlock
        }
        .background(TremorColor.canvas)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TremorColor.divider)
                .frame(height: TremorSize.hairline)
                .opacity(progress)
        }
    }

    // MARK: Pieces

    private var inlineBar: some View {
        ZStack {
            Text(title)
                .tremorType(.headline)
                .foregroundStyle(TremorColor.ink)
                .lineLimit(1)
                .padding(.horizontal, TremorSize.minimumTapTarget + TremorSpacing.md)
                // The inline title only exists once the large one has gone, and
                // it duplicates it — so it is hidden from VoiceOver entirely.
                .opacity(inlineTitleOpacity)
                .accessibilityHidden(true)

            HStack(spacing: 0) {
                itemButton(leading)
                Spacer(minLength: 0)
                itemButton(trailing)
            }
            .padding(.horizontal, TremorSpacing.md)
        }
        .frame(height: TremorSize.topBar)
    }

    private var largeTitleBlock: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.xxs) {
            Text(title)
                .tremorType(.title1)
                .foregroundStyle(TremorColor.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .tremorType(.footnote)
                    .foregroundStyle(TremorColor.inkTertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, TremorSpacing.pageInset)
        .padding(.bottom, TremorSpacing.md)
        .opacity(1 - min(1, progress * 1.6))
        .frame(height: expandedHeight * (1 - progress), alignment: .top)
        .clipped()
    }

    @ViewBuilder
    private func itemButton(_ item: TremorNavBarItem?) -> some View {
        if let item {
            Button(action: item.action) {
                Image(systemName: item.systemImage)
                    .font(.system(size: Metric.icon, weight: .medium))
                    .foregroundStyle(TremorColor.ink)
                    .frame(width: TremorSize.minimumTapTarget, height: TremorSize.minimumTapTarget)
                    .contentShape(Circle())
            }
            .buttonStyle(PressStyle(shape: AnyShape(Circle()), scales: false))
            .accessibilityLabel(item.label)
            .modifier(OptionalHint(hint: item.hint))
        } else {
            Color.clear
                .frame(width: TremorSize.minimumTapTarget, height: TremorSize.minimumTapTarget)
                .accessibilityHidden(true)
        }
    }

    // MARK: Geometry

    private var progress: Double { min(1, max(0, collapseProgress)) }

    /// The inline title only fades in over the last 40% of the collapse, so the
    /// two titles are never both fully visible.
    private var inlineTitleOpacity: Double { max(0, (progress - 0.6) / 0.4) }

    private var expandedHeight: CGFloat {
        Self.largeTitleHeight(hasSubtitle: subtitle != nil, dynamicTypeSize: dynamicTypeSize)
    }

    /// The height the large-title block occupies when fully expanded — line
    /// heights straight from the type ramp, so it stays correct at every
    /// Dynamic Type size.
    static func largeTitleHeight(hasSubtitle: Bool,
                                        dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        var height = TremorType.title1.spec.scaledLineHeight(for: dynamicTypeSize)
        if hasSubtitle {
            height += TremorSpacing.xxs + TremorType.footnote.spec.scaledLineHeight(for: dynamicTypeSize)
        }
        return height + TremorSpacing.md
    }
}

/// A screen scaffold: `TremorNavBar` over a scroll view, with the collapse driven
/// automatically by the scroll offset.
///
/// ```swift
/// TremorNavBarScrollView(title: "Your rooms",
///                       trailing: .init(systemImage: "plus", label: "New scan") { scan() }) {
///     ...
/// }
/// ```
struct TremorNavBarScrollView<Content: View>: View {

    private let title: String
    private let subtitle: String?
    private let leading: TremorNavBarItem?
    private let trailing: TremorNavBarItem?
    private let inset: CGFloat
    private let content: Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var offset: CGFloat = 0

    init(title: String,
                subtitle: String? = nil,
                leading: TremorNavBarItem? = nil,
                trailing: TremorNavBarItem? = nil,
                inset: CGFloat = TremorSpacing.pageInset,
                @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.leading = leading
        self.trailing = trailing
        self.inset = inset
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            TremorNavBar(title: title,
                        subtitle: subtitle,
                        collapseProgress: progress,
                        leading: leading,
                        trailing: trailing)

            ScrollView {
                content
                    .padding(.horizontal, inset)
                    .padding(.bottom, TremorSpacing.xxl)
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: NavBarScrollOffsetKey.self,
                                value: geometry.frame(in: .named(Self.space)).minY
                            )
                        }
                    )
            }
            .coordinateSpace(name: Self.space)
            .onPreferenceChange(NavBarScrollOffsetKey.self) { offset = $0 }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(TremorColor.canvas.ignoresSafeArea())
    }

    private var progress: Double {
        let distance = TremorNavBar.largeTitleHeight(hasSubtitle: subtitle != nil,
                                                    dynamicTypeSize: dynamicTypeSize)
        guard distance > 0 else { return 0 }
        return min(1, max(0, Double(-offset / distance)))
    }

    private static var space: String { "TremorNavBarScroll" }
}

private struct NavBarScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

#Preview("TremorNavBar") {
    TremorNavBarScrollView(
        title: "Your rooms",
        subtitle: "3 scanned · 7 objects need attention",
        leading: TremorNavBarItem(systemImage: "line.3.horizontal",
                                 label: "Menu",
                                 hint: "Opens the app menu") {},
        trailing: TremorNavBarItem(systemImage: "plus",
                                  label: "New scan",
                                  hint: "Starts scanning a new room") {}
    ) {
        VStack(alignment: .leading, spacing: TremorSpacing.md) {
            TremorSectionHeader("Scroll to collapse the large title")
            ForEach(0..<12, id: \.self) { index in
                TremorCard.tappable(accessibilityHint: "Opens the room") {} content: {
                    HStack {
                        VStack(alignment: .leading, spacing: TremorSpacing.xxs) {
                            Text("Room \(index + 1)").tremorType(.title3).foregroundStyle(TremorColor.ink)
                            Text("14 objects · 2 unsafe")
                                .tremorType(.footnote).foregroundStyle(TremorColor.inkTertiary)
                        }
                        Spacer()
                        RiskChip(band: TremorRiskBand.allCases[index % TremorRiskBand.allCases.count])
                    }
                }
            }
        }
        .padding(.top, TremorSpacing.md)
    }
}

#Preview("TremorNavBar — collapse states") {
    VStack(spacing: TremorSpacing.xl) {
        ForEach([0.0, 0.5, 1.0], id: \.self) { progress in
            VStack(alignment: .leading, spacing: 0) {
                Text("collapseProgress \(progress.formatted(.number.precision(.fractionLength(1))))")
                    .tremorType(.overline)
                    .foregroundStyle(TremorColor.inkTertiary)
                    .padding(.horizontal, TremorSpacing.pageInset)
                TremorNavBar(title: "Living room",
                            subtitle: "14 objects",
                            collapseProgress: progress,
                            leading: TremorNavBarItem(systemImage: "chevron.left", label: "Back") {},
                            trailing: TremorNavBarItem(systemImage: "ellipsis", label: "More options") {})
            }
        }

        VStack(alignment: .leading, spacing: 0) {
            Text("no subtitle, long title, no items")
                .tremorType(.overline)
                .foregroundStyle(TremorColor.inkTertiary)
                .padding(.horizontal, TremorSpacing.pageInset)
            TremorNavBar(title: "Earthquake readiness report for the living room")
        }

        Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(TremorColor.canvas.ignoresSafeArea())
}
