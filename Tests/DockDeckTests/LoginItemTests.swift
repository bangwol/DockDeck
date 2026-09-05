import XCTest
@testable import DockDeck

final class LoginItemTests: XCTestCase {
    func testLoginChangesUseActualOSStateAndAreIdempotent() {
        let service = TestLoginService()
        let store = LoginItemStore(service: service)
        XCTAssertTrue(store.setEnabled(false))
        XCTAssertEqual(service.unregisterCount, 0)
        XCTAssertTrue(store.setEnabled(true))
        XCTAssertTrue(store.setEnabled(true))
        XCTAssertEqual(service.registerCount, 1)
        service.status = .requiresApproval
        XCTAssertTrue(store.setEnabled(true))
        XCTAssertEqual(store.status, .requiresApproval)
        XCTAssertEqual(service.registerCount, 1)
        XCTAssertTrue(store.setEnabled(false))
        XCTAssertEqual(service.unregisterCount, 1)
        XCTAssertEqual(store.status, .notRegistered)
    }

    func testFailureKeepsActualStatusAndRefreshReadsExternalChanges() {
        let service = TestLoginService()
        let store = LoginItemStore(service: service)
        service.fails = true
        XCTAssertFalse(store.setEnabled(true))
        XCTAssertEqual(store.status, .notRegistered)
        XCTAssertNotNil(store.error)
        service.status = .enabled
        store.refresh()
        XCTAssertEqual(store.status, .enabled)
        XCTAssertFalse(store.setEnabled(false))
        XCTAssertEqual(store.status, .enabled)
    }

    func testControlRequiresOneExactArgument() {
        XCTAssertEqual(DockDeckControl.parse(["--login-item-status"]), .loginStatus)
        XCTAssertEqual(DockDeckControl.parse(["--stop-installed-app"]), .stopInstalled)
        for arguments in [[], ["--enable-login-item", "extra"], ["--login-item-status=1"], ["--unknown"]] {
            XCTAssertNil(DockDeckControl.parse(arguments))
        }
    }
}

private final class TestLoginService: LoginItemControlling {
    var status: LoginItemStatus = .notRegistered
    var registerCount = 0
    var unregisterCount = 0
    var fails = false
    func register() throws {
        registerCount += 1
        if fails { throw CocoaError(.fileWriteNoPermission) }
        status = .enabled
    }
    func unregister() throws {
        unregisterCount += 1
        if fails { throw CocoaError(.fileWriteNoPermission) }
        status = .notRegistered
    }
}
