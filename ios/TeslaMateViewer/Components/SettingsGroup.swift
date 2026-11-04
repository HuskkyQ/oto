import SwiftUI

/// C-11 — rounded container for a group of settings rows.
struct SettingsGroup<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background {
            GlassBackground(radius: Theme.Radius.card, soft: true)
        }
    }
}

/// C-12 — label, muted value, trailing control or chevron.
struct SettingsRow: View {
    let title: String
    var value: String?
    var showsChevron = false
    var showsDivider = true
    var action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button {
                    action()
                } label: {
                    row
                }
                .buttonStyle(.plain)
            } else {
                row
            }
        }
    }

    private var row: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.m) {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textPrimary)

                Spacer(minLength: Theme.Spacing.s)

                if let value {
                    Text(value)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.28))
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .frame(minHeight: 52)

            if showsDivider {
                Rectangle()
                    .fill(.white.opacity(0.07))
                    .frame(height: 0.5)
                    .padding(.leading, Theme.Spacing.l)
            }
        }
        .contentShape(Rectangle())
    }
}
