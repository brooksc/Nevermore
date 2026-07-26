# Versioning and release process

How Nevermore versions itself and how a new version gets into users' hands.

**Primary channel:** Developer ID direct download (GitHub Releases), notarized
and stapled, with Sparkle in-app auto-update. The Mac App Store is a **second,
later track** — see [MAS-RELEASE.md](MAS-RELEASE.md) — and it has one hard
conflict with this process, documented under [MAS divergence](#mas-divergence).

**Status:** this document is the plan. Several pieces described here do not
exist in the code yet; they are collected in
[Implementation checklist](#implementation-checklist). Nothing has shipped and
there are no tags yet, so we get to set this up before the first release
rather than retrofit it.

---

## 1. Versioning

### Two numbers, different jobs

| Key | Example | Meaning |
|---|---|---|
| `CFBundleShortVersionString` | `0.3.1` | **Marketing version.** What users see, what tags and release notes use. |
| `CFBundleVersion` | `47` | **Build number.** Opaque, strictly increasing, never reused. |

macOS, Sparkle, and the App Store all compare `CFBundleVersion` to decide what
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

Pre-release builds use `0.4.0-beta.1`. Sparkle serves these on a separate
`beta` appcast channel, so they only reach users who opt in.

### Single source of truth

Today the version is hardcoded in two unrelated places that will drift:
`make-app.sh`'s Info.plist heredoc (`0.1` / `1`) and the `Nevermore/1.0`
User-Agent in `Sources/NevermoreKit/Unsubscribe/UnsubscribeEngine.swift:89`
and `:135`. They already disagree.

The fix: a `VERSION` file at `Packages/NevermoreKit/VERSION` containing exactly
the marketing version (`0.3.1\n`) and nothing else.

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
| Release notes | `CHANGELOG.md` (repo root) | [Keep a Changelog](https://keepachangelog.com) format. Sparkle's per-release description is generated from it. |
| Git tag | `v0.3.1` | Annotated **and signed** (`git tag -s`). SSH signing is already configured; `tag.gpgsign` is not, so pass `-s` explicitly or set it. |
| Distributable | `Nevermore-0.3.1.zip` | Notarized, stapled. Attached to the GitHub Release. |
| Appcast | `appcast.xml` | Served over HTTPS (GitHub Pages off this repo). Sparkle polls it. |
| Sparkle private key | **1Password only** | See below. Never in the repo, never in the release. |

### The Sparkle signing key is the highest-risk artifact here

Sparkle verifies each update with an EdDSA signature. The public half goes in
the app's Info.plist (`SUPublicEDKey`) and is baked into every build we ship.
The private half signs each release.

**If we lose the private key, every already-installed copy of Nevermore can
never auto-update again** — the public key they carry can't be changed without
an update, and the update can't be signed. Recovery means telling every user to
manually download a fresh build.

So: generate it once with Sparkle's `generate_keys`, immediately export and
store it in 1Password, and confirm it's there before the first release ships. It
also lives in the login keychain of whichever Mac does releases; that is a
convenience copy, not the backup.

---

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
  will either fail to migrate or misread columns. Sparkle only moves users
  forward, so this is acceptable — but it's why "just reinstall the old
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
3. `swift run nevermore-tests` — **all pass**. Currently 70/70.
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

14. `git tag -s v0.3.1 -m "Nevermore 0.3.1" && git push --follow-tags`
15. `gh release create v0.3.1 Nevermore-0.3.1.zip --notes-from-file <notes>`
16. Regenerate and publish the appcast:
    `generate_appcast ./releases/` — it signs each zip with the EdDSA key,
    reads the version out of each bundle, and writes `appcast.xml`. Publish it
    to the Pages site.
17. Verify the loop end to end: install the **previous** version, let it check
    for updates, confirm it offers the new one, installs it, and relaunches.
    This is the only real test of the update pipeline, and it's the step most
    likely to be skipped and most likely to be broken.

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

Sparkle's default check interval (24h) is fine. Don't set it lower; this is not
an app that benefits from nagging.

---

## 7. Rollback

There is no recall. Once a build is installed, it's installed — and §4 means
users can't safely downgrade to an older database schema.

What we can actually do:

1. **Pull the bad version from the appcast** immediately (remove its `<item>`,
   republish). This stops it reaching anyone who hasn't updated yet — usually
   the large majority within the first day.
2. **Mark the GitHub Release as a pre-release** so it drops off the "latest"
   link.
3. **Ship a fixed PATCH forward.** This is the real remedy. Roll forward, never
   back.

Which is the argument for step 17 in the checklist: the cost of a bad release
is high enough that the manual smoke test earns its time.

## MAS divergence

**Apple rejects apps containing their own updater.** A Mac App Store build must
not include Sparkle. If we pursue the MAS track, the app needs a build-time
switch — Sparkle compiled in for the Developer ID product, compiled out for the
MAS product — plus separate signing identities, a provisioning profile, and the
thin Xcode target described in MAS-RELEASE.md.

Practically this means two release processes with a shared preflight, and a
version that may sit in App Review for days while the direct build is already
out. Worth doing when there's a reason to be in the store; not worth carrying
the complexity before then. Until that decision, this document is the process.

---

## Implementation checklist

Described above but **not yet in the code**:

- [ ] `Packages/NevermoreKit/VERSION` file.
- [ ] `make-app.sh`: read `VERSION`, compute `CFBundleVersion` from
      `git rev-list --count HEAD`, honor a `NEVERMORE_BUILD` override.
- [ ] `AppVersion` accessor in `NevermoreKit`; replace the two hardcoded
      `Nevermore/1.0` User-Agent strings.
- [ ] `CHANGELOG.md`, seeded with an `Unreleased` section covering everything
      built so far.
- [ ] Sparkle: SPM dependency, `SUFeedURL` + `SUPublicEDKey` in the Info.plist
      heredoc, updater wired into the app, "Check for Updates…" menu item.
- [ ] EdDSA keypair generated and the private key backed up to 1Password.
- [ ] GitHub Pages set up to serve `appcast.xml` over HTTPS.
- [ ] Pre-migration database backup in `MessageStore`.
- [ ] `tag.gpgsign = true`, or remember `-s` on every tag.

Open questions:

- **Sparkle under the sandbox** needs its installer XPC services bundled and
  extra entitlements. Irrelevant for the Developer ID build, but it means the
  `NEVERMORE_SANDBOX=1` local build and the Sparkle build interact; worth
  verifying they don't collide before it matters.
- **Nothing verifies that `VERSION`, the tag, and the shipped bundle agree.** A
  cheap guard in `notarize.sh` — refuse to build if `VERSION` doesn't match the
  tag being released — would close the most likely process failure. Add it when
  the above lands.
