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

    func testYearWithHomeGoesBackHomeBetweenTrips() {
        var home = city("Москва", 55.75, 37.62, order: 0)
        home.isHome = true
        let trips = [city("Рим", 41.9, 12.5, order: 1), city("Токио", 35.68, 139.69, order: 2)]
        let stops = [home, trips[0], home, trips[1], home]
        let script = FlyoverScript(cities: stops, pace: .calm)

        XCTAssertEqual(script.visitNumber(1).0, 1)
        XCTAssertEqual(script.visitNumber(3).0, 2)
        XCTAssertEqual(script.visitNumber(3).1, 2)
        XCTAssertLessThan(script.stayDurations[2], script.stayDurations[1])   // дома — короткая пересадка
        XCTAssertTrue(script.overview.rect.contains(home.center))
        let t = script.stayStart(2)
        XCTAssertEqual(script.camera(at: t - 0.0001).width, script.camera(at: t + 0.0001).width,
                       accuracy: script.camera(at: t).width * 0.02)
    }

    func testHomeResolverGivesHomePerYear() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)   // ноябрь 2023
        let samples = (0..<40).map { day in
            PhotoSample(id: "h\(day)", date: base.addingTimeInterval(Double(day) * 86_400),
                        latitude: 55.75, longitude: 37.62)
        }
        let homes = HomeResolver(samples: samples, config: .init()).homes(for: [2023, 2024])
        XCTAssertEqual(homes[2023]?.latitude ?? 0, 55.75, accuracy: 0.01)
        XCTAssertNotNil(homes[2024])   // своих фото за 2024 нет — берётся общий дом
    }
}

private extension FlyoverScript.Phase {
    var cityIndex: Int? {
        if case .stay(let city, _) = self { return city }
        return nil
    }
}
