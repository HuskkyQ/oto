import SwiftUI

struct SegmentOption<Value: Hashable>: Identifiable {
    let value: Value
    let label: String

    var id: Value { value }
}

/// Plain text only: the selected label turns white and bolder; nothing else marks it.
struct SegmentedControl<Value: Hashable>: View {
    let options: [SegmentOption<Value>]
    @Binding var selection: Value
    var compact = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                segment(for: option)
            }
        }
    }

    private func segment(for option: SegmentOption<Value>) -> some View {
        let isSelected = option.value == selection

        return Button {
            guard !isSelected else { return }
            withAnimation(.easeOut(duration: 0.16)) { selection = option.value }
        } label: {
            Text(option.label)
                .font(.system(size: compact ? 12 : 13, weight: isSelected ? .bold : .semibold))
                .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textFaint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, compact ? 8 : 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // NFR-8 — VoiceOver has no other way to hear which segment is current.
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
