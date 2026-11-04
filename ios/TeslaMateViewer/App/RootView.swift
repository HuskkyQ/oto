import SwiftUI

struct RootView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Group {
            if settings.isConfigured {
                MainTabView()
            } else {
                SettingsView(isOnboarding: true)
            }
        }
        .background(Theme.background.ignoresSafeArea())
    }
}

struct MainTabView: View {
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var chrome = TabBarChrome()
    @State private var selection: AppTab = .live

    var body: some View {
        TabView(selection: $selection) {
            LiveView()
                .tag(AppTab.live)
                .modifier(TabContentChrome())

            DrivesView()
                .tag(AppTab.drives)
                .modifier(TabContentChrome())

            ChargingView()
                .tag(AppTab.charging)
                .modifier(TabContentChrome())

            StatsView()
                .tag(AppTab.stats)
                .modifier(TabContentChrome())
        }
        .tint(Theme.accent)
        .overlay(alignment: .bottom) {
            // Only the bar animates; page insets below stay constant.
            ZStack {
                if !chrome.hidden {
                    TabBar(selection: $selection)
                        .padding(.bottom, 10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: chrome.hidden)
        }
        .environmentObject(chrome)
        .sheet(isPresented: $settings.wantsSettings) {
            SettingsView(isOnboarding: false)
        }
    }
}

/// Hides the system tab bar and clears the floating bar's height under every tab's content.
/// The clearance stays constant: toggling it makes a covered page scroll by the delta when
/// it comes back.
private struct TabContentChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .tabBar)
            .contentMargins(.bottom, 84, for: .scrollContent)
    }
}
