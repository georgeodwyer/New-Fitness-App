import XCTest
@testable import Kinetix

final class WhatsNewTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "whatsnew.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testEverythingSinceTheLastSeenReleaseIsShown() throws {
        try XCTSkipIf(WhatsNew.releases.count < 3)
        let d = defaults()
        WhatsNew.markSeen(WhatsNew.releases[2], defaults: d)
        let shown = try XCTUnwrap(WhatsNew.pending(isNewInstall: false, defaults: d))
        let expected = (WhatsNew.releases[0].items + WhatsNew.releases[1].items).map(\.title)
        XCTAssertEqual(shown.items.map(\.title), expected)
        XCTAssertEqual(shown.id, WhatsNew.releases[0].id)
        WhatsNew.markSeen(shown, defaults: d)
        XCTAssertNil(WhatsNew.pending(isNewInstall: false, defaults: d))
    }

    func testNewInstallsSeeNothing() {
        let d = defaults()
        XCTAssertNil(WhatsNew.pending(isNewInstall: true, defaults: d))
        XCTAssertNil(WhatsNew.pending(isNewInstall: false, defaults: d))
    }
}
