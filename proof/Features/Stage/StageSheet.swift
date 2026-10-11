//
//  StageSheet.swift
//  Tremor — the one sheet that carries S-12, S-13, S-14 and S-15
//
//  SPEC §2.7.4 gives four detents:
//
//      .peek    180 pt fixed   S-12 idle
//      .medium  0.58           S-13 configurator
//      .large   0.92 (top inset 44 pt, the stage stays visible)   S-15 report
//      .hidden  0              S-14 (the transport bar replaces it)
//
//  The sheet is *inline* rather than a `presentationDetents` sheet on purpose:
//  it sits in the same `ZStack` as the 3D stage, it never covers the whole
//  screen, and its top edge has to be reportable so the stage camera can keep
//  the room framed in the part of the display that is still visible (Lyft §7.1).
//
//  Everything about where the sheet lands after a drag is a pure function
//  (`StageDetent.settle`), because "the transitions between the four states feel
//  like one continuous surface" is a claim that has to survive a test.
//

import SwiftUI

// MARK: - Detents

/// How far up the screen the stage sheet sits.
enum StageDetent: String, CaseIterable, Hashable, Sendable {
    case hidden
    case peek
    case medium
    case large

    /// SPEC §2.7.4: a fixed 180 pt, not a fraction — the peek shows a room
    /// name, a subtitle and a 56 pt CTA, and that is the same height on every
    /// device.
    static let peekHeight: CGFloat = 180
    static let mediumFraction: CGFloat = 0.58
    static let largeFraction: CGFloat = 0.92
    /// The strip of stage that must stay visible at `.large`.
    static let largeTopInset: CGFloat = 44

    func height(in screenHeight: CGFloat, peek: CGFloat = StageDetent.peekHeight) -> CGFloat {
        guard screenHeight > 0 else { return 0 }
        switch self {
        case .hidden:
            return 0
        case .peek:
            return min(peek, screenHeight)
        case .medium:
            return (screenHeight * Self.mediumFraction).rounded()
        case .large:
            return min(screenHeight * Self.largeFraction, screenHeight - Self.largeTopInset).rounded()
        }
    }

    /// The peek detent is the one fixed-height detent, so it is also the one
    /// that can clip at large text sizes. It grows with the body ramp — capped
    /// at 1.45× by `TremorTypeSpec.textCap`, so it can never swallow the stage.
    static func peekHeight(for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        let spec = TremorType.body.spec
        let factor = spec.scaledSize(for: dynamicTypeSize) / spec.size
        return (peekHeight * factor).rounded()
    }

    /// Fraction of the display this detent covers. The stage camera reframes
    /// against it.
    func fraction(in screenHeight: CGFloat) -> Double {
        guard screenHeight > 0 else { return 0 }
        return Double(height(in: screenHeight) / screenHeight)
    }

    /// The scrim behind the sheet fades in only past `.medium` (SPEC §2.7.4).
    var showsScrim: Bool { self == .large }

    /// Content scrolls only at the sheet's top detent; below it a drag moves
    /// the sheet instead.
    var scrolls: Bool { self == .medium || self == .large }
}

// MARK: - Settlement

/// Where a drag leaves the screen: which of the four sheet states, and which
/// detent inside it.
struct StageSettlement: Equatable, Sendable {
    var phase: AppState.StagePhase
    var detent: StageDetent
}

extension StageDetent {

    /// The detents a given sheet state is allowed to rest at.
    ///
    /// The configurator and the report both list `.peek`/`.medium` below their
    /// resting detent so that dragging *down* is never a dead end: from S-13 it
    /// returns you to the room viewer, from S-15 it lets you see the room the
    /// report is about.
    static func allowed(for phase: AppState.StagePhase) -> [StageDetent] {
        switch phase {
        case .viewer: return [.peek, .medium]
        case .configurator: return [.peek, .medium, .large]
        case .running: return [.hidden]
        case .results: return [.medium, .large]
        }
    }

    /// The detent a sheet state opens at.
    static func resting(for phase: AppState.StagePhase, hasSelection: Bool) -> StageDetent {
        switch phase {
        case .viewer: return hasSelection ? .medium : .peek
        case .configurator: return .medium
        case .running: return .hidden
        case .results: return .large
        }
    }

    /// Where a drag that ended at `height` settles.
    ///
    /// Dragging the configurator down to the peek is a request to leave it, so
    /// it resolves to the room viewer rather than to a 180 pt configurator with
    /// nothing in it.
    static func settle(dragHeight: CGFloat,
                       phase: AppState.StagePhase,
                       screenHeight: CGFloat,
                       peek: CGFloat = StageDetent.peekHeight) -> StageSettlement {
        guard phase != .running else {
            return StageSettlement(phase: .running, detent: .hidden)
        }
        let candidates = allowed(for: phase)
        let nearest = candidates.min {
            abs($0.height(in: screenHeight, peek: peek) - dragHeight)
                < abs($1.height(in: screenHeight, peek: peek) - dragHeight)
        } ?? resting(for: phase, hasSelection: false)

        if phase == .configurator, nearest == .peek {
            return StageSettlement(phase: .viewer, detent: .peek)
        }
        return StageSettlement(phase: phase, detent: nearest)
    }
}

// MARK: - The shell

/// The sheet's chrome: rounded top corners, the `panel` glow, the grabber, and
/// the drag that moves it between detents.
///
/// The drag lives on the grabber strip rather than on the whole sheet. A
/// full-surface drag competes with the report's scroll view and with every
/// button inside it; a 44 pt handle is unambiguous, is what the grabber already
/// promises, and leaves the content free.
struct StageSheetShell<Content: View>: View {

    /// Where the sheet rests when nothing is being dragged.
    let restingHeight: CGFloat
    /// The tallest the sheet may ever be — `.large` for this screen size.
    let maximumHeight: CGFloat
    let isDraggable: Bool
    /// Reports the height a live drag is at, and where it ended.
    let onDrag: (CGFloat) -> Void
    let onDragEnd: (CGFloat) -> Void
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0

    private var currentHeight: CGFloat {
        min(max(restingHeight - dragOffset, 0), maximumHeight)
    }

    var body: some View {
        VStack(spacing: 0) {
            grabberStrip
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
        }
        .frame(height: currentHeight, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(sheetSurface)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: TremorRadius.sheet,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: TremorRadius.sheet,
                style: .continuous)
        )
        .tremorShadow(.panel)
        .animation(
            TremorMotion.resolved(TremorMotion.change, reduceMotion: reduceMotion),
            value: restingHeight)
        .accessibilityElement(children: .contain)
    }

    private var sheetSurface: some View {
        TremorColor.surface
            .ignoresSafeArea(edges: .bottom)
    }

    private var grabberStrip: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: TremorSize.grabberHeight / 2, style: .continuous)
                .fill(TremorColor.ink.opacity(0.20))
                .frame(width: TremorSize.grabberWidth, height: TremorSize.grabberHeight)
                .padding(.top, TremorSpacing.xs)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: TremorSpacing.lg)
        .contentShape(Rectangle())
        .gesture(dragGesture, including: isDraggable ? .all : .none)
        .accessibilityElement()
        .accessibilityLabel("Sheet position")
        .accessibilityHint(isDraggable ? "Drag up or down to resize this panel." : "")
        .accessibilityHidden(!isDraggable)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                dragOffset = value.translation.height
                onDrag(currentHeight)
            }
            .onEnded { value in
                let landed = min(
                    max(restingHeight - value.predictedEndTranslation.height, 0),
                    maximumHeight)
                dragOffset = 0
                onDragEnd(landed)
            }
    }
}

// MARK: - Skeleton

/// The loading treatment used inside the sheet.
///
/// SPEC §2.7.11: `surfaceSunken` blocks with a 1200 ms shimmer, never a spinner
/// in a sheet header.
struct StageSkeletonBlock: View {

    var height: CGFloat
    var width: CGFloat?
    var radius: CGFloat = TremorRadius.sm

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(TremorColor.surfaceSunken)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .overlay {
                if !reduceMotion {
                    GeometryReader { geometry in
                        LinearGradient(
                            colors: [.clear, TremorColor.surface.opacity(0.85), .clear],
                            startPoint: .leading,
                            endPoint: .trailing)
                        .frame(width: geometry.size.width * 0.5)
                        .offset(x: phase * geometry.size.width * 1.5)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
            .accessibilityHidden(true)
    }
}

#Preview("Stage sheet — detents") {
    struct Harness: View {
        @State private var detent: StageDetent = .peek

        var body: some View {
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    TremorColor.ink.ignoresSafeArea()

                    StageSheetShell(
                        restingHeight: detent.height(in: geometry.size.height),
                        maximumHeight: StageDetent.large.height(in: geometry.size.height),
                        isDraggable: true,
                        onDrag: { _ in },
                        onDragEnd: { height in
                            detent = StageDetent.settle(
                                dragHeight: height,
                                phase: .results,
                                screenHeight: geometry.size.height).detent
                        }
                    ) {
                        VStack(alignment: .leading, spacing: TremorSpacing.sm) {
                            Text("Bedroom").tremorType(.title2)
                            StageSkeletonBlock(height: TremorSpacing.md, width: 220)
                            StageSkeletonBlock(height: TremorSpacing.md)
                            Spacer(minLength: 0)
                        }
                        .padding(TremorSpacing.lg)
                    }
                }
            }
        }
    }
    return Harness()
}
