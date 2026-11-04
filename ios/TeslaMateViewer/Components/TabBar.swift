import SwiftUI

enum AppTab: Int, CaseIterable, Identifiable {
    case live
    case drives
    case charging
    case stats

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .live: return "实时"
        case .drives: return "行程"
        case .charging: return "充电"
        case .stats: return "统计"
        }
    }

    var symbol: String {
        switch self {
        case .live: return "gauge"
        case .drives: return "point.topleft.down.to.point.bottomright.curvepath"
        case .charging: return "bolt"
        case .stats: return "chart.bar.xaxis"
        }
    }
}

/// Pages that take the whole screen ask the floating bar to step aside.
///
/// The requests are counted rather than set: pushing a full-height detail marks the page below it
/// as disappeared too, so a plain `= false` there would bring the bar back over the detail.
@MainActor
final class TabBarChrome: ObservableObject {
    @Published private(set) var hidden = false

    private var holders = 0

    func hide() {
        holders += 1
        hidden = holders > 0
    }

    func show() {
        holders = max(0, holders - 1)
        hidden = holders > 0
    }
}

/// C-06 — the floating glass capsule from the design: five fixed items, the active tab as a
/// glass pill. The system tab bar is hidden on every tab, so this is the only bar shown.
struct TabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases) { tab in
                item(tab)
            }
        }
        .padding(6)
        .frame(height: 64)
        .background {
            GlassBackground(radius: 26)
        }
        .padding(.horizontal, 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("标签栏")
        .animation(.easeOut(duration: 0.18), value: selection)
    }

    private func item(_ tab: AppTab) -> some View {
        let isSelected = selection == tab

        return Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 18, weight: .medium))
                    .frame(height: 22)
                Text(tab.title)
                    .font(.system(size: 9.5, weight: .medium))
            }
            .foregroundStyle(isSelected ? Theme.accent : Theme.textFaint)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.16), .white.opacity(0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.26), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    }
                    .opacity(isSelected ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
