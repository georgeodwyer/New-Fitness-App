import XCTest
@testable import TrainingEngine

final class SocialTests: XCTestCase {
    /// A straight line north from (51.5, -0.1), one point every 10 m.
    private func line(meters: Int) -> [RoutePoint] {
        (0...(meters / 10)).map { i in
            let (lat, lon) = Geo.offset(latitude: 51.5, longitude: -0.1, northMeters: Double(i * 10), eastMeters: 0)
            return RoutePoint(latitude: lat, longitude: lon, elapsed: Double(i * 3))
        }
    }

    func testTrimsTwoHundredMetresAtEachEnd() throws {
        let route = line(meters: 2000)
        let kept = try XCTUnwrap(RoutePrivacy.trimmed(route))
        let first = kept.first!, last = kept.last!
        XCTAssertGreaterThanOrEqual(Geo.distance(first[0], first[1], route.first!.latitude, route.first!.longitude), 199)
        XCTAssertGreaterThanOrEqual(Geo.distance(last[0], last[1], route.last!.latitude, route.last!.longitude), 199)
        XCTAssertLessThan(Geo.distance(first[0], first[1], route.first!.latitude, route.first!.longitude), 220)
        // Nothing left within 200 m of either end.
        for point in kept {
            XCTAssertGreaterThanOrEqual(Geo.distance(point[0], point[1], route.first!.latitude, route.first!.longitude), 199)
            XCTAssertGreaterThanOrEqual(Geo.distance(point[0], point[1], route.last!.latitude, route.last!.longitude), 199)
        }
    }

    func testLoopPassingHomeHidesHomeMidRun() throws {
        // Out 1 km, back home, out 1 km again, back home.
        let out = line(meters: 1000)
        let route = out + out.reversed() + out + out.reversed()
        let kept = try XCTUnwrap(RoutePrivacy.trimmed(route, maxPoints: 10_000))
        for point in kept {
            XCTAssertGreaterThanOrEqual(Geo.distance(point[0], point[1], 51.5, -0.1), 199)
        }
    }

    func testShortRunsHaveNoMap() {
        XCTAssertNil(RoutePrivacy.trimmed(line(meters: 300)))
        XCTAssertNil(RoutePrivacy.trimmed([]))
    }

    func testThinsLongRoutes() throws {
        let kept = try XCTUnwrap(RoutePrivacy.trimmed(line(meters: 20_000), maxPoints: 100))
        XCTAssertLessThanOrEqual(kept.count, 101)
        XCTAssertGreaterThan(kept.count, 50)
    }

    func testUsernames() {
        XCTAssertNil(Username.problem("Ann_Runs"))
        XCTAssertEqual(Username.normalised(" Ann_Runs "), "ann_runs")
        XCTAssertNotNil(Username.problem("ab"))
        XCTAssertNotNil(Username.problem("a b c"))
        XCTAssertNotNil(Username.problem("émile"))
        XCTAssertNotNil(Username.problem(String(repeating: "a", count: 21)))
    }

    func testFriendLinks() {
        XCTAssertEqual(FriendLink.normalisedCode("gxqd-rn26"), "GXQDRN26")
        XCTAssertNil(FriendLink.normalisedCode("GXQDRN20"))   // 0 isn't used
        XCTAssertNil(FriendLink.normalisedCode("SHORT"))
        let url = FriendLink.url(code: "GXQDRN26")!
        XCTAssertEqual(url.absoluteString, "kinetix://friend/GXQDRN26")
        XCTAssertEqual(FriendLink.code(from: url), "GXQDRN26")
        XCTAssertNil(FriendLink.code(from: URL(string: "kinetix://tab/plan")!))
        XCTAssertEqual(FriendLink.code(fromText: "kinetix://friend/GXQDRN26"), "GXQDRN26")
        XCTAssertEqual(FriendLink.code(fromText: " gxqdrn26 "), "GXQDRN26")
    }
}
