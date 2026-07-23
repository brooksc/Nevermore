import SwiftUI

/// The unsubscribe-method glyph shown in the table and inspector.
struct MethodIcon: View {
    let method: UnsubscribeMethod
    var size: CGFloat = 15

    var body: some View {
        Image(systemName: method.systemImage)
            .font(.system(size: size))
            .foregroundStyle(tint)
            .help(method.label)
            .accessibilityLabel(method.label)
    }

    private var tint: Color {
        switch method {
        case .oneClick: Tokens.brandBlue
        case .webLink, .email: .secondary
        case .manual: .orange
        }
    }
}

/// Unread percentage: a number and a thin bar. Never colour alone (spec §15).
struct UnreadBar: View {
    let percent: Int
    var width: CGFloat = 44

    var body: some View {
        // Fixed geometry rather than a GeometryReader: GeometryReader inside a
        // Table cell forces extra layout passes and can churn "multiple times
        // per frame". The bar width is known, so compute the fill directly.
        HStack(spacing: 7) {
            Text("\(percent)%")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)
            ZStack(alignment: .leading) {
                Capsule().fill(Color(nsColor: .quaternaryLabelColor))
                    .frame(width: width, height: 4)
                Capsule().fill(Tokens.unreadBar)
                    .frame(width: width * CGFloat(min(max(percent, 0), 100)) / 100, height: 4)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(percent) percent unread")
    }
}

/// A monogram avatar on a tinted circle (inspector, reappeared/ignored rows).
struct Monogram: View {
    let text: String
    var diameter: CGFloat = 44

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Tokens.brandBlue.opacity(0.85), Tokens.brandBlue],
                    startPoint: .top, endPoint: .bottom)
            )
            .frame(width: diameter, height: diameter)
            .overlay(
                Text(initial)
                    .font(.system(size: diameter * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }

    private var initial: String {
        guard let first = text.first else { return "?" }
        return String(first).uppercased()
    }
}

/// A centred empty/transitional state: symbol, headline, one line, optional button.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title).font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
