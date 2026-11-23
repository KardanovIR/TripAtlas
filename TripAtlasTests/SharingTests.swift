import XCTest
@testable import TripAtlas

final class SharingTests: XCTestCase {

    func testSilhouetteIsNormalizedToUnitSquare() {
        let ring = [Coordinate(latitude: 41.85, longitude: 12.45), Coordinate(latitude: 41.85, longitude: 12.65),
                    Coordinate(latitude: 41.95, longitude: 12.65), Coordinate(latitude: 41.95, longitude: 12.45)]
        let boundary = CityBoundary(osmID: "t/1", name: "Рим", polygons: [.init(outer: ring, holes: [])])
        let rings = SilhouetteBuilder.normalize(boundary)
        let points = rings.flatMap { $0 }

        XCTAssertEqual(rings.count, 1)
        XCTAssertTrue(points.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
        // Широкий прямоугольник: заполняет всю ширину и центрирован по высоте.
        XCTAssertEqual(points.map(\.x).min() ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(points.map(\.x).max() ?? -1, 1, accuracy: 1e-9)
        XCTAssertGreaterThan(points.map(\.y).min() ?? 0, 0.1)
    }

    func testSpreadPicksCoverFirstAndEvenlyDistributes() {
        let ids = (0..<100).map { "p\($0)" }
        let picked = ShareComposerModel.spread(ids, count: 5, first: "p42")
        XCTAssertEqual(picked.count, 5)
        XCTAssertEqual(picked.first, "p42")
        XCTAssertEqual(Set(picked).count, 5)
        XCTAssertEqual(ShareComposerModel.spread(["a", "b"], count: 5, first: nil), ["a", "b"])
    }
}
