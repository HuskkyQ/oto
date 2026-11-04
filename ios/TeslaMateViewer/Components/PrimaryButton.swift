import SwiftUI

/// C-35 — full-width accent action.
struct PrimaryButton: View {
    let title: String
    var isLoading = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            ZStack {
                Text(title)
                    .opacity(isLoading ? 0 : 1)
                if isLoading {
                    ProgressView()
                        .tint(Theme.backgroundTop)
                }
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.backgroundTop)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                Theme.accent.opacity(isEnabled ? 1 : 0.35),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
    }
}

/// C-36 — destructive action; confirmation belongs to the screen.
struct DestructiveButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.red)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.red.opacity(0.10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Theme.red.opacity(0.28), lineWidth: 1)
                        }
                }
        }
        .buttonStyle(.plain)
    }
}
