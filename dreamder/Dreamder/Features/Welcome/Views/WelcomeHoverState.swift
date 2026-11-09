import Observation

@Observable
final class WelcomeHoverState {
    private(set) var isHovering: Bool

    init(isHovering: Bool = false) {
        self.isHovering = isHovering
    }

    func setHovering(_ hovering: Bool) {
        isHovering = hovering
    }
}
