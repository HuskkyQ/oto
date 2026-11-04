import SwiftUI

struct SettingsView: View {
    let isOnboarding: Bool
    /// Set when the page is pushed; the sheet and onboarding pass nothing.
    var onBack: (() -> Void)?

    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var model = SettingsViewModel()

    @State private var showConnectionEditor = false
    @State private var showClearConfirmation = false

    var body: some View {
        if isOnboarding {
            onboarding
        } else {
            settingsScreen
        }
    }

    // MARK: - Onboarding (FR-1)

    private var onboarding: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                VStack(spacing: Theme.Spacing.m) {
                    HeroGlyph(systemImage: "car.fill")
                    Text("连接你的 TeslaMate")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("使用公网 HTTPS 地址和 Token 安全连接。")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                ConnectionForm(
                    model: model,
                    buttonTitle: "测试并保存",
                    successPause: .milliseconds(700)
                ) {}

                Text("填写已部署的公网 HTTPS 代理地址；手机无需 Tailscale。")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(Theme.Spacing.l)
            .padding(.top, 56)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(ScreenBackground())
        .onAppear { model.prepareForEditing(baseURL: settings.baseURLString) }
    }

    // MARK: - Settings (FR-2)

    private var settingsScreen: some View {
        ScreenScaffold(title: "设置", backAction: onBack) {
            VStack(spacing: Theme.Spacing.l) {
                SettingsGroup {
                    SettingsRow(
                        title: "服务器",
                        value: settings.baseURLString,
                        showsChevron: true
                    ) {
                        openConnectionEditor()
                    }

                    SettingsRow(title: "API Token", value: "••••••••", showsChevron: true) {
                        openConnectionEditor()
                    }

                    statusRow
                }

                if case .failed(let message) = model.status {
                    ErrorBanner(message: message)
                }

                SettingsGroup {
                    carMenuRow
                }

                SettingsGroup {
                    ToggleRow(
                        title: "中国坐标偏移校正",
                        caption: "WGS-84 → GCJ-02；海外自动关闭",
                        isOn: $settings.mapOffsetCorrection
                    )
                }

                SettingsGroup {
                    SettingsRow(
                        title: "版本",
                        value: "0.1.0 · 只读 · HTTPS 安全连接",
                        showsDivider: false
                    )
                }

                DestructiveButton(title: "清除 Token") {
                    showClearConfirmation = true
                }
                .padding(.top, Theme.Spacing.s)
            }
            .padding(Theme.Spacing.l)
        }
        // Pushed from Live: the page draws its own header and 返回, so hide the system bar.
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.loadCars(client: settings.client) }
        .sheet(isPresented: $showConnectionEditor) { connectionEditor }
        .confirmationDialog(
            "清除 Token？",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("清除 Token", role: .destructive) {
                settings.clearToken()
                model.reset()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("清除后需要重新填写服务器地址和 Token。")
        }
    }

    private var statusRow: some View {
        HStack(spacing: Theme.Spacing.s) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)

            Text(statusText)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)

            Spacer(minLength: Theme.Spacing.s)

            Button {
                Task { await model.loadCars(client: settings.client) }
            } label: {
                Text("测试连接")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .disabled(model.isTesting)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .frame(minHeight: 48)
    }

    private var statusColor: Color {
        switch model.status {
        case .connected: return Theme.green
        case .failed: return Theme.orange
        default: return .white.opacity(0.3)
        }
    }

    private var statusText: String {
        switch model.status {
        case .idle: return "未验证"
        case .testing: return "正在验证…"
        case .connected(let count): return "连接正常 · \(count) 辆车"
        case .failed: return "连接失败"
        }
    }

    private var carMenuRow: some View {
        Menu {
            ForEach(model.cars) { car in
                Button {
                    settings.carId = car.id
                } label: {
                    Text(car.displayName)
                }
            }
        } label: {
            SettingsRow(
                title: "车辆",
                value: currentCarName,
                showsChevron: true,
                showsDivider: false
            )
        }
        .disabled(model.cars.isEmpty)
    }

    private var currentCarName: String {
        model.cars.first { $0.id == settings.carId }?.displayName ?? "未加载"
    }

    private var connectionEditor: some View {
        NavigationStack {
            ScrollView {
                ConnectionForm(
                    model: model,
                    buttonTitle: "测试并保存",
                    allowsStoredToken: true
                ) {
                    showConnectionEditor = false
                }
                .padding(Theme.Spacing.l)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(ScreenBackground())
            .navigationTitle("服务器与 Token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showConnectionEditor = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func openConnectionEditor() {
        model.prepareForEditing(baseURL: settings.baseURLString)
        showConnectionEditor = true
    }
}
