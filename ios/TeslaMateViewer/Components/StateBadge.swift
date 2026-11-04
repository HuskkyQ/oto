import SwiftUI

struct StateBadge: View {
    let state: String?

    private var label: String {
        switch state {
        case "online": return "在线"
        case "asleep": return "休眠"
        case "offline": return "离线"
        case "charging": return "充电中"
        case "driving": return "行驶中"
        case "updating": return "更新中"
        case "suspended": return "已暂停"
        default: return state ?? "未知"
        }
    }

    private var color: Color {
        switch state {
        case "online", "driving": return Theme.green
        case "charging", "updating": return Theme.orange
        case "suspended": return Theme.purple
        default: return .secondary
        }
    }

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.16), in: Capsule())
    }
}
