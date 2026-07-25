# Mac App Store release notes

Nevermore is built with SwiftPM (`Packages/NevermoreKit`). For local development
and Developer ID distribution, `make-app.sh` wraps the executable into a signed
`.app`. Submitting to the **Mac App Store** requires a few things SwiftPM can't
do on its own and that need *your* Apple Developer account — they can't be
scripted here.

## What's already done in the codebase

- **App Sandbox entitlements** — `Resources/Nevermore.entitlements`
  (`com.apple.security.app-sandbox` + `com.apple.security.network.client`). No
  server entitlement, no file access beyond the app container.
- **Sandbox-safe code** — no `Process`/subprocess spawning. Diagnostics export
  reads the unified log via `OSLogStore(scope: .currentProcessIdentifier)`; the
  crash handler and all app data write inside the container's Application
  Support directory.
- **Provider-agnostic** — connects to any IMAP provider (Gmail, iCloud, Yahoo,
  Fastmail, AOL auto-detected; custom domains pick a provider). No Gmail-only
  APIs or hard-coded folder names.
- **Sandboxed local build** — `NEVERMORE_SANDBOX=1 ./make-app.sh release`
  applies the entitlements so you can verify the app still connects and the
  Keychain still works under the sandbox.
  - ⚠️ The sandbox relocates Application Support into
    `~/Library/Containers/com.brooksc.nevermore/Data/…`, so a sandboxed build
    starts with no accounts (it can't see a non-sandboxed dev build's data).
    That's expected.

## What you still have to do (needs your Apple account)

1. **Create the app record** in App Store Connect (bundle id
   `com.brooksc.nevermore`).
2. **Signing assets** in your Apple Developer account:
   - a **Mac App Distribution** certificate (for the app) and a **Mac Installer
     Distribution** certificate (for the `.pkg`), or let Xcode manage signing;
   - a **Mac App Store provisioning profile** for the bundle id.
3. **Use a real Xcode app target for submission.** A SwiftPM executable wrapped
   by a shell script can't carry a provisioning profile through `altool`/
   Transporter validation. Create a thin Xcode "App" target that depends on the
   `NevermoreKit` package (File ▸ Add Package Dependencies ▸ local package), set
   its entitlements to `Resources/Nevermore.entitlements`, and move
   `Sources/NevermoreApp/*` into that target (or reference it as a library).
4. **Archive & upload**: Product ▸ Archive → Distribute App → App Store Connect.
5. **App Review notes**: justify `NSAllowsArbitraryLoads` (in `make-app.sh`'s
   Info.plist) — some senders publish http-only `List-Unsubscribe` URLs, and the
   whole purpose of the app is to reach the sender-chosen unsubscribe endpoint.
   Confirm you read only message *headers*, never bodies, and store data locally.

## Privacy nutrition label (App Store Connect)

- **Data collected:** none transmitted to us — there is no server.
- Email metadata (sender, subject, headers) is stored **on device** only.
- The app password is stored in the **macOS Keychain**.
