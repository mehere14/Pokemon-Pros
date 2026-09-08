import Testing
@testable import Battle_Card_Dex

@Test("carousel honors threshold, flick, and boundaries")
func carouselThresholds() {
    let model = CarouselInteractionModel(constants: .standard)
    #expect(model.decide(translation: -80, duration: 0.5, index: 1, count: 3, width: 390) == .stay)
    #expect(model.decide(translation: -86, duration: 0.5, index: 1, count: 3, width: 390) == .move(by: 1))
    #expect(model.decide(translation: -40, duration: 0.2, index: 1, count: 3, width: 390) == .move(by: 1))
    #expect(model.decide(translation: 100, duration: 0.5, index: 0, count: 3, width: 390) == .boundary)
}

@Test("panels use independent open and close thresholds")
func panelThresholds() {
    let model = PanelInteractionModel(constants: .standard)
    #expect(model.openingDecision(travel: 20, extent: 100) == .remainClosed)
    #expect(model.openingDecision(travel: 22, extent: 100) == .open)
    #expect(model.closingDecision(travel: 11, extent: 100) == .open)
    #expect(model.closingDecision(travel: 12, extent: 100) == .close)
}

@Test("card tilt follows touch position and recenters")
func cardTilt() {
    let model = CardTiltInteractionModel()
    #expect(model.state(locationX: 0, locationY: 0, width: 200, height: 300) == CardTiltState(rotationX: 6, rotationY: -6, glareX: 0, glareY: 0))
    #expect(model.state(locationX: 200, locationY: 300, width: 200, height: 300) == CardTiltState(rotationX: -6, rotationY: 6, glareX: 1, glareY: 1))
    #expect(model.state(locationX: 100, locationY: 150, width: 200, height: 300) == model.restingState)
}
