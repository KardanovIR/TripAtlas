import XCTest
@testable import TripAtlas

final class CityBoundaryTests: XCTestCase {

    /// Квадрат ~11×11 км вокруг (41.9, 12.5) с «дыркой» в центре.
    private let polygonJSON = """
    {"osm_type":"relation","osm_id":41485,"name":"Roma","addresstype":"city",
     "geojson":{"type":"Polygon","coordinates":[
       [[12.45,41.85],[12.55,41.85],[12.55,41.95],[12.45,41.95],[12.45,41.85]],
       [[12.49,41.89],[12.51,41.89],[12.51,41.91],[12.49,41.91],[12.49,41.89]]
     ]}}
    """

    func testParsesPolygonWithHole() throws {
        let boundary = try XCTUnwrap(OSMBoundaryParser.parse(Data(polygonJSON.utf8)))
        XCTAssertEqual(boundary.osmID, "relation/41485")
        XCTAssertEqual(boundary.polygons.count, 1)
        XCTAssertEqual(boundary.polygons[0].holes.count, 1)
        XCTAssertEqual(boundary.areaKm2, 92, accuracy: 6)   // 8.3 × 11.1 км минус дырка

        XCTAssertTrue(boundary.contains(Coordinate(latitude: 41.87, longitude: 12.47)))
        XCTAssertFalse(boundary.contains(Coordinate(latitude: 41.90, longitude: 12.50)))  // в дырке
        XCTAssertFalse(boundary.contains(Coordinate(latitude: 42.10, longitude: 12.50)))  // снаружи
    }

    func testParsesMultiPolygon() throws {
        let json = """
        {"osm_type":"relation","osm_id":1,"geojson":{"type":"MultiPolygon","coordinates":[
          [[[0,0],[0.1,0],[0.1,0.1],[0,0.1],[0,0]]],
          [[[1,1],[1.1,1],[1.1,1.1],[1,1.1],[1,1]]]
        ]}}
        """
        let boundary = try XCTUnwrap(OSMBoundaryParser.parse(Data(json.utf8)))
        XCTAssertEqual(boundary.polygons.count, 2)
        XCTAssertEqual(boundary.makeMKPolygons().count, 2)
    }

    func testPointOrErrorMeansNoBoundary() throws {
        let point = #"{"osm_type":"node","osm_id":5,"geojson":{"type":"Point","coordinates":[12.5,41.9]}}"#
        XCTAssertNil(try OSMBoundaryParser.parse(Data(point.utf8)))
        XCTAssertNil(try OSMBoundaryParser.parse(Data(#"{"error":"Unable to geocode"}"#.utf8)))
    }

    func testRejectsRegionSizedPolygons() throws {
        // ~3°×3° ≈ 80 000 км² — это область, а не город.
        let json = #"{"osm_type":"relation","osm_id":2,"geojson":{"type":"Polygon","coordinates":[[[10,40],[13,40],[13,43],[10,43],[10,40]]]}}"#
        XCTAssertNil(try OSMBoundaryParser.parse(Data(json.utf8)))
    }

    func testSimplifyKeepsShapeAndLimitsPoints() {
        // Окружность из 5000 точек.
        let ring = (0..<5000).map { i -> Coordinate in
            let a = Double(i) / 5000 * 2 * .pi
            return Coordinate(latitude: 41.9 + 0.1 * sin(a), longitude: 12.5 + 0.1 * cos(a))
        }
        let simplified = GeoPolygon.simplify(ring, maxPoints: 700)
        XCTAssertLessThanOrEqual(simplified.count, 700)
        XCTAssertGreaterThan(simplified.count, 20)
        XCTAssertEqual(GeoPolygon.areaKm2(simplified), GeoPolygon.areaKm2(ring), accuracy: GeoPolygon.areaKm2(ring) * 0.02)
    }
}
