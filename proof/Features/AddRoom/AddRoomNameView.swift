//
//  AddRoomNameView.swift
//  proof — Add Room, step 1
//
//  The first screen of the consumer path, and the only one that asks for anything.
//
//  It asks for one thing: what to call the room. Not the building type, not the floor, not
//  the construction year — those matter to the physics, but asking for them here would put
//  a form between a new user and the thing they came to see. They are asked later, or
//  defaulted, and this screen stays a single field.
//
//  The suggestion chips are the real input. Four names cover most of a home, and tapping
//  one fills the field *and* dismisses the keyboard so the primary action is immediately
//  visible — a two-tap path from opening the tab to the camera. The keyboard focuses on
//  appear for the people who want to type something else, and the return key advances, so
//  the button is never the only way forward.
//
//  TWO THINGS HERE ARE CORRECTIONS, AND BOTH CAME FROM WATCHING SOMEONE USE IT
//  ---------------------------------------------------------------------------
//  1. **Focus is gated on `isActive`, not on `onAppear`.** The shell keeps all three tab
//     roots alive in a `ZStack` so switching tabs preserves state — which means this view
//     "appears" during the app's cold launch, while the user is looking at the Rooms
//     dashboard. Focusing from `onAppear` therefore raised the software keyboard over a
//     screen this file does not own, on every single launch, before anyone had touched
//     anything. The field takes first responder only while the Add Room tab is the
//     selected one, and gives it up the moment the user leaves.
//
//  2. **The CTA is a docked bottom bar, not the last item in a column.** As a column
//     member it was laid out below the keyboard — invisible in the state the screen spends
//     most of its life in — and the copy above it was being compressed to a single
//     truncated line to make room. Scrolling content plus a `safeAreaInset` bar means the
//     button sits above the keyboard and above the tab bar in every combination, and the
//     sentence that explains the whole flow is never the thing that gets squeezed.
//

import SwiftUI

struct AddRoomNameView: View {

    @Binding var name: String
    /// Suggestions offered as chips. Injected so a preview can show a different set.
    var suggestions: [String] = AddRoomFlowModel.suggestedNames
    /// True only while this screen is the one the user is actually looking at. The shell
    /// builds every tab root at launch, so "on screen" and "appeared" are different facts
    /// here, and only the first of them may raise a keyboard.
    var isActive: Bool = true
    var onStart: () -> Void

    @FocusState private var isFocused: Bool

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canStart: Bool { !trimmed.isEmpty }

    var body: some View {
        // A column of "scroller + docked bar", not a `safeAreaInset` on the scroller.
        //
        // `safeAreaInset` was the obvious way to dock the button and it put it *underneath*
        // the tab bar: the shell supplies the tab bar as its own bottom `safeAreaInset`, and
        // a nested inset is allowed to occupy the region the outer one reserved. A plain
        // `VStack` cannot — its frame ends where the safe area ends — so the button lands
        // above the tab bar, and SwiftUI's keyboard avoidance lifts the whole column when
        // the keyboard arrives.
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    TremorTextField(
                        "Room name",
                        text: $name,
                        placeholder: AddRoomFlowModel.defaultRoomName,
                        helpText: "You'll see this on the room's card and on its checklist.",
                        leadingIcon: "house",
                        submitLabel: .continue,
                        autocapitalization: .sentences,
                        onSubmit: submit)
                    .focused($isFocused)
                    .padding(.top, TremorSpacing.xl)

                    suggestionChips
                        .padding(.top, TremorSpacing.md)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, TremorSpacing.pageInset)
                .padding(.bottom, TremorSpacing.xl)
                // Anywhere on the page puts the keyboard away. Without this the only way
                // down was a chip or the return key, and someone who wanted neither was
                // stuck looking at a screen with its bottom half covered.
                .contentShape(Rectangle())
                .onTapGesture { isFocused = false }
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)

            TremorButton(
                "Continue",
                trailingIcon: "arrow.right",
                hint: "Asks what you are getting ready for"
            ) { submit() }
            .disabled(!canStart)
            .padding(.horizontal, TremorSpacing.pageInset)
            .padding(.top, TremorSpacing.sm)
            .padding(.bottom, TremorSpacing.ctaBottomInset)
        }
        // The page inset lives on the scrolling column and on the docked bar separately,
        // so the bar can carry a full-width canvas behind it.
        .tremorScreen(inset: 0)
        // `initial: true` so arriving on an already-selected tab focuses too — that is the
        // case when the user taps Add Room, which is the only time a keyboard here is
        // wanted.
        .onChange(of: isActive, initial: true) { _, active in
            guard active else {
                isFocused = false
                return
            }
            // A beat, so the field is on screen before the keyboard climbs over it —
            // focusing in the same frame as the appear transition drops the animation.
            Task {
                try? await Task.sleep(for: .seconds(Self.focusDelaySeconds))
                guard isActive else { return }
                isFocused = true
            }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.sm) {
            Text("New room")
                .tremorType(.overline)
                .foregroundStyle(TremorColor.inkTertiary)

            Text("Which room are we\nlooking at?")
                .tremorType(.displayM)
                .foregroundStyle(TremorColor.ink)
                .fixedSize(horizontal: false, vertical: true)

            // Fixed vertically for the same reason the display line above it is: this is
            // the sentence that sets the expectation for the whole flow, and it was being
            // truncated to one line whenever the keyboard squeezed the column.
            Text("Give it a name, tell us what you're getting ready for, then film a slow lap of the room. It takes about ten seconds.")
                .tremorType(.body)
                .foregroundStyle(TremorColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, TremorSpacing.xxl)
    }

    /// A wrapping row rather than a scroller: four short chips fit on every phone at the
    /// standard text sizes, and at accessibility sizes they stack instead of hiding half of
    /// themselves off the trailing edge.
    private var suggestionChips: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.xs) {
            Text("Or pick one")
                .tremorType(.footnote)
                .foregroundStyle(TremorColor.inkTertiary)

            TremorChipFlow(spacing: TremorSpacing.xs) {
                ForEach(suggestions, id: \.self) { suggestion in
                    TremorChip(
                        suggestion,
                        isSelected: trimmed.caseInsensitiveCompare(suggestion) == .orderedSame
                    ) {
                        name = suggestion
                        // The answer is complete, so the keyboard has nothing left to do.
                        isFocused = false
                    }
                }
            }
        }
    }

    private func submit() {
        guard canStart else { return }
        isFocused = false
        onStart()
    }

    private static let focusDelaySeconds: Double = 0.35
}

// MARK: - Chip flow

/// A left-aligned wrapping row.
///
/// SwiftUI has no wrapping stack, and a `ScrollView(.horizontal)` would hide chips at
/// accessibility text sizes — the sizes where the labels are longest and the shortcut
/// matters most. Twenty lines of `Layout` is cheaper than that trade.
private struct TremorChipFlow: Layout {

    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let rows = layout(subviews: subviews, width: width)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        for row in layout(subviews: subviews, width: bounds.width) {
            subviews[row.index].place(
                at: CGPoint(x: bounds.minX + row.x, y: bounds.minY + row.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: row.width, height: row.height))
        }
    }

    private struct Placement {
        var index: Int
        var x: CGFloat
        var y: CGFloat
        var width: CGFloat
        var height: CGFloat
    }

    private func layout(subviews: Subviews, width: CGFloat) -> [Placement] {
        var placements: [Placement] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            placements.append(
                Placement(index: index, x: x, y: y, width: size.width, height: size.height))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return placements
    }
}

// MARK: - Previews

#Preview("Add room — naming") {
    AddRoomNameView(name: .constant("")) {}
}

#Preview("Add room — named") {
    AddRoomNameView(name: .constant("Kitchen")) {}
}
