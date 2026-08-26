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

        let speedButton = app.buttons["ios15-player-rate"]
        XCTAssertTrue(speedButton.waitForExistence(timeout: 8), "紧凑播放器缺少倍速按钮")
        speedButton.tap()
        XCTAssertTrue(speedButton.label.contains("1.25×"), "倍速按钮未切换到 1.25×")
        XCTAssertTrue(app.buttons["下一曲"].exists)
        XCTAssertTrue(app.buttons["暂停"].exists)

        let moreButton = app.buttons["更多播放控制"]
        XCTAssertTrue(moreButton.exists, "紧凑播放器缺少更多控制入口")
        moreButton.tap()
        let playbackMode = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "切换播放模式（")).firstMatch
        XCTAssertTrue(playbackMode.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["播放队列"].exists)
        app.buttons["播放队列"].tap()

        XCTAssertTrue(app.navigationBars["播放队列 2 首"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["正在播放"].exists)
        XCTAssertTrue(app.staticTexts["队列测试歌曲"].exists)
        app.buttons["完成"].tap()

        moreButton.tap()
        app.buttons["歌词"].tap()
        XCTAssertTrue(app.navigationBars["播放器测试歌曲"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["当前音源：测试内置音源"].exists)
    }

    @MainActor
    func testRecentPlaybackPageShowsPersistedHistoryMetadata() throws {
        let recorder = XCUIApplication()
        recorder.launchArguments.append("-KumoneHistoryRecordPreview")
        recorder.launch()
        recorder.terminate()

        let app = XCUIApplication()
        app.launch()

        let profileTab = app.buttons["我的"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 8))
        profileTab.tap()

        let recentPlays = app.buttons["最近播放"]
        XCTAssertTrue(recentPlays.waitForExistence(timeout: 5))
        recentPlays.tap()

        XCTAssertTrue(app.navigationBars["最近播放"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["播放全部"].exists)
        XCTAssertTrue(app.staticTexts["播放器测试歌曲"].exists)
        XCTAssertTrue(app.staticTexts["3 次"].exists)
        XCTAssertTrue(app.buttons["最近播放：播放器测试歌曲，3 次"].exists)
        XCTAssertTrue(app.buttons["所有时间"].exists)
        XCTAssertTrue(app.buttons["最近一周"].exists)
    }
}
