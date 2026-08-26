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

    @MainActor
    func testIOS15PlayerChromeLyricsAndQueue() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-KumonePlayerPreview")
        app.launch()

        XCTAssertTrue(app.buttons["歌词"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["播放队列"].exists)
        XCTAssertTrue(app.buttons["静音"].exists)
        XCTAssertTrue(app.staticTexts["当前音源：测试内置音源"].exists)

        let playbackMode = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "播放模式：")).firstMatch
        XCTAssertTrue(playbackMode.exists, "紧凑播放器缺少播放模式图标")

        let speedButton = app.buttons["播放倍速：1.0x"]
        XCTAssertTrue(speedButton.exists, "紧凑播放器缺少倍速按钮")
        speedButton.tap()
        XCTAssertTrue(app.buttons["播放倍速：1.25x"].waitForExistence(timeout: 3))

        app.buttons["播放队列"].tap()
        XCTAssertTrue(app.navigationBars["播放队列 2 首"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["正在播放"].exists)
        XCTAssertTrue(app.staticTexts["队列测试歌曲"].exists)
        app.buttons["完成"].tap()

        app.buttons["歌词"].tap()
        XCTAssertTrue(app.navigationBars["播放器测试歌曲"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["当前音源：测试内置音源"].exists)
    }
}
