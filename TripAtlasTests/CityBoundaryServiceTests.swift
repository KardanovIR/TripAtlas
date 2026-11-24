import XCTest
@testable import TripAtlas

final class CityBoundaryServiceTests: XCTestCase {

    // MARK: - Запрос

    /// nginx на сервере пропускает только format=jsonv2, zoom=10 и polygon_geojson=1 (Server/geo/nginx.conf).
    func testRequestIsExactlyWhatTheServerAllows() throws {
        let url = CityBoundaryService.requestURL(latitude: 41.902784, longitude: 12.496366)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "geo.agstatus.online")
        XCTAssertEqual(components.path, "/reverse")

        // nginx сверяет строку запроса целиком, по регулярному выражению, с этим порядком параметров.
        XCTAssertEqual(components.percentEncodedQuery,
                       "format=jsonv2&lat=41.90278&lon=12.49637&zoom=10&polygon_geojson=1&polygon_threshold=0.0005")
    }

    /// Те же граничные случаи, что разрешает регулярное выражение в nginx.conf: знак, три цифры долготы.
    func testRequestFormatsExtremeCoordinates() throws {
        let west = CityBoundaryService.requestURL(latitude: -33.868820, longitude: -151.209296)
        XCTAssertEqual(URLComponents(url: west, resolvingAgainstBaseURL: false)?.percentEncodedQuery,
                       "format=jsonv2&lat=-33.86882&lon=-151.20930&zoom=10&polygon_geojson=1&polygon_threshold=0.0005")
        let north = CityBoundaryService.requestURL(latitude: 78.2232, longitude: 15.6267)
        XCTAssertEqual(URLComponents(url: north, resolvingAgainstBaseURL: false)?.percentEncodedQuery,
                       "format=jsonv2&lat=78.22320&lon=15.62670&zoom=10&polygon_geojson=1&polygon_threshold=0.0005")
    }

    // MARK: - Какие ошибки включают паузу

    func testOfflineErrorsDoNotPauseTheServer() {
        for code in [URLError.Code.notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff,
                     .callIsActive, .networkConnectionLost, .cancelled] {
            XCTAssertFalse(CityBoundaryService.isServerFailure(URLError(code)), "\(code)")
        }
    }

    func testServerSideErrorsPauseTheServer() {
        for code in [URLError.Code.timedOut, .cannotConnectToHost, .cannotFindHost, .badServerResponse,
                     .secureConnectionFailed] {
            XCTAssertTrue(CityBoundaryService.isServerFailure(URLError(code)), "\(code)")
        }
    }

    func testUserAgentNamesTheApp() {
        XCTAssertTrue(CityBoundaryService.userAgent.hasPrefix("TripAtlas/"))
        XCTAssertTrue(CityBoundaryService.userAgent.hasSuffix("; iOS)"))
    }

    // MARK: - Пауза после ошибок

    func testPauseDoublesFromHalfAMinuteUpToAnHour() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var backoff = RetryBackoff()
        var pauses: [TimeInterval] = []
        for _ in 1...9 {
            backoff.recordFailure(at: now)
            pauses.append(backoff.resumeAt!.timeIntervalSince(now))
        }
        XCTAssertEqual(pauses, [30, 60, 120, 240, 480, 960, 1920, 3600, 3600])
    }

    func testRequestsWaitForThePauseToEnd() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var backoff = RetryBackoff()
        XCTAssertTrue(backoff.allows(at: now))

        backoff.recordFailure(at: now)
        XCTAssertFalse(backoff.allows(at: now.addingTimeInterval(29)))
        XCTAssertTrue(backoff.allows(at: now.addingTimeInterval(30)))
    }

    func testSuccessEndsThePause() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var backoff = RetryBackoff()
        backoff.recordFailure(at: now)
        backoff.recordFailure(at: now)
        backoff.recordSuccess()
        XCTAssertTrue(backoff.allows(at: now))
        XCTAssertEqual(backoff.failures, 0)

        backoff.recordFailure(at: now)   // счёт начинается заново
        XCTAssertEqual(backoff.resumeAt?.timeIntervalSince(now), 30)
    }

    func testRetryAfterCanLengthenThePauseButNotBeyondAnHour() {
        let now = Date(timeIntervalSince1970: 1_000_000)

        var longer = RetryBackoff()
        longer.recordFailure(at: now, retryAfter: 600)
        XCTAssertEqual(longer.resumeAt?.timeIntervalSince(now), 600)

        var shorter = RetryBackoff()
        shorter.recordFailure(at: now, retryAfter: 5)
        XCTAssertEqual(shorter.resumeAt?.timeIntervalSince(now), 30)

        var huge = RetryBackoff()
        huge.recordFailure(at: now, retryAfter: 86_400)
        XCTAssertEqual(huge.resumeAt?.timeIntervalSince(now), 3600)

        var negative = RetryBackoff()
        negative.recordFailure(at: now, retryAfter: -10)
        XCTAssertEqual(negative.resumeAt?.timeIntervalSince(now), 30)
    }

    func testManyFailuresStayAtAnHour() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var backoff = RetryBackoff()
        for _ in 0..<200 { backoff.recordFailure(at: now) }
        XCTAssertEqual(backoff.resumeAt?.timeIntervalSince(now), 3600)
    }
}
