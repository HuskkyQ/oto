import ObjectiveC
import SwiftUI
import UIKit

/// The custom header hides the navigation bar, which also turns off UIKit's interactive pop.
/// This turns it back on so a drag from the leading edge moves the page with the finger.
private struct InteractiveBackBridge: UIViewRepresentable {
    func makeUIView(context: Context) -> BridgeView {
        let view = BridgeView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.onAttach = { install(on: $0) }
        return view
    }

    func updateUIView(_ uiView: BridgeView, context: Context) {
        install(on: uiView)
    }

    final class BridgeView: UIView {
        var onAttach: ((UIView) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { onAttach?(self) }
        }
    }
}

/// Lives as long as the navigation controller, so the recognizer never loses its gate when
/// a page is dismantled mid-transition.
private final class BackGestureGate: NSObject, UIGestureRecognizerDelegate {
    private weak var navigation: UINavigationController?

    init(navigation: UINavigationController) {
        self.navigation = navigation
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let navigation,
              gestureRecognizer === navigation.interactivePopGestureRecognizer
        else { return false }
        // Never let the gesture start on the root page, and never re-enter a running transition.
        return navigation.viewControllers.count > 1 && navigation.transitionCoordinator == nil
    }
}

private enum BackGestureAssociation {
    static var key: UInt8 = 0
}

@MainActor
private func install(on view: UIView) {
    guard let navigation = view.nearestNavigationController(),
          let gesture = navigation.interactivePopGestureRecognizer
    else { return }

    let gate: BackGestureGate
    if let existing = objc_getAssociatedObject(navigation, &BackGestureAssociation.key) as? BackGestureGate {
        gate = existing
    } else {
        gate = BackGestureGate(navigation: navigation)
        objc_setAssociatedObject(navigation, &BackGestureAssociation.key, gate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    if gesture.delegate !== gate { gesture.delegate = gate }
    // Hiding the bar switches the recognizer off; the page's own header replaces it.
    if !gesture.isEnabled { gesture.isEnabled = true }
}

private extension UIView {
    func nearestNavigationController() -> UINavigationController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController {
                if let navigation = controller as? UINavigationController { return navigation }
                if let navigation = controller.navigationController { return navigation }
            }
            responder = current.next
        }
        return nil
    }
}

private struct InteractiveBackModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background {
            InteractiveBackBridge()
                .frame(width: 0, height: 0)
        }
    }
}

extension View {
    /// Gives a pushed page the system's interactive pop, which the hidden navigation bar removes.
    func interactiveBackEnabled() -> some View {
        modifier(InteractiveBackModifier())
    }
}
