//
//  ProfileSheetView.swift
//  Tremor — Features / Onboarding — S-04
//
//  Presented from Settings (S-19). It is the only screen in the app that can
//  destroy data, so it is built around one idea: say exactly what exists, where
//  it is, and what each button will do to it, before the button is pressed.
//
//  A note on what is *not* here. SPEC lists a "Sync to iCloud" switch. There is
//  no CloudKit in this build — no container, no zone, no sync engine — so the
//  switch would be a control wired to nothing, in the one screen where a user
//  is deciding whether to trust the app with the layout of their bedroom. It is
//  replaced by a plain statement of where the data actually lives, which is the
//  same information the switch was supposed to imply and has the advantage of
//  being true.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ProfileSheetView: View {

    @Environment(\.tremor) private var tremor
    @Environment(Router.self) private var router
    @Environment(AppState.self) private var appState

    @State private var displayName: String = ""
    @State private var roomCount: Int?
    @State private var isConfirmingDelete = false
    @State private var deleteConfirmation = ""
    @State private var isDeleting = false
    @State private var exportState: ExportState = .idle
    @State private var exportPayload: ExportPayload?

    /// The word the user has to type. Uppercase, unambiguous, and not a word
    /// anyone types by accident.
    static let deleteKeyword = "DELETE"

    private enum ExportState: Equatable {
        case idle
        case working
        case failed(String)
    }

    private struct ExportPayload: Identifiable {
        let id = UUID()
        let urls: [URL]
    }

    var body: some View {
        VStack(spacing: 0) {
            TremorNavBar(
                title: "Your account",
                trailing: TremorNavBarItem(
                    systemImage: "xmark",
                    label: "Close",
                    action: { router.dismissSheet() }))

            if let profile = tremor.account.profile {
                content(for: profile)
            } else {
                noProfile
            }
        }
        .tremorScreen(inset: 0)
        .task {
            displayName = tremor.account.profile?.displayName ?? ""
            await loadRoomCount()
        }
        .onDisappear { commitDisplayName() }
        .sheet(item: $exportPayload) { payload in
            ShareActivityView(items: payload.urls)
        }
    }

    // MARK: - No profile

    /// Reachable only if the profile file was deleted underneath us. It is still
    /// a state, so it still gets an exit.
    private var noProfile: some View {
        VStack {
            Spacer(minLength: 0)
            TremorEmptyState(
                title: "There's no profile on this iPhone",
                message: "proof works without one. Create a local profile and your scans, reports and fix-it plans carry on exactly as they are.",
                systemImage: "person.crop.circle.badge.questionmark",
                actionTitle: "Create a local profile",
                actionHint: "Nothing leaves this iPhone",
                action: {
                    tremor.account.continueWithoutAccount()
                    displayName = ""
                })
            Spacer(minLength: 0)
        }
    }

    // MARK: - Content

    private func content(for profile: Profile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TremorSpacing.md) {
                header(for: profile)

                TremorTextField(
                    "Display name",
                    text: $displayName,
                    placeholder: "You",
                    helpText: "Only used on this iPhone and on the reports you export.",
                    submitLabel: .done,
                    autocapitalization: .words,
                    onSubmit: commitDisplayName)

                TremorSectionHeader("Account")
                TremorCard(padding: 0) {
                    VStack(spacing: 0) {
                        TremorListRow(
                            title: profile.kind == .apple ? "Signed in with Apple" : "Local profile",
                            subtitle: profile.kind == .apple
                                ? "Apple gave us an identifier and nothing else."
                                : "No account, no identifier, nothing to sign out of.",
                            leading: .iconWell(profile.kind == .apple ? "apple.logo" : "iphone"))
                        TremorRowDivider()
                        TremorListRow(
                            title: "Email",
                            subtitle: Self.emailDescription(for: profile),
                            leading: .iconWell("envelope"))
                        TremorRowDivider()
                        TremorListRow(
                            title: "Using proof since",
                            subtitle: Self.dateFormatter.string(from: profile.createdAt),
                            leading: .iconWell("calendar"))
                        TremorRowDivider()
                        TremorListRow(
                            title: "Devices",
                            subtitle: "This iPhone. proof has no server, so there is nowhere else for your rooms to be.",
                            leading: .iconWell("iphone.gen3"))
                    }
                }

                TremorSectionHeader("Your data")

                TremorBanner(
                    "Everything is on this iPhone",
                    message: "Your rooms, reports and fix-it plans are files inside proof. They're included in your encrypted iPhone backup, and they go nowhere else unless you export them.",
                    kind: .highlight)

                exportRow

                if profile.kind == .apple { signOutRow }

                deleteSection
            }
            .padding(.horizontal, TremorSpacing.md)
            .padding(.vertical, TremorSpacing.md)
        }
    }

    private func header(for profile: Profile) -> some View {
        HStack(spacing: TremorSpacing.md) {
            Text(profile.avatarInitials)
                .tremorType(.title2)
                .foregroundStyle(TremorColor.primary)
                .frame(width: Metric.avatar, height: Metric.avatar)
                .background(TremorColor.primarySoft, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: TremorSpacing.hair) {
                Text(displayName.isEmpty ? profile.displayTitle : displayName)
                    .tremorType(.title3)
                    .foregroundStyle(TremorColor.ink)
                    .lineLimit(2)
                Text(roomCountDescription)
                    .tremorType(.footnote)
                    .foregroundStyle(TremorColor.inkTertiary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var roomCountDescription: String {
        switch roomCount {
        case .none: return "Counting your rooms…"
        case .some(0): return "No rooms scanned yet"
        case .some(1): return "1 room"
        case .some(let count): return "\(count) rooms"
        }
    }

    // MARK: - Export

    @ViewBuilder
    private var exportRow: some View {
        TremorCard(padding: 0) {
            VStack(spacing: 0) {
                TremorListRow(
                    title: exportState == .working ? "Packing up your rooms…" : "Export all rooms",
                    subtitle: exportTitleSubtitle,
                    leading: .iconWell("square.and.arrow.up"),
                    accessory: exportState == .working
                        ? .custom(AnyView(ProgressView().tint(TremorColor.primary)))
                        : .chevron,
                    accessibilityHint: "Creates one file per room and opens the share sheet",
                    action: { Task { await exportAll() } })
                    .disabled(exportState == .working || roomCount == 0)

                if case .failed(let message) = exportState {
                    TremorRowDivider()
                    TremorBanner(
                        "Export didn't finish",
                        message: message,
                        kind: .warning,
                        actionTitle: "Try again",
                        action: { Task { await exportAll() } })
                    .padding(TremorSpacing.sm)
                }
            }
        }
    }

    private var exportTitleSubtitle: String {
        if roomCount == 0 { return "Nothing to export yet — scan a room first." }
        return "One .tremorroom file per room, with its reports. Openable by proof on any iPhone."
    }

    private func exportAll() async {
        guard exportState != .working else { return }
        exportState = .working
        do {
            let summaries = try await tremor.rooms.list()
            guard !summaries.isEmpty else {
                exportState = .idle
                appState.post("Nothing to export", message: "Scan a room first.", style: .info)
                return
            }
            var urls: [URL] = []
            for summary in summaries {
                if let url = try? await tremor.rooms.export(id: summary.id) { urls.append(url) }
            }
            guard !urls.isEmpty else {
                exportState = .failed("None of your rooms could be packaged. They may be damaged.")
                return
            }
            exportState = .idle
            exportPayload = ExportPayload(urls: urls)
        } catch {
            exportState = .failed(AppState.message(for: error))
        }
    }

    // MARK: - Sign out

    private var signOutRow: some View {
        TremorCard(padding: 0) {
            TremorListRow(
                title: "Sign out of Apple",
                subtitle: "Your rooms, reports and plans stay exactly where they are. They were never tied to the account.",
                leading: .iconWell("rectangle.portrait.and.arrow.right"),
                accessibilityHint: "Removes the Apple identifier from this iPhone",
                action: {
                    tremor.account.signOut()
                    appState.post(
                        "Signed out",
                        message: "Your rooms are still here.",
                        style: .info)
                })
        }
    }

    // MARK: - Delete

    @ViewBuilder
    private var deleteSection: some View {
        if isConfirmingDelete {
            TremorCard(padding: TremorSpacing.md) {
                VStack(alignment: .leading, spacing: TremorSpacing.sm) {
                    HStack(spacing: TremorSpacing.xs) {
                        Image(systemName: "exclamationmark.octagon.fill")
                            .font(.system(size: TremorControlMetrics.glyphMedium))
                            .foregroundStyle(TremorColor.danger)
                            .accessibilityHidden(true)
                        Text("This cannot be undone")
                            .tremorType(.headline)
                            .foregroundStyle(TremorColor.ink)
                    }

                    Text(deleteSummary)
                        .tremorType(.callout)
                        .foregroundStyle(TremorColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Export first if you want to keep any of it.")
                        .tremorType(.footnote)
                        .foregroundStyle(TremorColor.inkTertiary)

                    TremorTextField(
                        "Type \(Self.deleteKeyword) to confirm",
                        text: $deleteConfirmation,
                        placeholder: Self.deleteKeyword,
                        submitLabel: .done,
                        autocapitalization: .characters)
                    .disabled(isDeleting)

                    TremorButton("Delete everything",
                                variant: .destructive,
                                size: .medium,
                                isLoading: isDeleting,
                                hint: "Permanently erases your profile and every room on this iPhone") {
                        Task { await deleteEverything() }
                    }
                    .disabled(!Self.confirmationMatches(deleteConfirmation))

                    TremorButton("Keep my data", variant: .tertiary, size: .medium) {
                        isConfirmingDelete = false
                        deleteConfirmation = ""
                    }
                    .disabled(isDeleting)
                }
            }
        } else {
            TremorCard(padding: 0) {
                TremorListRow(
                    title: "Delete account and all data",
                    subtitle: "Erases your profile, every scanned room and every report on this iPhone.",
                    leading: .iconWell(symbol: "trash", tint: TremorColor.danger,
                                       fill: TremorColor.danger.opacity(0.12)),
                    accessibilityHint: "Asks you to confirm before anything is deleted",
                    action: {
                        deleteConfirmation = ""
                        isConfirmingDelete = true
                    })
            }
        }
    }

    private var deleteSummary: String {
        let rooms: String
        switch roomCount {
        case .none: return "Your profile and everything proof has stored on this iPhone will be erased."
        case .some(0): rooms = "no scanned rooms"
        case .some(1): rooms = "1 scanned room"
        case .some(let count): rooms = "\(count) scanned rooms"
        }
        return "Your profile, \(rooms) and every report and fix-it plan on this iPhone will be erased. There is no copy anywhere else."
    }

    /// Case-sensitive, whitespace-tolerant. A user who types a trailing space
    /// has still made the decision; a user who types "delete" has not proved
    /// they read the word.
    static func confirmationMatches(_ typed: String) -> Bool {
        typed.trimmingCharacters(in: .whitespacesAndNewlines) == deleteKeyword
    }

    private func deleteEverything() async {
        guard Self.confirmationMatches(deleteConfirmation), !isDeleting else { return }
        isDeleting = true
        appState.closeRoom()
        await tremor.account.deleteAccount(alsoErasing: tremor.rooms)
        isDeleting = false
        isConfirmingDelete = false
        deleteConfirmation = ""
        router.dismissSheet()
        appState.post(
            "Everything is deleted",
            message: "Your profile and every room have been erased from this iPhone.",
            style: .info)
    }

    // MARK: - Helpers

    private func commitDisplayName() {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (tremor.account.profile?.displayName ?? "") else { return }
        tremor.account.setDisplayName(trimmed.isEmpty ? nil : trimmed)
    }

    private func loadRoomCount() async {
        roomCount = (try? await tremor.rooms.list())?.count ?? 0
    }

    static func emailDescription(for profile: Profile) -> String {
        if let email = profile.email, !email.isEmpty { return email }
        return profile.kind == .apple
            ? "Hidden. Apple only shares an address the first time you sign in, and only if you allow it."
            : "None. There's no account, so there's nothing to send anywhere."
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()

    private enum Metric {
        static let avatar: CGFloat = 64
    }
}

// MARK: - Share sheet

/// The system share sheet, for the exported room packages.
///
/// A `UIActivityViewController` rather than `ShareLink` because the items are
/// produced by work that has to happen first — `ShareLink` needs its payload at
/// the moment the button is built, and packaging a library of rooms is not
/// something to do on every render.
private struct ShareActivityView: UIViewControllerRepresentable {

    let items: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Previews

#Preview("S-04 local profile") {
    OnboardingPreviewHost(env: .makePreview(signedIn: true)) {
        ProfileSheetView()
    }
}

#Preview("S-04 signed in with Apple") {
    OnboardingPreviewHost(env: appleSignedInPreviewEnvironment()) {
        ProfileSheetView()
    }
}

#Preview("S-04 no profile") {
    OnboardingPreviewHost(env: .makePreview(signedIn: false, seedsFixtures: false)) {
        ProfileSheetView()
    }
}

#Preview("S-04 large text") {
    OnboardingPreviewHost(env: .makePreview(signedIn: true)) {
        ProfileSheetView()
    }
    .environment(\.dynamicTypeSize, .accessibility2)
}

@MainActor
private func appleSignedInPreviewEnvironment() -> TremorEnvironment {
    let env = TremorEnvironment.makePreview(signedIn: false)
    env.account.adopt(AppleCredential(
        userIdentifier: "preview.000",
        fullName: "Alex Rivera",
        email: "alex_rivera@privaterelay.appleid.com"))
    return env
}
