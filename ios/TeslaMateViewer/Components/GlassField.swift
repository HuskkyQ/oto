import SwiftUI
import UIKit

/// C-34 — labelled input well.
struct GlassField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var isSecure = false
    var keyboardType: UIKeyboardType = .default
    var error: String?

    @State private var revealed = false
    @FocusState private var focused: Bool

    private var borderColor: Color {
        if error != nil { return Theme.red.opacity(0.55) }
        return focused ? Theme.accent.opacity(0.55) : .white.opacity(0.10)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)

            HStack(spacing: 8) {
                Group {
                    if isSecure && !revealed {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                    }
                }
                .focused($focused)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 15))
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.accent)

                if isSecure {
                    Button {
                        revealed.toggle()
                    } label: {
                        Image(systemName: revealed ? "eye.slash" : "eye")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(revealed ? "隐藏 Token" : "显示 Token")
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, isSecure ? 2 : 14)
            .frame(height: 50)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(.white.opacity(0.055))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: 1)
                    }
            }

            if let error {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(Theme.red)
            }
        }
    }
}
