# Brainstorm: Auth Layer (Sign Up + Log In) with Supabase

**Date**: 2026-06-01
**Status**: Ready for Planning
**Branch**: `claude/auth-layer-supabase-kZcoV`

## Problem Statement

Cadence is currently a **local-first, account-less** app. The boot flow is
`CadenceApp → RootView → Splash → Onboarding → MainTabView`, where the only gate
is a `UserProfileManager.hasCompletedOnboarding` boolean in `UserDefaults`. All
user data lives locally (`SwiftData` models + `UserDefaults` profile). There is
no concept of an account, no server-side identity, and no cross-device sync.

We want to introduce an **authentication layer** supporting both **sign up** and
**log in**, backed by **Supabase**. Per the confirmed decision, we use
**Supabase Auth (GoTrue)** for identity/credentials **plus a linked `profiles`
table** that mirrors the existing name/weight/height profile (the "hybrid"
model). We never store raw passwords ourselves — Supabase handles hashing,
sessions, JWTs, and resets.

## Core Requirements

- **Sign up** (create account) and **log in** (returning user) flows.
- Supabase Auth as the identity provider; a `profiles` table linked by
  `auth.users.id` for app profile data.
- Secure session persistence so users stay logged in across launches.
- A clean integration with the existing local-first data (`UserProfileManager`,
  `SwiftData`) — do not regress the current UX.
- Follow existing architecture patterns: factory + protocol + mock split
  (`APIClientFactory`), secrets via `SecretsLoader`, `@MainActor` ViewModels.
- DEBUG/mock mode must still work offline without a live Supabase project.

## Constraints

- **Dependency manager**: project uses **CocoaPods** (only `lottie-ios`) wired
  through `Cadence.xcworkspace`. The official `supabase-swift` SDK ships via
  **Swift Package Manager**; there is no first-party CocoaPod. Adding SPM
  alongside Pods is supported by Xcode but is a new pattern for this repo.
- **iOS 18.6 min target** (from `Podfile`) — fine; `supabase-swift` supports it.
- **MainActor isolation** default (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`).
  Auth ViewModels follow the `@MainActor final class` + `@Published` convention.
- **Secrets**: Supabase URL + anon key must flow through `SecretsLoader`
  (`Secrets.plist` / env), never hardcoded. The anon key is publishable by
  design, but should still not be committed.
- **App Store review**: offering Google (third-party social login) requires
  **Sign in with Apple** to also be offered — **satisfied**, since v1 ships both.
- **Sign in with Apple**: needs the *Sign in with Apple* capability/entitlement,
  native `ASAuthorizationController`, and a **nonce** passed to Supabase
  (`signInWithIdToken`). Apple may return a **private-relay email** and only
  returns the user's name **once** (on first authorization) — must capture it
  then.
- **Sign in with Google**: configure the Google provider in Supabase + a Google
  OAuth client; on iOS use the ASWebAuthenticationSession/OAuth flow (or Google
  SDK id-token → `signInWithIdToken`). Requires a redirect URL scheme.
- **Extensions** (`ScreenTimeMonitor`, `ScreenTimeReport`, `CadenceWidget`) may
  eventually need the session via the App Group keychain — out of scope for v1
  but the storage choice should not preclude it.

## Confirmed Decision (from user)

- **Auth model = Hybrid**: Supabase Auth (managed GoTrue) for credentials +
  a separate `profiles` table linked by `auth user id`. We do **not** roll our
  own credentials table.

---

## Approach 1: Auth-gated onboarding (account required) — *Recommended*

**Summary**: Insert an auth step into the existing onboarding so a Supabase
account is created/restored before the user reaches the main app; profile pages
write to both local storage and the `profiles` table.

New flow (OAuth has no separate "sign up" vs "log in" — first authorization
auto-provisions the account; subsequent ones just sign in):
```
Splash → Welcome → [Continue with Apple / Google] → Name → Body → Completion → MainTab
                          │
                          └─ returning user (profile exists) → skip profile pages → MainTab
```

A new `AuthService` (protocol + real/mock + factory, mirroring
`APIClientFactory`) owns the Supabase client and exposes `signInWithApple`,
`signInWithGoogle`, `signOut`, `currentSession`, and an `authState` stream.
`RootView` gains an `authState` gate ahead of (or fused into) the onboarding
gate.

**Pros**:
- Guarantees every user has a server identity → unlocks sync, backup,
  multi-device, server-side AI features later.
- Cleanly extends the existing onboarding container (`OnboardingView` already
  has a paged `TabView` and a completion handoff closure).
- Profile data captured in onboarding maps 1:1 onto the `profiles` table.

**Cons**:
- Adds friction to first launch (account wall before value) — mitigated by
  putting Welcome first and keeping the form minimal.
- Existing local-only users (already past onboarding) need a one-time
  "create/link account" migration path.
- Requires network on first run (offline sign-up impossible).

**Complexity**: Medium
**Risk**: Medium

## Approach 2: Optional auth with guest mode (local-first preserved)

**Summary**: Keep the app fully usable **without** an account (guest). Auth lives
in Profile/Settings as "Sign up to back up & sync." On sign-up, local data is
uploaded and linked to the new account.

**Pros**:
- Zero added friction; preserves the current local-first UX exactly.
- Account becomes a value-add ("back up your data"), not a wall → better
  activation for a health app.
- Naturally supports offline-first; auth is layered on top.

**Cons**:
- Two states to support forever (guest vs. authed) → more branching, more QA.
- Guest→account **data migration/merge** is the hard part (dedupe `SwiftData`
  rows, reconcile `UserDefaults` profile with `profiles` row).
- Easy for users to never sign up → sync features underused.

**Complexity**: High (migration/merge logic)
**Risk**: Medium-High

## Approach 3: Thin standalone auth screen (gate before everything)

**Summary**: A dedicated, separate `AuthView` shown before splash/onboarding for
unauthenticated users — a hard wall decoupled from onboarding. Onboarding runs
afterward only for brand-new accounts.

**Pros**:
- Cleanest separation of concerns (auth is its own module, not entangled with
  onboarding pages).
- Simplest mental model for the gate in `RootView` (authed? → onboarding gate →
  app).
- Easiest to later swap/extend auth methods without touching onboarding.

**Cons**:
- Hard wall on very first screen (before any value shown) = worst activation.
- Duplicates some visual scaffolding the onboarding flow already provides
  (`OnboardingBackground`, styling).

**Complexity**: Low-Medium
**Risk**: Low (technically), High (activation/UX)

---

## Cross-Cutting Design (applies to chosen approach)

### Module shape (mirrors existing patterns)
```
Cadence/Core/Services/Auth/
├── AuthServiceProtocol.swift     # signInWithApple / signInWithGoogle / signOut / session / authState
├── SupabaseAuthService.swift     # real impl, wraps supabase-swift client
├── MockAuthService.swift         # offline/DEBUG, fakes sessions for mockMode
├── AuthServiceFactory.swift      # .shared → real|mock via AppConfig.mockMode
├── SupabaseClientProvider.swift  # builds SupabaseClient from SecretsLoader
└── AuthSessionStore.swift        # Keychain-backed session persistence
Cadence/Features + UI/Auth/
├── Views/ (AuthGateView with "Continue with Apple" + "Continue with Google")
└── ViewModels/ (AuthViewModel: @MainActor, @Published)
Cadence/Core/Services/Auth/Providers/
├── AppleSignInCoordinator.swift  # ASAuthorizationController + nonce
└── GoogleSignInCoordinator.swift # OAuth web flow → id token
Cadence/Models/
└── Profile.swift                 # Codable mirror of `profiles` row
```

### Supabase schema (hybrid model)
- `auth.users` — managed by Supabase (do not touch).
- `public.profiles` — `id uuid PK references auth.users(id) on delete cascade`,
  `name text`, `weight_kg double precision`, `height_cm double precision`,
  `weight_unit text`, `height_unit text`, `onboarding_completed_at timestamptz`,
  `updated_at timestamptz`.
- **Row Level Security ON**: policy `auth.uid() = id` for select/insert/update.
- Auto-create profile row via a `handle_new_user()` trigger on `auth.users`
  insert (or client-side upsert right after sign-up).

### Secrets
- Add `SUPABASE_URL` and `SUPABASE_ANON_KEY` accessors to `SecretsLoader`,
  sourced from `Secrets.plist` / env. Keep `Secrets.plist` git-ignored; commit a
  `Secrets.example.plist`.

### Session persistence
- Provide a custom storage conforming to supabase-swift's auth storage that
  writes to **Keychain** (not `UserDefaults`), so refresh tokens are protected
  and (later) shareable via App Group with extensions.

### Local data reconciliation
- **New sign-up**: after account creation, upsert the onboarding-captured
  profile into `profiles`; set `UserProfileManager` locally as the cache.
- **Returning log-in**: fetch `profiles` row → hydrate `UserProfileManager` →
  skip onboarding profile pages.
- **Existing local-only user** (already onboarded, no account): show a one-time
  "Create account to back up your data" prompt that links current local profile
  to the new account (Approach 1 makes this a migration; Approach 2 makes it the
  normal guest→account path).

### Mock / offline support
- `MockAuthService` returns a canned session immediately so `mockMode` and
  previews work with no network and no real Supabase project — exactly how
  `MockAPIClient` shields the rest of the app today.

---

## Edge Cases to Consider
- [ ] **Same email across providers** (signs in with Google once, Apple later) →
      decide on Supabase identity linking vs treating as separate accounts.
- [ ] **Apple private-relay email** → never assume a real/contactable inbox; key
      everything off the stable `user.id`, not email.
- [ ] **Apple returns name only once** (first authorization) → capture and persist
      to `profiles` immediately; can't re-request later.
- [ ] **User cancels the OAuth sheet** (`ASWebAuthenticationSession` /
      `ASAuthorization` cancel) → treat as benign, return to auth screen, no error
      noise.
- [ ] **Nonce mismatch / replay** on `signInWithIdToken` → reject and restart.
- [ ] Redirect URL scheme misconfig (Google) → fails silently; needs a clear
      dev-time check.
- [ ] Network offline during sign-in → clear retry, no data loss.
- [ ] Expired/invalid refresh token on launch → silent refresh, else re-auth
      without nuking local data.
- [ ] Sign-out → what happens to local `SwiftData`/`UserDefaults`? (Keep cache vs
      wipe — privacy vs convenience; default: keep, clear on explicit "log out &
      erase").
- [ ] **Account deletion** (App Store requirement once accounts exist) → in-app
      delete removing `auth.users` + `profiles` (cascade); for Apple, also handle
      token **revocation**.
- [ ] Two devices editing the same profile → `updated_at` last-write-wins for v1.
- [ ] Existing onboarded user who never had an account → migration prompt fires
      exactly once and is dismissible.
- [ ] Deep-link return from OAuth handled via `RootView.onOpenURL` (already wired).
- [ ] Anon/publishable key + Google client secret rotation — keep out of source
      control.

## Open Questions
- [ ] **Gating policy**: account *required* (Approach 1) vs *optional guest*
      (Approach 2)? This is the biggest remaining fork — see Recommendation.
- [ ] **Email/password too?** v1 is Apple + Google OAuth. Add an email/password
      option as well, or OAuth-only for now? (OAuth-only is simpler and avoids
      password-reset flows.)
- [ ] **Cross-provider identity linking**: if a user signs in with Google then
      Apple under the same email, link to one account or keep separate?
- [ ] **Dependency manager**: SPM for `supabase-swift` (recommended) — OK to
      introduce SPM alongside CocoaPods in the workspace? (Google sign-in may also
      pull `GoogleSignIn-iOS` via SPM, or use the pure web OAuth flow with none.)
- [ ] **Sign-out data policy**: keep local cache or wipe on logout?
- [ ] **Account deletion**: in-app self-serve now, or manual for v1? (Apple
      requires self-serve once accounts exist in a shipping build; Apple also
      needs token revocation.)

## Decisions Made
| # | Decision | Severity | Chosen Option | Rationale |
|---|----------|----------|---------------|-----------|
| 1 | Credential handling | Critical | **Hybrid**: Supabase Auth + linked `profiles` table | User-selected. Never store raw passwords; managed Auth is secure; `profiles` mirrors existing name/weight/height for app use + future sync. |
| 2 | Sign-in methods (v1) | High | **Sign in with Apple + Sign in with Google** (OAuth via Supabase `signInWithIdToken`) | User-specified. Lowest-friction native auth on iOS; offering Apple satisfies the App Store rule triggered by Google. OAuth auto-provisions accounts, so there is no separate sign-up vs log-in form. Email/password left as an open question. |

## Recommendation

**Pursue Approach 1 (auth-gated onboarding) with the cross-cutting module shape**,
with one deliberate softening: keep a **"Skip / continue as guest"** affordance on
the auth step so we don't kill first-run activation for a health app (borrowing
the best part of Approach 2). Concretely:

1. Add `AuthService` (protocol + `SupabaseAuthService` + `MockAuthService` +
   `AuthServiceFactory`) following the `APIClientFactory` pattern.
2. Add Supabase secrets to `SecretsLoader`; Keychain-backed session store.
3. Insert an **Auth step after Welcome** in `OnboardingView`; returning users log
   in and skip the profile pages.
4. Stand up the `profiles` table with **RLS** + auto-provision trigger; sync
   onboarding profile up on sign-up, hydrate `UserProfileManager` on log-in.
5. Reconcile existing local-only users via a one-time "create account to back up"
   prompt.

This delivers real accounts and a clean path to sync, reuses the existing
onboarding/factory/secrets architecture, and isolates the risky bits (data
migration, OAuth provider config). With methods settled (Apple + Google), the
**gating policy (account required vs optional guest)** and **whether to also add
email/password** are the two questions to settle before planning.

## Research References
- App boot/gate: `Cadence/App/RootView.swift` (onboarding gate + `onOpenURL`),
  `Cadence/App/CadenceApp.swift` (`@main`, env objects, model container).
- Profile storage to mirror: `Cadence/Core/Services/UserProfileManager.swift`.
- Onboarding container to extend: `Cadence/Features + UI/Onboarding/OnboardingView.swift`.
- Patterns to mirror: `Cadence/Networking/Real/APIClientFactory.swift` (real/mock
  factory), `Cadence/Core/Services/SecretsLoader.swift` (secrets).
- SDK: `supabase-swift` (official, SPM) — Auth (GoTrue), PostgREST, Realtime.
- Supabase docs: Auth + Row Level Security + iOS/Swift quickstart.
