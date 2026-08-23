# Versioning and release process

_Last updated: 9 August 2026._

How Nevermore versions itself and how a new version gets into users' hands.

**Two channels, shipped together:**

| | Mac App Store | DMG from GitHub Releases |
|---|---|---|
| Built by | Xcode app target | `make-dmg.sh` |
| Signed with | Apple Distribution + profile | Developer ID Application |
| Sandbox | always | no |
| Updates | the store | **Sparkle** |
| Notarization | Apple | `make-dmg.sh --notarize` |

**Sparkle ships in the DMG build only.** Apple rejects apps that update
themselves, so the store target must not contain an updater. Rather than a
build flag someone can forget, every use of Sparkle is behind
`#if canImport(Sparkle)`, and the package is a dependency of the SwiftPM
`NevermoreApp` target only — an Xcode store target that doesn't add the package
compiles the updater out automatically.

If the store version later becomes paid and the DMG is withdrawn, deleting the
Sparkle dependency is the whole change; nothing else references it.

**Status:** both channels are live. 1.0.0 ships as a notarized DMG with a
signed appcast, and the same version is with App Review as build 49, built on
CI because this machine runs a macOS beta (see MAS-RELEASE.md §8.5).

---

## 1. Versioning

### Two numbers, different jobs

| Key | Example | Meaning |
|---|---|---|
| `CFBundleShortVersionString` | `0.3.1` | **Marketing version.** What users see, what tags and release notes use. |
| `CFBundleVersion` | `47` | **Build number.** Opaque, strictly increasing, never reused. |

macOS and the App Store both compare `CFBundleVersion` to decide what
is newer. It must increase on every build we publish, even a rebuild of the same
marketing version. The marketing version is for humans.

Build number is `git rev-list --count HEAD` — monotonic on a linear `main`,
reproducible from any checkout, no state to maintain.

> Assumption: `main` stays linear (we squash before merge, per the repo
> convention). If we ever start merging with real merge commits, the count still
> increases monotonically along `main`, so this holds; it only breaks if history
> is rewritten to be *shorter*, which we don't do after a tag exists.

### Scheme: semver, applied to an app

`MAJOR.MINOR.PATCH`, currently in `0.x`.

- **PATCH** (`0.3.0` → `0.3.1`) — bug fixes, security fixes, copy changes. No
  new user-visible capability, no schema change.
- **MINOR** (`0.3.1` → `0.4.0`) — new features, new provider support,
  backward-compatible schema migrations, UI changes.
- **MAJOR** (`0.x` → `1.0`) — reserved. `1.0` means: no known data-loss bugs,
  the sandboxed build is verified working, and we'd be comfortable with a
  stranger's 100k-message mailbox. After `1.0`, a MAJOR bump means the user has
  to *do* something — re-authenticate, re-sync from scratch, or accept a
  one-way data migration.

While in `0.x`, MINOR carries the weight MAJOR normally would; there is no
stability promise before `1.0` and the README should keep saying so.

Pre-release builds use `0.4.0-beta.1`. On the App Store these go out through
TestFlight, which keeps them away from anyone who hasn't opted in.

### Single source of truth

`Packages/NevermoreKit/VERSION` holds the marketing version and nothing else.
It was added because the version had been hardcoded in two unrelated places —
`make-app.sh`'s Info.plist heredoc and the User-Agent — which had already
drifted apart.

- `make-app.sh` reads it into `CFBundleShortVersionString` and computes
  `CFBundleVersion` from the commit count.
- Runtime code reads it back out of the bundle — one accessor in `NevermoreKit`:

  ```swift
  public enum AppVersion {
      /// Marketing version from the bundle; the fallback marks a non-bundled
      /// build (tests, probe), which must never be mistaken for a release.
      public static let marketing =
          Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
          ?? "0.0.0-dev"
      public static var userAgent: String { "Nevermore/\(marketing)" }
  }
  ```

- The User-Agent, the About box, and the diagnostics export header all use it.
  Nothing hardcodes a version string again.

Bumping a version is then: edit one file, commit, tag.

---

## 2. What lives where

| Artifact | Location | Notes |
|---|---|---|
| Marketing version | `Packages/NevermoreKit/VERSION` | Committed. The only place it's written by hand. |
| Build number | derived | `git rev-list --count HEAD`, or `NEVERMORE_BUILD` to override. |
| Release notes | `CHANGELOG.md` (repo root) | [Keep a Changelog](https://keepachangelog.com) format; also the source for App Store "What's New". |
| Git tag | `v0.1.0` | Annotated and signed. `tag.gpgsign` is enabled in this repo. |
| Store build | App Store Connect | Uploaded from Xcode; Apple signs and distributes. |
| Direct build | `Nevermore-0.1.0.dmg` | Built, signed, notarized, and stapled by `make-dmg.sh --notarize`. |
| Appcast | `docs/appcast.xml` | Served by GitHub Pages; Sparkle polls it. Generated by Sparkle's `generate_appcast`. |
| Sparkle public key | `Resources/sparkle-public-key.txt` | Committed. `make-app.sh` injects it into `Info.plist`; absent, Sparkle is inert. |
| Sparkle **private** key | **1Password only** | Never in the repo. See below. |

### The Sparkle signing key is the highest-risk artifact here

Sparkle verifies each update with an EdDSA signature. The public half is baked
into every DMG build; the private half signs each release.

**Lose the private key and every installed copy can never auto-update again** —
the public key they carry can't be changed without an update, and the update
can't be signed. Recovery means telling every user to download a fresh build by
hand.

Generate it once, then immediately put the private key in 1Password:

```bash
# The tool ships inside the resolved Sparkle package
find Packages/NevermoreKit/.build -name generate_keys -type f
./generate_keys                     # prints the public key; private goes to the login Keychain
./generate_keys -x sparkle-private-key.txt   # export it, save to 1Password, then delete the file
```

Put the printed public key in `Packages/NevermoreKit/Resources/sparkle-public-key.txt`.
Builds made before that file exists are inert, not broken.

### Signing identities

Two, and they coexist:

- **Developer ID Application** — used by `make-app.sh` for local and direct
  builds. Keep it stable: an ad-hoc signature changes identity every build,
  which invalidates the Keychain ACL and makes the app unable to read its own
  saved password.
- **Apple Distribution** + a Mac App Store provisioning profile — used by the
  Xcode app target for store uploads. See [MAS-RELEASE.md](MAS-RELEASE.md).

## 3. Branching

Release from `main`. No release branches, no develop branch — at one
maintainer and this cadence, they'd be pure overhead.

**Hotfix on a shipped version, when `main` has moved on:**

```bash
git switch -c hotfix/0.3.2 v0.3.1
# fix, bump VERSION to 0.3.2, commit
git tag -s v0.3.2 -m "Nevermore 0.3.2"
# release from this branch, then merge the fix back to main
```

The build number still comes from `git rev-list --count HEAD`, which on a
branch off an older tag will be *lower* than a build already published from
`main`. That breaks monotonicity. If we ever ship a hotfix while `main` is
ahead, override it: `NEVERMORE_BUILD=<higher number> ./make-app.sh release`.
`make-app.sh` should honor that env var precisely for this case.

---

## 4. The database is forward-only

`MessageStore` uses a GRDB `DatabaseMigrator` with named migrations (`v1`,
`v2-history-metadata`, `v3-message-id`). This constrains releases:

- **Never edit or reorder a migration that has shipped.** Its name is recorded
  in the user's database; changing the body means existing users never run the
  new version of it and new users get a different schema. Add `v4-…` instead.
- **Downgrades are not supported.** An older build opening a newer database
  will either fail to migrate or misread columns. The App Store only moves
  users forward, so this is acceptable — but it's why "just reinstall the old
  version" is not a rollback plan (see §7).
- **A release containing a new migration gets a pre-migration backup.** Before
  running migrations for the first time under a new build, copy the SQLite file
  to `<name>.pre-v4.sqlite` in the same directory. Cheap insurance; the cache is
  regenerable but re-syncing 132k messages is a bad afternoon.
- Schema changes are at minimum a **MINOR** bump, never a PATCH.

---

## 5. Release checklist

Every step is verifiable — do not proceed past a red one.

### Preflight (on `main`, clean tree)

1. `git status` is clean and `main` is pushed.
2. `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build`
   — clean. (The bare `swift build` in the README fails without this on a
   machine whose `xcode-select` points at CommandLineTools; the SwiftUI macro
   plugins aren't in that toolchain.)
3. `swift test` — **all pass**. Currently 479 tests.
4. Update `CHANGELOG.md`: move `Unreleased` items under the new version and
   date.
5. Update `Packages/NevermoreKit/VERSION`.
6. Commit: `Release 0.3.1`.

### Build and sign

7. `./notarize.sh` — builds release, signs with Developer ID, hardened runtime,
   submits to Apple, waits, staples, re-zips. Verify the output says
   `notarized and stapled`.
8. `spctl --assess --type execute -vv Nevermore.app` → `accepted`,
   `source=Notarized Developer ID`.
9. `xcrun stapler validate Nevermore.app` → validated (proves it launches on a
   machine with no network).

### Smoke test the actual artifact

Not the build directory — the zip, on a machine that has never run it.

10. Unzip to `/Applications`, launch. It opens without a Gatekeeper warning.
11. Add an account, sync, unsubscribe from one sender, undo a trash. Confirm
    the Keychain prompt appears at most once and the saved password survives a
    relaunch.
12. If this release contains a migration: launch it against a **copy** of a
    real pre-migration database and confirm the data survives.
13. Sandboxed build sanity (keeps the MAS track alive):
    `NEVERMORE_SANDBOX=1 ./make-app.sh release`, launch, add an account,
    confirm it connects. It starts empty by design — the container has its own
    Application Support.

### Publish

**App Store:** Product ▸ Archive ▸ Distribute App ▸ App Store Connect, then
submit for review. Paste the review notes from
[MAS-RELEASE.md](MAS-RELEASE.md) — especially the pointer to demo mode, which
is how a reviewer evaluates the app without an email account.

**DMG:**

```bash
git tag -s v0.1.0 -m "Nevermore 0.1.0" && git push --follow-tags
cd Packages/NevermoreKit && ./make-dmg.sh --notarize
gh release create v0.1.0 Nevermore-0.1.0.dmg --notes-from-file <notes>

# Regenerate the appcast from every published DMG and publish it
generate_appcast ./releases/          # signs each DMG with the EdDSA key
cp releases/appcast.xml docs/appcast.xml && git commit -am "Update appcast"
```

`make-dmg.sh` refuses to build when `VERSION` and the tag disagree, so tag
first.

**Then verify the update path end to end:** install the *previous* DMG, let it
check for updates, and confirm it offers, downloads, and installs the new one.
This is the only real test of Sparkle, and it's the step most likely to be
skipped and most likely to be broken.

### After

18. Bump `VERSION` to the next patch with a `-dev` suffix so a stray dev build
    is never mistaken for the release.

---

## 6. Cadence and what triggers a release

- **Security fix** in the unsubscribe path, the SSRF guard, or credential
  handling → release immediately, PATCH, no batching.
- **Data-loss or sync-corruption bug** → same.
- **Everything else** → batched. Ship when there's a coherent set of changes
  worth a user's restart, not on a calendar.

The App Store handles update delivery and its own cadence; there is nothing to
configure and nothing to nag with.

---

## 7. Rollback

There is no recall. Once a build is installed, it's installed — and §4 means
users can't safely downgrade to an older database schema.

What we can actually do:

1. **Remove the build from sale** in App Store Connect, or halt a phased
   release. This stops it reaching anyone who hasn't updated yet.
2. **Mark any GitHub Release as a pre-release** so it drops off the "latest"
   link.
3. **Ship a fixed PATCH forward.** This is the real remedy — App Review takes
   days, so expedited review exists for exactly this, and asking for it is
   reasonable when the bug loses mail. Roll forward, never back.

Which is the argument for step 17 in the checklist: the cost of a bad release
is high enough that the manual smoke test earns its time.

## Distribution channels

The App Store is primary. `make-app.sh` and `notarize.sh` remain the path for a
Developer ID build — useful for testing the un-sandboxed app, and for anyone
who wants a direct download. The differences between the two builds are
tabulated at the end of [MAS-RELEASE.md](MAS-RELEASE.md); the one that bites
during testing is that a sandboxed build keeps its data in a container and so
always looks like a first run.

## What's done, and what's left

Implemented:

- [x] `Packages/NevermoreKit/VERSION`, read by `make-app.sh`, with the build
      number from `git rev-list --count HEAD` and a `NEVERMORE_BUILD` override.
- [x] `AppVersion` in `NevermoreKit`; no version string is hardcoded anywhere.
- [x] `CHANGELOG.md`.
- [x] Pre-migration database backup in `MessageStore`.
- [x] `tag.gpgsign = true`.
- [x] A guard in `notarize.sh` that refuses to build when `VERSION` and the tag
      disagree.

Left, all of it in [MAS-RELEASE.md](MAS-RELEASE.md):

- [x] The thin Xcode app target — generated by Tuist from `Project.swift`.
- [x] App Store Connect record, signing assets, privacy nutrition label.
- [x] Publish `PRIVACY.md` at a stable URL — `docs/privacy.html`, served at
      <https://brooksc.github.io/Nevermore/privacy.html>. Still to do: point
      App Store Connect at it.
- [x] First archive, upload, and review submission — 1.0.0 build 49, uploaded from CI.

And for the DMG channel:

- [x] `make-dmg.sh` — builds, signs, notarizes, staples a mountable DMG.
- [x] Sparkle wired in behind `#if canImport(Sparkle)`, framework embedded and
      signed by `make-app.sh`.
- [x] Generate the EdDSA keypair; commit the public half, back the private half
      up to 1Password.
- [x] Store notarytool credentials:
      `xcrun notarytool store-credentials nevermore-notary --apple-id … --team-id SU999VT2G2`
- [x] Publish `docs/appcast.xml` and confirm an old build updates itself —
      verified 0.1.0 → 0.1.1 on 1 August 2026.

Open questions:

- **Nothing verifies the built bundle's version against `CHANGELOG.md`.** The
  tag guard covers `VERSION`; the changelog can still be forgotten.
- **Convert the test harness to swift-testing** once the Xcode target makes
  Xcode a hard requirement anyway.
