# Mac App Store release

_Last updated: 26 July 2026. Status: not yet submitted. Steps 1–4 are done in
the codebase; steps 5 onward need your Apple account and can't be scripted
here._

Nevermore is built with SwiftPM (`Packages/NevermoreKit`). `make-app.sh` wraps
the executable into a signed `.app`, which is enough for Developer ID
distribution but **not** enough for the App Store: a SwiftPM executable can't
carry a provisioning profile through validation. The store path needs a thin
Xcode app target. That's the one real piece of work left, and it's step 5.

> **No Sparkle.** Apple rejects apps that update themselves, so the App Store
> build must not contain an updater — the store handles updates. This is why
> [RELEASE.md](RELEASE.md) treats Sparkle as belonging only to a
> Developer-ID-only future, and why it isn't in the project today. Choosing MAS
> means choosing not to add it.

---

## Done in the codebase

1. **App Sandbox entitlements** — `Resources/Nevermore.entitlements`:
   `com.apple.security.app-sandbox` plus `com.apple.security.network.client`.
   No server entitlement, no file access outside the container.
2. **Sandbox-safe code** — no subprocess spawning anywhere. Diagnostics read
   the unified log via `OSLogStore(scope: .currentProcessIdentifier)`, which is
   the only scope a sandboxed app may read. All app data is written under
   Application Support, which resolves inside the container.
3. **Provider-agnostic** — any IMAP provider, folders discovered via
   SPECIAL-USE. No Gmail-only APIs, so nothing depends on a Google project.
4. **Versioning** — `VERSION` holds the marketing version; `make-app.sh` writes
   it and a commit-count build number into `Info.plist`. The App Store requires
   a strictly increasing `CFBundleVersion` per upload, which the commit count
   satisfies. See [RELEASE.md](RELEASE.md).

Verify the sandbox locally before doing anything else:

```bash
cd Packages/NevermoreKit
NEVERMORE_SANDBOX=1 ./make-app.sh release
```

Launch it, add an account, sync. **It will start with no accounts** — the
sandbox relocates Application Support to
`~/Library/Containers/com.brooksc.nevermore/Data/…`, so it can't see a
non-sandboxed build's data. That's expected, not a bug. If the Keychain and
IMAP work here, the sandbox is correctly configured.

---

## Steps that need your Apple Developer account

### 5. Create a thin Xcode app target

The only structural work. In a new or existing `Nevermore.xcodeproj`:

- Add a macOS **App** target, bundle id `com.brooksc.nevermore`, deployment
  target macOS 14.
- File ▸ Add Package Dependencies ▸ Add Local… ▸ `Packages/NevermoreKit`, and
  link the `NevermoreKit` library.
- Move `Sources/NevermoreApp/*` into that target, or make `NevermoreApp` a
  library product of the package and have the app target's `@main` call into
  it. The second keeps one source of truth and is worth the extra step.
- Set the target's entitlements to `Resources/Nevermore.entitlements`.
- Set **Signing & Capabilities** to your team with automatic signing, and add
  the **App Sandbox** capability with only *Outgoing Connections (Client)*
  checked.
- Copy the `NSAppTransportSecurity` block from `make-app.sh`'s Info.plist —
  see the review notes below for why it's needed.

Keep `make-app.sh` working. It stays the fast path for local builds and
Developer ID, and it's what the screenshots and the test loop use.

### 6. App Store Connect record

Create the app with bundle id `com.brooksc.nevermore`. You'll need:

- **Name** — "Nevermore" if available; App Store names are unique.
- **Primary category** — Productivity.
- **Age rating** — the questionnaire; the app has an in-app browser that opens
  sender-chosen pages, so answer the unrestricted-web-access question honestly.
- **Privacy policy URL** — required. Publish [PRIVACY.md](PRIVACY.md) at a
  stable URL; the GitHub Pages site in `docs/` is the intended home.
- **Support URL** — the same site or the repository's issues page.

### 7. Signing assets

Automatic signing in Xcode will create these, or make them by hand in the
Developer portal:

- **Apple Distribution** certificate (the app)
- **Mac Installer Distribution** certificate (the `.pkg`)
- A **Mac App Store** provisioning profile for the bundle id

These are separate from the Developer ID certificate `make-app.sh` uses. Both
can coexist.

### 8. Privacy nutrition label

In App Store Connect, under App Privacy. The honest answers:

- **Data collected: none.** Not "collected but not linked" — none. There is no
  server and no telemetry.
- Nothing is tracked, so no tracking disclosure.

Be ready to justify this: reviewers sometimes assume a mail app must be
uploading something. The answer is that the app talks only to the user's own
mail provider and to the unsubscribe endpoint the sender published.

### 9. Archive and upload

Product ▸ Archive ▸ Distribute App ▸ App Store Connect. Validate first; it
catches entitlement and profile mismatches before the upload.

### 10. App Review notes

Paste something close to this into the review notes — the first two points are
the ones most likely to draw a question:

> Nevermore is a local-only mail utility. It connects from the user's Mac
> directly to their own IMAP provider using an app-specific password they
> supply. There is no server, no account, and no analytics.
>
> **Arbitrary loads (`NSAllowsArbitraryLoads`)**: the app sends unsubscribe
> requests to endpoints published by mail senders in the RFC 2369
> `List-Unsubscribe` header. Some senders still publish `http://` URLs. The
> destinations are chosen by the sender, not the app, and reaching them is the
> app's core function. All such URLs are validated against a guard that rejects
> private, loopback, and link-local addresses before any request is made, and
> redirects are re-validated at every hop.
>
> **Mail access**: the app reads message *headers* only, using
> `BODY.PEEK[HEADER.FIELDS (...)]` — it never downloads message bodies and
> never marks mail as read. Deleting moves messages to the provider's Trash
> folder; the app never issues an IMAP `EXPUNGE`, so nothing is permanently
> destroyed.
>
> **Demo mode**: choose "Try the Demo" on first launch to review the entire
> interface with a fabricated mailbox, without credentials. It runs on a
> backend containing no network code.

That last point matters — **demo mode is how a reviewer evaluates this app
without an email account**, which removes the most common cause of rejection
for tools that need a login. Mention it first if the review notes are trimmed.

### 11. After approval

- Tag the release (`git tag -s v0.1.0`); `notarize.sh` refuses to build if
  `VERSION` and the tag disagree.
- Update `CHANGELOG.md`.
- Bump `VERSION` to the next `-dev` value so a stray local build can't be
  mistaken for the shipped one.

---

## Known divergences from the Developer ID build

| | Developer ID | Mac App Store |
|---|---|---|
| Built by | `make-app.sh` | Xcode app target |
| Signed with | Developer ID Application | Apple Distribution + profile |
| Sandbox | opt-in (`NEVERMORE_SANDBOX=1`) | always |
| App Support | `~/Library/Application Support/` | container |
| Updates | manual download (or Sparkle, if ever added) | App Store |
| Notarization | `notarize.sh` | handled by Apple |

The container relocation is worth remembering when testing: the two builds
cannot see each other's accounts, so a sandboxed build always looks like a
first run.
