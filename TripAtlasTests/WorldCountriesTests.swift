import XCTest
@testable import TripAtlas

final class WorldCountriesTests: XCTestCase {

    func testHas195Countries() {
        XCTAssertEqual(WorldCountries.total, 195)
        XCTAssertEqual(WorldCountries.list(including: []).count, 195)
    }

    func testVisitedTerritoryIsAddedButNotSovereign() {
        let list = WorldCountries.list(including: ["HK", "FR"])
        XCTAssertEqual(list.count, 196)
        XCTAssertEqual(list.first { $0.code == "HK" }?.isSovereign, false)
        XCTAssertEqual(list.first { $0.code == "FR" }?.isSovereign, true)
    }

    func testContinents() {
        XCTAssertEqual(WorldCountries.continent(for: "FR"), .europe)
        XCTAssertEqual(WorldCountries.continent(for: "RU"), .europe)
        XCTAssertEqual(WorldCountries.continent(for: "JP"), .asia)
        XCTAssertEqual(WorldCountries.continent(for: "EG"), .africa)
        XCTAssertEqual(WorldCountries.continent(for: "US"), .northAmerica)
        XCTAssertEqual(WorldCountries.continent(for: "MX"), .northAmerica)
        XCTAssertEqual(WorldCountries.continent(for: "CU"), .northAmerica)
        XCTAssertEqual(WorldCountries.continent(for: "BR"), .southAmerica)
        XCTAssertEqual(WorldCountries.continent(for: "AU"), .oceania)
    }

    func testEveryCountryHasContinent() {
        let unknown = WorldCountries.sovereignCodes.filter { WorldCountries.continent(for: $0) == .other }
        XCTAssertTrue(unknown.isEmpty, "Без части света: \(unknown.sorted())")
    }
}
