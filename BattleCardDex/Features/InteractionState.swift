import Foundation

enum CarouselDecision: Equatable, Sendable { case stay; case move(by: Int); case boundary }

struct CarouselInteractionModel: Sendable {
    let constants: InteractionConstants

    func decide(translation: Double, duration: TimeInterval, index: Int, count: Int, width: Double) -> CarouselDecision {
        guard count > 0 else { return .stay }
        let threshold = width * constants.carouselCommitFraction
        let flick = duration < constants.flickMaximumDuration && abs(translation) >= constants.flickMinimumDistance
        guard abs(translation) >= threshold || flick else { return .stay }
        let delta = translation < 0 ? 1 : -1
        let next = index + delta
        return (0..<count).contains(next) ? .move(by: delta) : .boundary
    }
}

enum PanelDecision: Equatable, Sendable { case remainClosed; case open; case close }

struct PanelInteractionModel: Sendable {
    let constants: InteractionConstants

    func openingDecision(travel: Double, extent: Double) -> PanelDecision {
        travel / max(1, extent) >= constants.panelOpenFraction ? .open : .remainClosed
    }

    func closingDecision(travel: Double, extent: Double) -> PanelDecision {
        travel / max(1, extent) >= constants.panelCloseFraction ? .close : .open
    }
}

struct CardTiltState: Equatable, Sendable {
    let rotationX: Double
    let rotationY: Double
    let glareX: Double
    let glareY: Double
}

struct CardTiltInteractionModel: Sendable {
    let maximumAngle: Double

    init(maximumAngle: Double = 6) {
        self.maximumAngle = maximumAngle
    }

    func state(locationX: Double, locationY: Double, width: Double, height: Double) -> CardTiltState {
        let x = min(max(locationX / max(width, 1), 0), 1)
        let y = min(max(locationY / max(height, 1), 0), 1)
        return CardTiltState(
            rotationX: (0.5 - y) * maximumAngle * 2,
            rotationY: (x - 0.5) * maximumAngle * 2,
            glareX: x,
            glareY: y
        )
    }

    var restingState: CardTiltState {
        CardTiltState(rotationX: 0, rotationY: 0, glareX: 0.5, glareY: 0.5)
    }
}
