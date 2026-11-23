import XCTest
@testable import TripAtlas

final class FlyoverTests: XCTestCase {

    private func city(_ name: String, _ lat: Double, _ lon: Double, order: Int) -> FlyoverCity {
        let center = Mercator.project(latitude: lat, longitude: lon)
        return FlyoverCity(name: name, subtitle: "🇮🇹 Италия", order: order, center: center, rings: [],
                           circles: [FlyoverCircle(center: center, radius: Mercator.units(km: 4, latitude: lat))],
                           photoIDs: [], photoDates: [])
    }

    private var italy: [FlyoverCity] {
        [city("Рим", 41.9, 12.5, order: 1), city("Флоренция", 43.77, 11.25, order: 2), city("Венеция", 45.44, 12.33, order: 3)]
    }

    func testMercatorRoundTrip() {
        let p = Mercator.project(latitude: 55.75, longitude: 37.62)
        let c = Mercator.unproject(p)
        XCTAssertEqual(c.latitude, 55.75, accuracy: 1e-9)
        XCTAssertEqual(c.longitude, 37.62, accuracy: 1e-9)
        XCTAssertEqual(Mercator.project(latitude: 0, longitude: 0).y, 0.5, accuracy: 1e-12)
    }

    func testPhasesCoverWholeTimeline() {
        let script = FlyoverScript(cities: italy, pace: .calm)
        XCTAssertEqual(script.phase(at: 0), .intro(t: 0))
        XCTAssertEqual(script.phase(at: script.stayStart(1) + 0.01).cityIndex, 1)
        if case .outroHold = script.phase(at: script.duration - 0.01) {} else { XCTFail("должен быть финал") }
        XCTAssertEqual(script.frameCount, Int((script.duration * 30).rounded(.up)))
        XCTAssertGreaterThan(script.duration, 10)
        XCTAssertLessThan(script.duration, 30)
    }

    func testCameraIsContinuousBetweenPhases() {
        let script = FlyoverScript(cities: italy, pace: .dynamic)
        for t in [script.intro, script.stayStart(0), script.flyStart(1), script.stayStart(2), script.outroStart] {
            let before = script.camera(at: t - 0.0001), after = script.camera(at: t + 0.0001)
            XCTAssertEqual(before.width, after.width, accuracy: before.width * 0.02, "скачок ширины в \(t)")
            XCTAssertEqual(Double(before.center.x), Double(after.center.x), accuracy: before.width * 0.02)
        }
    }

    func testFlyZoomsOutOnLongDistance() {
        let a = italy[0].camera, b = italy[2].camera
        let mid = FlyCamera.fly(from: a, to: b, t: 0.5)
        XCTAssertGreaterThan(mid.width, max(a.width, b.width))
        XCTAssertEqual(FlyCamera.fly(from: a, to: b, t: 1).width, b.width, accuracy: 1e-12)
    }

    func testOverviewContainsAllCities() {
        let overview = FlyoverScript.overview(for: italy).rect
        for c in italy { XCTAssertTrue(overview.contains(c.center), c.name) }
    }
}

private extension FlyoverScript.Phase {
    var cityIndex: Int? {
        if case .stay(let city, _) = self { return city }
        return nil
    }
}
