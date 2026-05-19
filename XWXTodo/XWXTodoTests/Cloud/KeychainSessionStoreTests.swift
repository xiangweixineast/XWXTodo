import XCTest
@testable import XWXTodo

final class KeychainSessionStoreTests: XCTestCase {
    private var store: KeychainSessionStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        store = KeychainSessionStore(
            service: "com.komavideo.XWXTodoTests.\(UUID().uuidString)",
            account: "bearer-token"
        )
        try? store.deleteToken()
    }

    override func tearDownWithError() throws {
        try? store.deleteToken()
        store = nil
        try super.tearDownWithError()
    }

    func testSaveLoadOverwriteAndDeleteToken() throws {
        XCTAssertNil(try store.loadToken())

        try store.saveToken("first-token")
        XCTAssertEqual(try store.loadToken(), "first-token")

        try store.saveToken("second-token")
        XCTAssertEqual(try store.loadToken(), "second-token")

        try store.deleteToken()
        XCTAssertNil(try store.loadToken())
    }

    func testDeletingMissingTokenSucceeds() throws {
        try store.deleteToken()
        XCTAssertNil(try store.loadToken())
    }
}
