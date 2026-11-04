import SwiftUI

/// C-24 — the end of a paged list. Never shows a spinner and the end message together.
struct ListFooter: View {
    enum State: Equatable {
        case loading
        case end
        case failed(String)
    }

    let state: State
    var endText = "没有更多行程"
    var retry: (() -> Void)?

    var body: some View {
        Group {
            switch state {
            case .loading:
                HStack(spacing: Theme.Spacing.s) {
                    ProgressView()
                    Text("正在加载更多…")
                }
            case .end:
                Text(endText)
            case .failed(let message):
                VStack(spacing: Theme.Spacing.s) {
                    Text(message)
                    if let retry {
                        Button {
                            retry()
                        } label: {
                            Text("重试")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .font(.footnote)
        .foregroundStyle(Theme.textSecondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.l)
    }
}
