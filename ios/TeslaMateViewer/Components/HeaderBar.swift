import SwiftUI

struct HeaderAction {
    let systemImage: String
    let label: String
    let action: () -> Void

    init(_ systemImage: String, label: String, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.label = label
        self.action = action
    }
}

/// Pinned title and actions. One fixed state: full-bleed, no capsule, no scroll-driven change.
struct HeaderBar: View {
    static let height: CGFloat = 54

    let title: String
    var subtitle: String?
    var backAction: (() -> Void)?
    var actions: [HeaderAction] = []

    var body: some View {
        HStack(spacing: 10) {
            if let backAction {
                Button(action: backAction) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textPrimary.opacity(0.74))
                .accessibilityLabel("返回")
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.22)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Theme.Spacing.s)

            ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                Button(action: action.action) {
                    Image(systemName: action.systemImage)
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textPrimary.opacity(0.74))
                .accessibilityLabel(action.label)
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, 14)
        .padding(.bottom, 12)
        // Full-bleed backdrop: scrolled content ends at the bar's edge instead of colliding
        // with the title. Same navy as the page top — no radius, rim or shadow.
        .background(Theme.backgroundTop.ignoresSafeArea(edges: .top))
    }
}

/// Scroll view with the header pinned above it. Content carries a top inset equal
/// to the header height, so its first row starts below the bar.
struct ScreenScaffold<Content: View>: View {
    let title: String
    var subtitle: String?
    var backAction: (() -> Void)?
    var actions: [HeaderAction]
    var scrollResetToken: AnyHashable
    var onRefresh: (() async -> Void)?

    private let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        backAction: (() -> Void)? = nil,
        actions: [HeaderAction] = [],
        scrollResetToken: AnyHashable = 0,
        onRefresh: (() async -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.backAction = backAction
        self.actions = actions
        self.scrollResetToken = scrollResetToken
        self.onRefresh = onRefresh
        self.content = content()
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: 0)
                        .id(Self.topAnchor)

                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: HeaderBar.height)
            }
            // The status bar band stays navy: scrolled content stops at the header, not behind the clock.
            .clipped()
            .scrollIndicators(.hidden)
            .refreshableIfPresent(onRefresh)
            // Scrolling back is a scroll, not a rebuild: an `.id` here re-created the whole
            // ScrollView on every period switch, which read as a full-page flash.
            .onChange(of: scrollResetToken) {
                proxy.scrollTo(Self.topAnchor, anchor: .top)
            }
            .overlay(alignment: .top) {
                HeaderBar(
                    title: title,
                    subtitle: subtitle,
                    backAction: backAction,
                    actions: actions
                )
            }
            .background(ScreenBackground())
        }
    }

    private static var topAnchor: String { "screenScaffold.top" }
}

private struct RefreshIfPresent: ViewModifier {
    let action: (() async -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let action {
            content.refreshable { await action() }
        } else {
            content
        }
    }
}

private extension View {
    func refreshableIfPresent(_ action: (() async -> Void)?) -> some View {
        modifier(RefreshIfPresent(action: action))
    }
}
