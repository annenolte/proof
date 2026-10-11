//
//  SignInView.swift
//  Tremor — Features / Onboarding — S-03
//
//  Sign in with Apple, and — at the same weight, in the same shape, on the same
//  row of the page — "Continue without an account".
//
//  That symmetry is deliberate and it is not generosity. Tremor has no server.
//  Rooms, assessments, reports and fix-it plans are files in the app's own
//  container. An account buys exactly one thing (carrying them to another device
//  later) and costs the user an identifier. Presenting the account as the way in
//  and the local profile as a grudging escape hatch would be a lie about the
//  architecture, so both are 56 pt pills and the copy says plainly what each one
//  is worth.
//

import SwiftUI
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

struct SignInView: View {

    @Environment(\.tremor) private var tremor
    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isAuthenticating = false
    @State private var errorMessage: String?

    private var appleIsOffered: Bool { tremor.account.isSignInWithAppleAvailable }

    var body: some View {
        ZStack {
            TremorColor.ink.ignoresSafeArea()

            // Centred when it fits, scrollable when it does not. A top-aligned
            // block on a tall phone leaves a third of the screen empty between
            // the copy and the buttons, which reads as an unfinished screen.
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Save your rooms.")
                            .tremorType(.displayM)
                            .foregroundStyle(TremorColor.primarySoft)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)

                        Text(bodyCopy)
                            .tremorType(.body)
                            .foregroundStyle(TremorColor.inkInverse.opacity(0.76))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, TremorSpacing.sm)

                        reassurance
                            .padding(.top, TremorSpacing.xl)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, TremorSpacing.pageInset)
                    .padding(.vertical, TremorSpacing.xl)
                    .frame(minHeight: geometry.size.height, alignment: .center)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { actions }
        }
    }

    // MARK: Copy

    private var bodyCopy: String {
        appleIsOffered
            ? "An account keeps your rooms, your flags and your fix plans if you change iPhone. It's the only thing it does — everything else works either way."
            : "proof keeps your rooms, your flags and your fix plans on this iPhone. Nothing here needs an account, and this build doesn't offer one."
    }

    /// Three plain facts, because "we never see your room" is a claim the user
    /// is entitled to see spelled out before they decide.
    private var reassurance: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.sm) {
            reassuranceRow("iphone", "Your scans stay on this iPhone.")
            reassuranceRow("eye.slash", "We never see the inside of your home.")
            reassuranceRow("checkmark.seal", "Every feature works without an account.")
        }
        .accessibilityElement(children: .combine)
    }

    private func reassuranceRow(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: TremorSpacing.sm) {
            // Lavender rather than the yuzu accent: Zip spends the lime on one
            // moment per screen, and on this screen that moment is the pair of
            // buttons, not a bullet list.
            Image(systemName: symbol)
                .font(.system(size: TremorControlMetrics.glyphSmall, weight: .semibold))
                .foregroundStyle(TremorColor.primarySoft.opacity(0.85))
                .frame(width: TremorControlMetrics.glyphMedium)
                .accessibilityHidden(true)
            Text(text)
                .tremorType(.callout)
                .foregroundStyle(TremorColor.inkInverse.opacity(0.66))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: TremorSpacing.sm) {
            if let errorMessage {
                inlineError(errorMessage)
            }

            if appleIsOffered {
                appleButton
                if !tremor.network.isOnline && tremor.network.hasResolved {
                    Text("Signing in with Apple needs a connection. Continuing without an account works offline, and gives you everything.")
                        .tremorType(.footnote)
                        .foregroundStyle(TremorColor.inkInverse.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            TremorButton("Continue without an account",
                        variant: .secondary,
                        hint: "Creates a profile that lives only on this iPhone. Nothing is locked.") {
                tremor.account.continueWithoutAccount()
                router.advanceLaunch(with: tremor)
            }
            .disabled(isAuthenticating)
        }
        .padding(.horizontal, TremorSpacing.pageInset)
        .padding(.top, TremorSpacing.md)
        .padding(.bottom, TremorSpacing.ctaBottomInset)
        .background {
            LinearGradient(
                colors: [TremorColor.ink.opacity(0), TremorColor.ink],
                startPoint: .top,
                endPoint: .bottom)
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        }
        .animation(TremorMotion.resolved(TremorMotion.reveal, reduceMotion: reduceMotion),
                   value: errorMessage)
        .animation(TremorMotion.resolved(TremorMotion.reveal, reduceMotion: reduceMotion),
                   value: appleIsOffered)
    }

    @ViewBuilder
    private var appleButton: some View {
        #if canImport(AuthenticationServices)
        SignInWithAppleButton(.signIn) { request in
            errorMessage = nil
            isAuthenticating = true
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            handle(result)
        }
        .signInWithAppleButtonStyle(.white)
        .frame(height: TremorSize.buttonLarge)
        .clipShape(Capsule(style: .continuous))
        // Lyft's disabled treatment, applied to a system control we cannot
        // restyle: the finished button takes one veil, and the spinner sits on
        // top of it, so the row never changes height while Apple's sheet is up.
        .overlay {
            if isAuthenticating {
                ZStack {
                    Capsule(style: .continuous)
                        .fill(TremorColor.ink.opacity(0.62))
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(TremorColor.inkInverse)
                }
            }
        }
        .allowsHitTesting(!isAuthenticating)
        .accessibilityLabel("Sign in with Apple")
        .accessibilityValue(isAuthenticating ? "In progress" : "")
        #endif
    }

    private func inlineError(_ message: String) -> some View {
        HStack(alignment: .top, spacing: TremorSpacing.xs) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: TremorControlMetrics.glyphSmall))
                .foregroundStyle(TremorColor.riskSevereSurface)
                .accessibilityHidden(true)
            Text(message)
                .tremorType(.footnote)
                .foregroundStyle(TremorColor.riskSevereSurface)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }

    // MARK: Outcome

    #if canImport(AuthenticationServices)
    private func handle(_ result: Result<ASAuthorization, Error>) {
        isAuthenticating = false

        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "Couldn't sign in. Try again."
                return
            }
            tremor.account.adopt(AppleCredential(
                userIdentifier: credential.user,
                fullName: Self.formattedName(credential.fullName),
                email: credential.email))
            router.advanceLaunch(with: tremor)

        case .failure(let error):
            switch AppleSignInController.translate(error) {
            case .cancelled:
                // SPEC S-03: a cancellation is a decision, not a failure.
                errorMessage = nil
            case .signInWithAppleUnavailable:
                // A build without the entitlement. Stop offering a button that
                // cannot work, and say so once.
                tremor.account.markSignInWithAppleUnavailable()
                errorMessage = "Sign in with Apple isn't available in this build. Carry on without an account — nothing is missing."
            case .authorizationFailed:
                errorMessage = "Couldn't sign in. Try again."
            }
        }
    }

    private static func formattedName(_ components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .default
        let formatted = formatter.string(from: components).trimmingCharacters(in: .whitespaces)
        return formatted.isEmpty ? nil : formatted
    }
    #endif
}

// MARK: - Previews

#Preview("S-03 idle") {
    SignInView()
        .environment(\.tremor, .makePreview(signedIn: false, seedsFixtures: false))
        .environment(Router())
}

#Preview("S-03 offline") {
    SignInView()
        .environment(\.tremor, .makePreview(online: false, signedIn: false, seedsFixtures: false))
        .environment(Router())
}

#Preview("S-03 large text") {
    SignInView()
        .environment(\.tremor, .makePreview(signedIn: false, seedsFixtures: false))
        .environment(Router())
        .environment(\.dynamicTypeSize, .accessibility2)
}
