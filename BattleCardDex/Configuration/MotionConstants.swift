import Foundation

struct MotionCurve: Equatable, Sendable {
    let firstControlPoint: (x: Double, y: Double)
    let secondControlPoint: (x: Double, y: Double)

    static func == (lhs: MotionCurve, rhs: MotionCurve) -> Bool {
        lhs.firstControlPoint.x == rhs.firstControlPoint.x
            && lhs.firstControlPoint.y == rhs.firstControlPoint.y
            && lhs.secondControlPoint.x == rhs.secondControlPoint.x
            && lhs.secondControlPoint.y == rhs.secondControlPoint.y
    }
}

struct MotionConstants: Equatable, Sendable {
    let standardCurve: MotionCurve
    let panelCurve: MotionCurve
    let carouselDuration: TimeInterval
    let boundaryBumpDuration: TimeInterval
    let panelDuration: TimeInterval
    let shuffleDuration: TimeInterval
    let modalReturnDuration: TimeInterval
    let scrimDuration: TimeInterval
    let quickControlDuration: TimeInterval
    let entranceDuration: TimeInterval
    let entranceStagger: TimeInterval
    let reducedMotionDuration: TimeInterval

    static let standard = MotionConstants(
        standardCurve: MotionCurve(
            firstControlPoint: (x: 0.22, y: 0.82),
            secondControlPoint: (x: 0.24, y: 1)
        ),
        panelCurve: MotionCurve(
            firstControlPoint: (x: 0.2, y: 0.9),
            secondControlPoint: (x: 0.24, y: 1)
        ),
        carouselDuration: 0.460,
        boundaryBumpDuration: 0.220,
        panelDuration: 0.420,
        shuffleDuration: 0.480,
        modalReturnDuration: 0.420,
        scrimDuration: 0.180,
        quickControlDuration: 0.150,
        entranceDuration: 0.540,
        entranceStagger: 0.090,
        reducedMotionDuration: 0.001
    )
}
