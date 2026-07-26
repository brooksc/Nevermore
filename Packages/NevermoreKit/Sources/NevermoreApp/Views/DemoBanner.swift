import SwiftUI

/// Persistent notice that the window is showing invented mail, not the user's.
///
/// Deliberately not dismissible and deliberately loud. The failure mode this
/// guards against is someone unsubscribing from a demo sender, seeing it
/// disappear, and believing they've cleaned up their real mailbox — or worse,
/// believing they *haven't* and doing it twice somewhere else. A banner you can
/// close is a banner that's closed exactly when it matters.
struct DemoBanner: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "theatermasks.fill")
                .foregroundStyle(.white)
                .font(.system(size: 14))

            VStack(alignment: .leading, spacing: 1) {
                Text("Demo Mode — this is example data")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                Text(model.hasRealAccount
                    ? "Nothing here is your mail, and no action leaves this Mac."
                    : "Nothing here is your mail. Add your account to use Nevermore for real.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }

            Spacer()

            Button(model.hasRealAccount ? "Back to My Mail" : "Add My Account") {
                Task { await model.exitDemoMode() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(Tokens.demoAccent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(Tokens.demoAccent)
    }
}
