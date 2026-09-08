import Foundation

struct InteractionConstants: Equatable, Sendable {
    let carouselCommitFraction: Double
    let carouselFingerTravelMultiplier: Double
    let carouselMaximumScaleReduction: Double
    let flickMaximumDuration: TimeInterval
    let flickMinimumDistance: Double
    let panelDirectionDetectionDistance: Double
    let panelOpenFraction: Double
    let panelCloseFraction: Double
    let panelProgressTravelFraction: Double
    let clickSuppressionDistance: Double
    let horizontalWheelMinimumDistance: Double

    static let standard = InteractionConstants(
        carouselCommitFraction: 0.22,
        carouselFingerTravelMultiplier: 0.82,
        carouselMaximumScaleReduction: 0.06,
        flickMaximumDuration: 0.280,
        flickMinimumDistance: 34,
        panelDirectionDetectionDistance: 6,
        panelOpenFraction: 0.22,
        panelCloseFraction: 0.12,
        panelProgressTravelFraction: 0.42,
        clickSuppressionDistance: 8,
        horizontalWheelMinimumDistance: 20
    )
}
