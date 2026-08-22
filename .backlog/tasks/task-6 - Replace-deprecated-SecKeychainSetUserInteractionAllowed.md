---
id: TASK-6
title: Replace deprecated SecKeychainSetUserInteractionAllowed
status: Done
assignee: []
created_date: '2026-08-09 18:51'
updated_date: '2026-08-22 22:51'
labels:
  - tech-debt
dependencies: []
modified_files:
  - Packages/NevermoreKit/Sources/NevermoreKit/Credentials/Keychain.swift
  - Packages/NevermoreKit/Tests/NevermoreTests/main.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Keychain.swift:80-81 uses SecKeychainSetUserInteractionAllowed, deprecated since macOS 10.10 along with the whole SecKeychain API. Four warnings per clean build.

It is used to stop a Keychain prompt appearing during a headless read. The modern equivalent is per-item access control on the SecItem call rather than a process-wide toggle. Worth doing while the surrounding code is small enough to reason about — credential handling is the last place to want a surprise API removal.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Process-wide interaction toggle replaced with per-item behaviour
- [ ] #2 No prompt appears during a normal read, including after a rebuild
- [ ] #3 Password still survives app relaunch, sandboxed and not
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch `task-6-fix`. The premise of AC #1 does not hold, so it is deliberately left unchecked.

**There is no modern per-item replacement for this dialog.** `kSecUseAuthenticationUI` and `LAContext.interactionNotAllowed` (via `kSecUseAuthenticationContext`) reach only the data-protection keychain. Apple states it in SecItem.h about the same mechanism's older spelling: "on macOS, this attribute only applies to items stored in the Data Protection keychain. Legacy keychain items will still activate UI if needed." Measured on macOS 27 (26A5416b) against a generic-password item this binary was not on the ACL of: adding `kSecUseAuthenticationUIFail` or `...UISkip` changed the returned status not at all (`errSecAuthFailed` in every case). A mechanical swap would not suppress the dialog — it would *cause* the dialog `readWouldPrompt` exists to predict, i.e. exactly the first-run ambush the function was written to avoid.

**What changed instead:**
- `readWouldPrompt` is now a two-step probe. Step 1 is an attributes-only read, which cannot prompt (the ACL guards decrypting the data, not reading attributes — measured: a foreign binary still gets `errSecSuccess`). It distinguishes "no item saved" from "item I cannot read", which the old single data read could only infer. Step 2 reads the data with interaction suppressed, as before.
- `kSecUseAuthenticationUISkip` is now passed per-item. It is the one spelling that is not itself deprecated, and it is inert on this item today (measured). Step 1 is what makes it safe: `Skip` reports an unreadable item as `errSecItemNotFound`, which alone would silently read as "nothing saved, no prompt".
- The deprecated `SecKeychainSetUserInteractionAllowed` is kept — it still functions on macOS 27 (setter observed by `SecKeychainGetUserInteractionAllowed`) — but is now confined to one private wrapper, `withUserInteractionSuppressed`, marked `@available(macOS, deprecated: 10.10)` so it stops re-stating what its own doc comment says. Kept as a direct call rather than `dlsym` so an actual removal breaks the build instead of surfacing as a dialog on a user's screen. Deprecation warnings in NevermoreKit: 2 -> 1.

**Verified** (no dialog appeared at any point; all probe items removed afterwards, confirmed absent via the `security` CLI; the maintainer's real item was never touched): absent account -> false; store in one process and read in a second -> false plus the correct password; delete -> gone; an item planted by a *differently signed* binary -> `readWouldPrompt` correctly returns true. Suite: 380 pass, 0 fail (377 before, plus 3 read-only tests).

**Not verified:** anything involving the signed, bundled, sandboxed app — that needs launching the GUI. All measurement was from command-line binaries, where an ACL check appears to resolve without UI when interaction is allowed. So `readWouldPrompt` returning true is properly read as "consent evaluation is required", which in a bundled app is the dialog; it over-predicts rather than under-predicts, which is the fail-safe direction and is unchanged from before.

**Separate defect found, not fixed here:** `Keychain.delete(for:)` on an item the running build is not on the ACL of fails with -25244 ("Invalid attempt to change the owner of this item"). The return value is discarded, so `AccountRegistry.remove` and the debug reset silently leave the item behind in exactly the re-signed/restored case. Worth its own task.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: task-6 agent
created: 2026-08-22 22:51
---
AC #1 ("process-wide toggle replaced with per-item behaviour") cannot be satisfied as written and is left unchecked: the per-item keys do not govern the legacy keychain's ACL dialog, and swapping to them would cause the very prompt this code predicts. AC #2 and #3 are verified for command-line processes but not for the signed, sandboxed app bundle, so they are also left unchecked. The one route to genuinely per-item control is migrating the item to the data-protection keychain (kSecUseDataProtectionKeychain), which would invalidate every existing user's saved password on upgrade unless migrated deliberately — a decision for the maintainer, not a side effect of a tech-debt fix.
---
<!-- COMMENTS:END -->
