import SwiftUI

/// The server/token form shared by onboarding and the settings editor.
struct ConnectionForm: View {
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject var model: SettingsViewModel

    let buttonTitle: String
    var allowsStoredToken = false
    var successPause: Duration = .zero
    var onSaved: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            GlassField(
                label: "服务器地址",
                text: $model.draftURL,
                placeholder: "https://api.example.com",
                keyboardType: .URL
            )

            GlassField(
                label: "API Token",
                text: $model.draftToken,
                placeholder: allowsStoredToken ? "留空则沿用已保存的 Token" : "粘贴 Bearer Token",
                isSecure: true
            )

            status

            PrimaryButton(title: buttonTitle, isLoading: model.isTesting) {
                submit()
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch model.status {
        case .idle:
            EmptyView()
        case .testing:
            HStack(spacing: Theme.Spacing.s) {
                ProgressView()
                Text("正在验证…")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
            }
        case .connected(let count):
            Label("连接成功 · \(count) 辆车", systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.green)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .failed(let message):
            ErrorBanner(message: message)
        }
    }

    private func submit() {
        Task {
            let valid = await model.testConnection(
                settings: settings,
                allowsStoredToken: allowsStoredToken
            )
            guard valid else { return }

            // Let "连接成功 · N 辆车" land before the root view switches.
            if successPause > .zero {
                try? await Task.sleep(for: successPause)
            }

            guard model.commit(settings: settings) else { return }
            onSaved()
        }
    }
}
