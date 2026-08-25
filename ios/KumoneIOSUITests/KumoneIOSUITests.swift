import XCTest

final class KumoneIOSUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOriginalTabSetIsPresentAndReachable() throws {
        let app = XCUIApplication()
        app.launch()

        let originalTabs = ["推荐", "精选", "漫游", "搜索", "我的"]
        for title in originalTabs {
            let tab = app.buttons[title]
            XCTAssertTrue(tab.waitForExistence(timeout: 8), "缺少原版标签入口：\(title)")
            tab.tap()
        }

        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 5))
    }
}
