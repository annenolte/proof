//
//  SettingsView.swift
//  Tremor — Features / Library (S-19)
//
//  Preferences, and the two things a safety app owes its user: a plain account
//  of what leaves the device, and a way to take everything back out again.
//
//  The section order is deliberate. Simulation defaults first, because they are
//  what people come here to change. Then units. Then the cloud opt-in, which is
//  the only place in Tremor where anything at all leaves the phone, written out
//  in full and off by default. Then the data controls — export, restore, delete.
//  Then the credibility links. Version last, where it belongs.
//
//  Everything here writes straight through to `AppSettings`, which persists on
//  set; there is no "Save" button because there is nothing to save. The one
//  exception is the OpenAI key, which goes to the keychain, and which is
//  deliberately never read back into the field — only its presence is shown.
//

import SwiftUI
import UIKit

// MARK: - Screen

struct SettingsView: View {

    @Environment(\.tremor) private var tremor
    @Environment(Router.self) private var router
    @Environment(AppState.self) private var appState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var collapse: Double = 0
    @State private var keyDraft: String = ""
    @State private var hasStoredKey = false
    @State private var keyError: String?
    @State private var isExporting = false
    @State private var exportURLs: [URL] = []
    @State private var showsExportSheet = false
    @State private var confirmsDeleteAll = false
    @State private var storageBytes: Int64 = 0

    var body: some View {
        VStack(spacing: 0) {
            TremorNavBar(title: "Settings", collapseProgress: collapse)

            ScrollView {
                VStack(alignment: .leading, spacing: TremorSpacing.xl) {
                    accountSection
                    proofSection
                    aboutSection
                    versionFooter
                }
                .padding(.horizontal, TremorSpacing.md)
                .padding(.top, TremorSpacing.xs)
                .padding(.bottom, 200)
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                let distance = TremorNavBar.largeTitleHeight(
                    hasSubtitle: false, dynamicTypeSize: dynamicTypeSize)
                collapse = distance > 0 ? min(1, max(0, Double(offset / distance))) : 0
            }
        }
        .background(TremorColor.canvas.ignoresSafeArea())
        .task {
            hasStoredKey = SettingsSecrets.store(isPreview: tremor.isPreview).has(SecretKey.openAIAPIKey)
            storageBytes = await tremor.rooms.diskUsage()
        }
        .sheet(isPresented: $showsExportSheet) {
            SettingsShareSheet(items: exportURLs)
        }
        .confirmationDialog(
            "Delete every room?",
            isPresented: $confirmsDeleteAll,
            titleVisibility: .visible
        ) {
            Button("Delete everything", role: .destructive) { Task { await deleteAllRooms() } }
            Button("Keep my rooms", role: .cancel) {}
        } message: {
            Text("Every scan, report and fix-it plan on this iPhone will be removed. This cannot be undone, and nothing is stored anywhere else.")
        }
    }

    // MARK: Account

    private var accountSection: some View {
        SettingsGroup("You") {
            TremorListRow(
                title: tremor.account.profile?.displayName ?? "You",
                subtitle: tremor.account.isSignedIn
                    ? "Signed in with Apple"
                    : "Local profile, no account needed",
                leading: .iconWell("person.crop.circle"),
                accessory: .chevron,
                accessibilityHint: "Opens your profile") { router.openProfile() }
        }
    }

    // MARK: Simulation

    private var simulationSection: some View {
        SettingsGroup("Earthquakes", subtitle: "What a new simulation starts from. You can change either one on any room.") {
            VStack(alignment: .leading, spacing: TremorSpacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: TremorSpacing.xs) {
                    Text("Default intensity")
                        .tremorType(.bodyEmphasis)
                        .foregroundStyle(TremorColor.ink)
                    Spacer(minLength: 0)
                    TremorInfoButton(about: "the intensity scale") { router.openMethod() }
                        .padding(.trailing, -TremorSpacing.sm)
                }

                IntensityScaleView(intensity: tremor.settings.defaultIntensity) { level in
                    tremor.settings.defaultIntensity = level
                }
            }
            .padding(.horizontal, TremorSpacing.listInset)
            .padding(.vertical, TremorSpacing.sm)

            TremorRowDivider()

            SettingsMenuRow(
                title: "Ground type",
                subtitle: tremor.settings.defaultSoil.detail,
                symbol: "mountain.2",
                value: tremor.settings.defaultSoil.displayName,
                options: SoilClass.allCases,
                label: \.displayName,
                selection: Binding(
                    get: { tremor.settings.defaultSoil },
                    set: { tremor.settings.defaultSoil = $0 }))
        }
    }

    // MARK: Units

    private var unitsSection: some View {
        SettingsGroup("Units", subtitle: "Shaking is always reported in g and on the Mercalli scale — those don't change with units.") {
            VStack(alignment: .leading, spacing: TremorSpacing.sm) {
                TremorSegmentedControl(
                    selection: Binding(
                        get: { tremor.settings.units },
                        set: { tremor.settings.units = $0 }),
                    label: "Units") { $0.displayName }

                Text(unitsExample)
                    .tremorType(.footnote)
                    .foregroundStyle(TremorColor.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, TremorSpacing.listInset)
            .padding(.vertical, TremorSpacing.sm)
        }
    }

    private var unitsExample: String {
        let settings = tremor.settings
        return "A tall bookcase reads as \(settings.formatHeight(1.83)) and \(settings.formatMass(48))."
    }

    // MARK: Feel

    private var feelSection: some View {
        SettingsGroup("Feel") {
            TremorToggle(
                "Haptics",
                subtitle: "The phone taps in time with the shaking and every time something falls. Turns itself off in Low Power Mode.",
                systemImage: "iphone.gen3.radiowaves.left.and.right",
                isOn: Binding(
                    get: { tremor.settings.hapticsEnabled },
                    set: { tremor.settings.hapticsEnabled = $0 }))
            .padding(.horizontal, TremorSpacing.listInset)

            TremorRowDivider()

            TremorToggle(
                "Reduce camera shake",
                subtitle: "Keeps the 3D camera still during a quake. Your furniture still moves — that's the point of it.",
                systemImage: "camera.metering.center.weighted",
                isOn: Binding(
                    get: { tremor.settings.reduceMotion },
                    set: { tremor.settings.reduceMotion = $0 }))
            .padding(.horizontal, TremorSpacing.listInset)
        }
    }

    // MARK: Cloud identification

    private var cloudSection: some View {
        SettingsGroup("Smarter object details",
                      subtitle: "Off by default. proof works completely without it.") {
            TremorToggle(
                "Use smarter details",
                subtitle: "proof can send a small cropped photo of each piece of furniture to OpenAI to identify what it is and estimate its weight more accurately.",
                systemImage: "sparkles",
                isOn: Binding(
                    get: { tremor.settings.cloudIdentificationEnabled },
                    set: { tremor.settings.cloudIdentificationEnabled = $0 }))
            .padding(.horizontal, TremorSpacing.listInset)

            TremorRowDivider()

            VStack(alignment: .leading, spacing: TremorSpacing.xs) {
                Text("What actually leaves your iPhone")
                    .tremorType(.subheadline)
                    .foregroundStyle(TremorColor.ink)

                ForEach(Self.cloudFacts, id: \.self) { fact in
                    HStack(alignment: .firstTextBaseline, spacing: TremorSpacing.xs) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: TremorSpacing.xxs))
                            .foregroundStyle(TremorColor.primary)
                            .accessibilityHidden(true)
                        Text(fact)
                            .tremorType(.footnote)
                            .foregroundStyle(TremorColor.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Text("Your room layout, floor plan and location never leave your device. Photos are sent over an encrypted connection, are not used to train any model, and are not stored by proof.")
                    .tremorType(.footnote)
                    .foregroundStyle(TremorColor.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, TremorSpacing.xxs)

                if let recorded = tremor.settings.cloudConsentRecordedAt {
                    Text("You turned this on \(LibraryFormatting.shortDate(recorded)).")
                        .tremorType(.caption)
                        .foregroundStyle(TremorColor.inkTertiary)
                }

                if !tremor.network.isOnline, tremor.network.hasResolved {
                    Text("You're offline right now, so objects are being identified on-device. Nothing is queued or sent later.")
                        .tremorType(.footnote)
                        .foregroundStyle(TremorColor.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, TremorSpacing.listInset)
            .padding(.vertical, TremorSpacing.sm)

            if tremor.settings.cloudIdentificationEnabled {
                TremorRowDivider()
                apiKeyBlock
            }
        }
    }

    private var apiKeyBlock: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.sm) {
            if hasStoredKey {
                HStack(spacing: TremorSpacing.xs) {
                    Image(systemName: "key.fill")
                        .font(.system(size: TremorControlMetrics.glyphMedium))
                        .foregroundStyle(TremorColor.success)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: TremorSpacing.hair) {
                        Text("Your OpenAI key is saved")
                            .tremorType(.bodyEmphasis)
                            .foregroundStyle(TremorColor.ink)
                        Text("It's in the iPhone keychain, and it never appears in a report or an export.")
                            .tremorType(.footnote)
                            .foregroundStyle(TremorColor.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                TremorButton("Remove key", variant: .tertiary, size: .small, fillsWidth: false) {
                    removeKey()
                }
            } else {
                TremorTextField(
                    "Your OpenAI API key",
                    text: $keyDraft,
                    placeholder: "sk-…",
                    isSecure: true,
                    errorMessage: keyError,
                    helpText: "proof has no key of its own, so smarter details use yours. Billed to your OpenAI account, roughly a cent per room.",
                    leadingIcon: "key",
                    keyboardType: .asciiCapable,
                    submitLabel: .done,
                    autocapitalization: .never,
                    onSubmit: saveKey)

                TremorButton("Save key", variant: .secondary, size: .medium, action: saveKey)
                    .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal, TremorSpacing.listInset)
        .padding(.vertical, TremorSpacing.sm)
    }

    // MARK: Data

    private var dataSection: some View {
        SettingsGroup("Your data",
                      subtitle: "Everything proof knows lives on this iPhone. \(LibraryFormatting.fileSize(storageBytes)) of it right now.") {
            TremorListRow(
                title: isExporting ? "Preparing your rooms…" : "Export everything",
                subtitle: "One file per room, with its geometry, reports and photos",
                leading: .iconWell("square.and.arrow.up"),
                accessory: isExporting ? .custom(AnyView(ProgressView())) : .chevron,
                accessibilityHint: "Opens the share sheet with one file per room") {
                Task { await exportEverything() }
            }
            .disabled(isExporting)

            TremorRowDivider()

            TremorListRow(
                title: "Restore the demo rooms",
                subtitle: "Puts the three rooms we prepared back in your library",
                leading: .iconWell("arrow.counterclockwise"),
                accessory: .chevron) {
                Task { await restoreDemos() }
            }

            TremorRowDivider()

            TremorListRow(
                title: "Delete all rooms",
                subtitle: "Irreversible, and it takes your reports with it",
                leading: .iconWell(symbol: "trash", tint: TremorColor.danger,
                                   fill: TremorColor.danger.opacity(0.12)),
                accessory: .chevron,
                accessibilityHint: "Asks you to confirm first") {
                confirmsDeleteAll = true
            }
        }
    }

    // MARK: proof

    @State private var confirmsResetCraft = false

    private var proofSection: some View {
        let sky = appState.addRoomFlow.sky
        return SettingsGroup("Your kitchen", subtitle: "Edits, links and fix plans are kept on this iPhone.") {
            VStack(alignment: .leading, spacing: TremorSpacing.sm) {
                Text("Age stage")
                    .tremorType(.subheadline)
                    .foregroundStyle(TremorColor.ink)
                TremorSegmentedControl(
                    selection: Binding(get: { sky.stage }, set: { sky.setStage($0) }),
                    label: "Age stage",
                    icon: { $0.symbol },
                    title: { $0.title })
            }
            .padding(.vertical, TremorSpacing.xs)
            .padding(.horizontal, TremorSpacing.md)

            TremorRowDivider()

            TremorListRow(
                title: "Reset my edits",
                subtitle: "Back to what the scan found: \(sky.progressText)",
                leading: .iconWell("arrow.counterclockwise"),
                accessory: .chevron,
                accessibilityHint: "Asks you to confirm first") {
                confirmsResetCraft = true
            }
            .confirmationDialog("Reset your edits?", isPresented: $confirmsResetCraft, titleVisibility: .visible) {
                Button("Reset", role: .destructive) { sky.resetCraft() }
                Button("Keep them", role: .cancel) {}
            }
        }
    }

    // MARK: About

    private var aboutSection: some View {
        SettingsGroup("How proof works") {
            TremorListRow(title: "The method",
                         subtitle: "The pipeline, the engine, and what proof can't see",
                         leading: .iconWell("function"),
                         accessory: .chevron) { router.push(.method) }
            TremorRowDivider()
            TremorListRow(title: "Privacy",
                         leading: .iconWell("hand.raised"),
                         accessory: .chevron) { router.push(.privacy) }
            TremorRowDivider()
            TremorListRow(title: "Licences",
                         leading: .iconWell("doc.text"),
                         accessory: .chevron) { router.push(.licences) }
        }
    }

    private var versionFooter: some View {
        VStack(spacing: TremorSpacing.xxs) {
            Text(SettingsInfo.versionLine)
                .tremorType(.footnote)
                .foregroundStyle(TremorColor.inkTertiary)
            Text("Flags to check, not a safety guarantee.")
                .tremorType(.caption)
                .foregroundStyle(TremorColor.inkTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, TremorSpacing.md)
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    private func saveKey() {
        let trimmed = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let error = SettingsSecrets.validationError(for: trimmed) else {
            let store = SettingsSecrets.store(isPreview: tremor.isPreview)
            do {
                try store.setString(trimmed, for: SecretKey.openAIAPIKey)
                keyDraft = ""
                keyError = nil
                hasStoredKey = true
                appState.post("Key saved", message: "Smarter details are ready to use.", style: .success)
            } catch {
                keyError = "Couldn't save the key to the keychain. Try again."
            }
            return
        }
        keyError = error
    }

    private func removeKey() {
        let store = SettingsSecrets.store(isPreview: tremor.isPreview)
        try? store.delete(SecretKey.openAIAPIKey)
        hasStoredKey = false
        keyDraft = ""
        keyError = nil
        appState.post("Key removed", style: .info)
    }

    private func exportEverything() async {
        isExporting = true
        defer { isExporting = false }

        let summaries = (try? await tremor.rooms.list()) ?? []
        guard !summaries.isEmpty else {
            appState.post("Nothing to export",
                          message: "Scan a room first, and it'll show up here.",
                          style: .info)
            return
        }

        var urls: [URL] = []
        for summary in summaries where !summary.isDamaged {
            if let url = try? await tremor.rooms.export(id: summary.id) { urls.append(url) }
        }

        guard !urls.isEmpty else {
            appState.post("Couldn't export",
                          message: "None of your rooms could be packaged up. Their files may be damaged.",
                          style: .error)
            return
        }
        exportURLs = urls
        showsExportSheet = true
    }

    private func restoreDemos() async {
        try? await tremor.rooms.resetSamples()
        storageBytes = await tremor.rooms.diskUsage()
        appState.post("Demo rooms restored", style: .success)
        router.select(.rooms)
    }

    private func deleteAllRooms() async {
        let summaries = (try? await tremor.rooms.list()) ?? []
        for summary in summaries {
            try? await tremor.rooms.delete(id: summary.id)
        }
        storageBytes = await tremor.rooms.diskUsage()
        appState.post("All rooms deleted",
                      message: "Your library is empty. You can restore the demo rooms any time.",
                      style: .info)
    }

    // MARK: Constants

    /// The four true statements about the cloud pass, each independently
    /// verifiable in `Core/Understanding`.
    static let cloudFacts: [String] = [
        "One cropped photo of each object — never a whole camera frame, so no faces, no windows, no room.",
        "Its size in centimetres, and the category the scanner guessed.",
        "Nothing else: no name, no account, no location, no floor plan.",
    ]
}

// MARK: - Group

/// A settings section: an overline, an optional explanatory line, and a white
/// card holding the rows.
struct SettingsGroup<Content: View>: View {

    private let title: String
    private let subtitle: String?
    private let content: Content

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.xs) {
            TremorSectionHeader(title, subtitle: subtitle)

            TremorCard(padding: 0, shadow: .card) {
                VStack(spacing: 0) { content }
                    // Rows paint a full-bleed press wash, so they are clipped to
                    // the card's own radius rather than overflowing its corners.
                    .clipShape(RoundedRectangle(cornerRadius: TremorRadius.card, style: .continuous))
            }
        }
    }
}

// MARK: - Menu row

/// A row whose value is chosen from a short list. A menu rather than a push,
/// because a four-item choice does not deserve its own screen.
struct SettingsMenuRow<Option: Hashable>: View {

    var title: String
    var subtitle: String?
    var symbol: String
    var value: String
    var options: [Option]
    var label: KeyPath<Option, String>
    @Binding var selection: Option

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(option[keyPath: label]).tag(option)
                }
            }
        } label: {
            HStack(spacing: TremorSpacing.md) {
                Image(systemName: symbol)
                    .font(.system(size: TremorControlMetrics.glyphMedium))
                    .foregroundStyle(TremorColor.primary)
                    .frame(width: TremorSpacing.xxxl, height: TremorSpacing.xxxl)
                    .background(TremorColor.primarySoft, in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: TremorSpacing.hair) {
                    Text(title)
                        .tremorType(.bodyEmphasis)
                        .foregroundStyle(TremorColor.ink)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle)
                            .tremorType(.footnote)
                            .foregroundStyle(TremorColor.inkTertiary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: TremorSpacing.xxs) {
                    Text(value)
                        .tremorType(.subheadline)
                        .foregroundStyle(TremorColor.inkSecondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: TremorControlMetrics.glyphSmall, weight: .semibold))
                        .foregroundStyle(TremorColor.inkTertiary)
                }
                .layoutPriority(1)
            }
            .padding(.horizontal, TremorSpacing.listInset)
            .padding(.vertical, TremorSpacing.sm)
            .frame(minHeight: TremorSize.rowTwoLine)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .accessibilityHint("Opens a list of options")
    }
}

// MARK: - Secrets

/// Where the OpenAI key goes.
///
/// Previews must never touch the real keychain — they run in the same simulator
/// as the app — so a preview environment gets a throwaway in-memory store and
/// the shipped app gets `SecretStore.live`.
enum SettingsSecrets {

    @MainActor private static let previewStore: any SecretStoring = InMemorySecretStore()

    @MainActor
    static func store(isPreview: Bool) -> any SecretStoring {
        isPreview ? previewStore : SecretStore.live
    }

    /// Returns a sentence explaining what is wrong with a key, or `nil` when it
    /// looks usable. Deliberately forgiving: we check the shape, not the key.
    static func validationError(for key: String) -> String? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Paste your key first."
        }
        if trimmed.contains(where: { $0.isWhitespace }) {
            return "That has a space in it — keys don't. Try pasting it again."
        }
        if !trimmed.hasPrefix("sk-") {
            return "OpenAI keys start with \"sk-\". Check you copied the whole thing."
        }
        if trimmed.count < 20 {
            return "That looks too short to be a whole key."
        }
        return nil
    }
}

// MARK: - Bundle info

enum SettingsInfo {
    static var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "proof \(version) (\(build))"
    }
}

// MARK: - Share sheet

/// `UIActivityViewController`, for handing exported packages to another app.
struct SettingsShareSheet: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Previews

#Preview("S-19 — settings") {
    RootPreviewHost(env: .makePreview(), phase: .ready, tab: .settings)
}

#Preview("S-19 — offline") {
    RootPreviewHost(env: .makePreview(online: false), phase: .ready, tab: .settings)
}

#Preview("S-19 — accessibility 3") {
    RootPreviewHost(env: .makePreview(), phase: .ready, tab: .settings)
        .environment(\.dynamicTypeSize, .accessibility3)
}
