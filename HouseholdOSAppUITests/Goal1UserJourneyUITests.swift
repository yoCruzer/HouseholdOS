import XCTest

@MainActor
final class Goal1UserJourneyUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDraftToSearchEditArchiveAndRelaunchJourney() throws {
        let app = englishApp()
        app.launchEnvironment["HOUSEHOLDOS_UI_TESTING"] = "1"
        app.launchEnvironment["HOUSEHOLDOS_UI_TEST_RESET"] = "1"
        app.launch()

        XCTAssertTrue(app.staticTexts["No items yet"].waitForExistence(timeout: 10))

        app.tabBars.buttons["Add"].tap()
        XCTAssertTrue(app.buttons["capture.photoLibrary"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["capture.photoLibrary"].isEnabled)
        XCTAssertTrue(app.buttons["capture.camera"].exists)
        XCTAssertFalse(app.buttons["capture.camera"].isEnabled)

        app.buttons["capture.photoLibrary"].tap()
        let pickerCancel = app.buttons["Cancel"]
        if pickerCancel.waitForExistence(timeout: 5) {
            pickerCancel.tap()
        } else {
            app.swipeDown()
        }
        XCTAssertTrue(app.buttons["capture.manual"].waitForExistence(timeout: 5))

        app.buttons["capture.manual"].tap()
        let nameField = app.textFields["record.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Cordless Drill")
        app.buttons["draft.save"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["draft.saveSuccess"]
                .waitForExistence(timeout: 5)
        )

        app.terminate()
        app.launchEnvironment["HOUSEHOLDOS_UI_TEST_RESET"] = "0"
        app.launch()

        app.tabBars.buttons["Drafts"].tap()
        XCTAssertTrue(app.staticTexts["Cordless Drill"].waitForExistence(timeout: 10))
        app.staticTexts["Cordless Drill"].tap()
        app.swipeUp()
        XCTAssertTrue(app.buttons["draft.confirm"].waitForExistence(timeout: 5))
        app.buttons["draft.confirm"].tap()

        XCTAssertTrue(app.staticTexts["Cordless Drill"].waitForExistence(timeout: 10))

        let searchField = app.searchFields.firstMatch
        searchField.tap()
        searchField.typeText("drill")
        XCTAssertTrue(app.staticTexts["Cordless Drill"].exists)
        searchField.buttons["Clear text"].tap()
        searchField.typeText("not-present")
        XCTAssertTrue(app.staticTexts["No matching items"].waitForExistence(timeout: 5))
        searchField.buttons["Clear text"].tap()

        let itemRow = app.staticTexts.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "item.row.")
        ).firstMatch
        XCTAssertTrue(itemRow.waitForExistence(timeout: 5))
        XCTAssertTrue(itemRow.isHittable)
        itemRow.tap()
        app.buttons["item.edit"].tap()

        let itemNameField = app.textFields["record.name"]
        XCTAssertTrue(itemNameField.waitForExistence(timeout: 5))
        itemNameField.tap()
        itemNameField.typeText(" Unsaved")
        app.swipeUp()
        if !app.staticTexts["item.savingSemantics"].exists {
            app.swipeUp()
        }
        XCTAssertTrue(
            app.staticTexts["item.savingSemantics"].waitForExistence(timeout: 5)
        )
        app.buttons["item.close"].tap()
        XCTAssertTrue(app.staticTexts["Cordless Drill"].waitForExistence(timeout: 5))

        app.buttons["item.edit"].tap()
        let reopenedNameField = app.textFields["record.name"]
        XCTAssertTrue(reopenedNameField.waitForExistence(timeout: 5))
        XCTAssertEqual(reopenedNameField.value as? String, "Cordless Drill")
        reopenedNameField.tap()
        reopenedNameField.typeText(" Impact")
        app.buttons["item.save"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["item.saveSuccess"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["Cordless Drill Impact"].waitForExistence(timeout: 5))

        app.terminate()
        app.launch()
        let itemsTab = app.tabBars.buttons["Items"]
        itemsTab.tap()
        let selectedItemsTab = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isSelected == true"),
            object: itemsTab
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [selectedItemsTab], timeout: 5),
            .completed
        )
        XCTAssertTrue(app.navigationBars["Items"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["Cordless Drill Impact"].waitForExistence(timeout: 10)
        )

        let persistedItemRow = app.staticTexts.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "item.row.")
        ).firstMatch
        XCTAssertTrue(persistedItemRow.waitForExistence(timeout: 5))
        XCTAssertTrue(persistedItemRow.isHittable)
        persistedItemRow.tap()
        XCTAssertTrue(app.buttons["More actions"].waitForExistence(timeout: 5))
        app.buttons["More actions"].tap()
        XCTAssertTrue(app.buttons["Archive Item"].waitForExistence(timeout: 5))
        app.buttons["Archive Item"].tap()
        app.navigationBars.buttons["Items"].tap()
        let archivedItemRow = app.staticTexts.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "item.row.")
        ).firstMatch
        XCTAssertFalse(archivedItemRow.waitForExistence(timeout: 2))

        app.buttons["items.filters"].tap()
        let includeArchived = app.buttons["Include Archived"]
        if !includeArchived.exists {
            app.swipeUp()
        }
        XCTAssertTrue(includeArchived.waitForExistence(timeout: 5))
        includeArchived.tap()
        XCTAssertTrue(archivedItemRow.waitForExistence(timeout: 5))
    }

    func testDraftDeleteUIReportsResidualFilesAfterRecordRemoval() throws {
        let app = deletionFixtureApp(kind: "draft")
        app.launch()

        app.tabBars.buttons["Drafts"].tap()
        let draft = app.staticTexts["Residual Draft"]
        XCTAssertTrue(draft.waitForExistence(timeout: 10))
        XCTAssertTrue(app.images["Item photo"].waitForExistence(timeout: 10))
        draft.tap()
        XCTAssertTrue(app.buttons["More actions"].waitForExistence(timeout: 5))
        app.buttons["More actions"].tap()
        let deleteDraftButton = app.buttons["Delete Draft"].firstMatch
        XCTAssertTrue(deleteDraftButton.waitForExistence(timeout: 5))
        deleteDraftButton.tap()
        let draftDeleteConfirmation = app.buttons["Delete Draft Permanently"].firstMatch
        XCTAssertTrue(
            draftDeleteConfirmation.waitForExistence(timeout: 5)
        )
        draftDeleteConfirmation.tap()

        XCTAssertTrue(
            app.staticTexts["Draft record deleted"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            residualFileMessage(in: app).waitForExistence(timeout: 5)
        )
        XCTAssertFalse(app.staticTexts["Delete failed"].exists)
        app.buttons["OK"].tap()
        XCTAssertFalse(draft.waitForExistence(timeout: 2))
    }

    func testItemDeleteUIReportsResidualFilesAfterRecordRemoval() throws {
        let app = deletionFixtureApp(kind: "item")
        app.launch()

        let item = app.staticTexts["Residual Item"]
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        item.tap()
        XCTAssertTrue(app.buttons["More actions"].waitForExistence(timeout: 5))
        app.buttons["More actions"].tap()
        XCTAssertTrue(app.buttons["item.delete"].waitForExistence(timeout: 5))
        app.buttons["item.delete"].tap()
        XCTAssertTrue(
            app.buttons["item.delete.confirm"].waitForExistence(timeout: 5)
        )
        app.buttons["item.delete.confirm"].firstMatch.tap()

        XCTAssertTrue(
            app.staticTexts["Item record deleted"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            residualFileMessage(in: app).waitForExistence(timeout: 5)
        )
        XCTAssertFalse(app.staticTexts["Delete failed"].exists)
        app.buttons["OK"].tap()
        XCTAssertFalse(item.waitForExistence(timeout: 2))
    }

    func testCreateDraftRefreshFailureRecoversWithoutUnavailableOrDuplicate() throws {
        let app = englishApp()
        app.launchEnvironment["HOUSEHOLDOS_UI_TESTING"] = "1"
        app.launchEnvironment["HOUSEHOLDOS_UI_TEST_RESET"] = "1"
        app.launchEnvironment["HOUSEHOLDOS_UI_TEST_REFRESH_FAILURE_COUNT"] = "2"
        app.launch()

        app.tabBars.buttons["Add"].tap()
        XCTAssertTrue(app.buttons["capture.manual"].waitForExistence(timeout: 5))
        app.buttons["capture.manual"].tap()

        let nameField = app.textFields["record.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Draft unavailable"].exists)
        XCTAssertTrue(
            app.otherElements["library.refreshBanner"].waitForExistence(timeout: 5)
        )
        app.buttons["library.refreshBanner.reload"].tap()
        XCTAssertFalse(
            app.otherElements["library.refreshBanner"].waitForExistence(timeout: 2)
        )
        nameField.tap()
        nameField.typeText("Recovered Draft")
        app.buttons["draft.save"].tap()

        app.terminate()
        app.launchEnvironment["HOUSEHOLDOS_UI_TEST_RESET"] = "0"
        app.launch()
        app.tabBars.buttons["Drafts"].tap()
        let recoveredDrafts = app.staticTexts.matching(
            NSPredicate(format: "label == %@", "Recovered Draft")
        )
        XCTAssertTrue(recoveredDrafts.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(recoveredDrafts.count, 1)
        recoveredDrafts.firstMatch.tap()
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        XCTAssertEqual(nameField.value as? String, "Recovered Draft")
        XCTAssertFalse(app.staticTexts["Draft unavailable"].exists)
    }

    func testManualReloadFailureKeepsPersistentBannerUntilNextSuccess() throws {
        let app = refreshFailureApp(count: 3)
        app.launch()

        app.tabBars.buttons["Add"].tap()
        XCTAssertTrue(app.buttons["capture.manual"].waitForExistence(timeout: 5))
        app.buttons["capture.manual"].tap()
        XCTAssertTrue(app.textFields["record.name"].waitForExistence(timeout: 5))
        let banner = app.otherElements["library.refreshBanner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5))

        app.buttons["library.refreshBanner.reload"].tap()
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        app.buttons["library.refreshBanner.later"].tap()
        XCTAssertTrue(banner.exists)
        XCTAssertTrue(app.buttons["library.refreshBanner.reload"].exists)

        app.buttons["library.refreshBanner.reload"].tap()
        XCTAssertFalse(banner.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Draft unavailable"].exists)

        app.tabBars.buttons["Drafts"].tap()
        let drafts = app.staticTexts.matching(
            NSPredicate(format: "label == %@", "Untitled draft")
        )
        XCTAssertTrue(drafts.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(drafts.count, 1)
    }

    func testCombinedDraftDeleteShowsBannerAndResidualNoticeWithoutRestoringRow() throws {
        let app = deletionFixtureApp(kind: "draft")
        app.launchEnvironment["HOUSEHOLDOS_UI_TEST_REFRESH_FAILURE_COUNT"] = "2"
        app.launch()

        app.tabBars.buttons["Drafts"].tap()
        let draft = app.staticTexts["Residual Draft"]
        XCTAssertTrue(draft.waitForExistence(timeout: 10))
        draft.tap()
        app.buttons["More actions"].tap()
        app.buttons["Delete Draft"].firstMatch.tap()
        app.buttons["Delete Draft Permanently"].firstMatch.tap()

        XCTAssertTrue(
            app.staticTexts["Draft record deleted"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.otherElements["library.refreshBanner"].waitForExistence(timeout: 5)
        )
        app.buttons["OK"].tap()
        XCTAssertTrue(app.otherElements["library.refreshBanner"].exists)
        XCTAssertFalse(draft.waitForExistence(timeout: 2))

        app.buttons["library.refreshBanner.reload"].tap()
        XCTAssertFalse(
            app.otherElements["library.refreshBanner"].waitForExistence(timeout: 5)
        )
        XCTAssertFalse(draft.waitForExistence(timeout: 2))
    }

    func testEnglishLocalizationSmoke() throws {
        let app = localizedApp(language: "en", locale: "en_US")
        app.launchEnvironment["HOUSEHOLDOS_UI_TESTING"] = "1"
        app.launchEnvironment["HOUSEHOLDOS_UI_TEST_RESET"] = "1"
        app.launch()

        let itemsTab = app.tabBars.buttons["tab.items"]
        let draftsTab = app.tabBars.buttons["tab.drafts"]
        let addTab = app.tabBars.buttons["tab.add"]
        XCTAssertTrue(itemsTab.waitForExistence(timeout: 10))
        XCTAssertEqual(itemsTab.label, "Items")
        XCTAssertEqual(draftsTab.label, "Drafts")
        XCTAssertEqual(addTab.label, "Add")
        XCTAssertTrue(app.staticTexts["No items yet"].exists)

        addTab.tap()
        XCTAssertTrue(app.staticTexts["capture.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["capture.title"].label, "Add one household item")
        app.buttons["capture.manual"].tap()
        XCTAssertTrue(app.buttons["draft.save"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["draft.save"].label, "Save")
        app.buttons["More actions"].tap()
        XCTAssertTrue(app.buttons["draft.delete"].exists)
        XCTAssertFalse(app.staticTexts["物品"].exists)
        XCTAssertFalse(app.staticTexts["草稿"].exists)
    }

    func testSimplifiedChineseLocalizationSmoke() throws {
        let app = localizedApp(language: "zh-Hans", locale: "zh_CN")
        app.launchEnvironment["HOUSEHOLDOS_UI_TESTING"] = "1"
        app.launchEnvironment["HOUSEHOLDOS_UI_TEST_RESET"] = "1"
        app.launchEnvironment["HOUSEHOLDOS_UI_TEST_SEED_DELETION_KIND"] = "draft"
        app.launch()

        let itemsTab = app.tabBars.buttons["tab.items"]
        let draftsTab = app.tabBars.buttons["tab.drafts"]
        let addTab = app.tabBars.buttons["tab.add"]
        XCTAssertTrue(itemsTab.waitForExistence(timeout: 10))
        XCTAssertEqual(itemsTab.label, "物品")
        XCTAssertEqual(draftsTab.label, "草稿")
        XCTAssertEqual(addTab.label, "添加")
        XCTAssertTrue(app.staticTexts["还没有物品"].exists)

        addTab.tap()
        XCTAssertTrue(app.staticTexts["capture.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["capture.title"].label, "添加一件家庭物品")
        app.buttons["capture.manual"].tap()
        XCTAssertTrue(app.buttons["draft.save"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["draft.save"].label, "保存")

        let categoryPicker = app.buttons["record.category"]
        XCTAssertTrue(categoryPicker.waitForExistence(timeout: 5))
        categoryPicker.tap()
        XCTAssertTrue(app.buttons["电子产品"].waitForExistence(timeout: 5))
        app.buttons["电子产品"].tap()

        draftsTab.tap()
        let seededDraft = app.staticTexts["Residual Draft"]
        XCTAssertTrue(seededDraft.waitForExistence(timeout: 10))
        seededDraft.tap()
        let viewPhoto = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "media.view.")
        ).firstMatch
        let deletePhoto = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "media.delete.")
        ).firstMatch
        XCTAssertTrue(viewPhoto.waitForExistence(timeout: 5))
        XCTAssertEqual(viewPhoto.label, "查看照片")
        XCTAssertTrue(deletePhoto.exists)
        XCTAssertEqual(deletePhoto.label, "删除照片")
        XCTAssertFalse(app.staticTexts["Items"].exists)
        XCTAssertFalse(app.staticTexts["Drafts"].exists)
    }

    func testOriginalPhotoViewerAndDeletionPersistAcrossRelaunch() throws {
        let app = englishApp()
        app.launchEnvironment["HOUSEHOLDOS_UI_TESTING"] = "1"
        app.launchEnvironment["HOUSEHOLDOS_UI_TEST_RESET"] = "1"
        app.launchEnvironment["HOUSEHOLDOS_UI_TEST_SEED_DELETION_KIND"] = "draft"
        app.launch()

        app.tabBars.buttons["tab.drafts"].tap()
        let draft = app.staticTexts["Residual Draft"]
        XCTAssertTrue(draft.waitForExistence(timeout: 10))
        draft.tap()
        let viewPhoto = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "media.view.")
        ).firstMatch
        XCTAssertTrue(viewPhoto.waitForExistence(timeout: 5))
        app.collectionViews.firstMatch.swipeUp()
        XCTAssertTrue(viewPhoto.isHittable)
        viewPhoto.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["photoViewer.image"]
                .waitForExistence(timeout: 5)
        )
        let closePhoto = app.buttons["photoViewer.close"]
        closePhoto.tap()
        XCTAssertTrue(closePhoto.waitForNonExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)["photoViewer.image"]
                .waitForNonExistence(timeout: 5)
        )

        let deletePhoto = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "media.delete.")
        ).firstMatch
        XCTAssertTrue(deletePhoto.waitForExistence(timeout: 5))
        let deleteIsHittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == true"),
            object: deletePhoto
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [deleteIsHittable], timeout: 5),
            .completed
        )
        deletePhoto.tap()
        let confirmDelete = app.sheets.buttons["Delete Photo"].firstMatch
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 5))
        confirmDelete.tap()
        XCTAssertFalse(deletePhoto.waitForExistence(timeout: 3))

        app.terminate()
        app.launchEnvironment.removeValue(
            forKey: "HOUSEHOLDOS_UI_TEST_SEED_DELETION_KIND"
        )
        app.launchEnvironment["HOUSEHOLDOS_UI_TEST_RESET"] = "0"
        app.launch()
        app.tabBars.buttons["tab.drafts"].tap()
        XCTAssertTrue(draft.waitForExistence(timeout: 10))
        draft.tap()
        XCTAssertFalse(
            app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "media.delete.")
            ).firstMatch.exists
        )
    }

    private func deletionFixtureApp(kind: String) -> XCUIApplication {
        let app = englishApp()
        app.launchEnvironment["HOUSEHOLDOS_UI_TESTING"] = "1"
        app.launchEnvironment["HOUSEHOLDOS_UI_TEST_RESET"] = "1"
        app.launchEnvironment["HOUSEHOLDOS_UI_TEST_FAIL_MEDIA_REMOVAL"] = "1"
        app.launchEnvironment["HOUSEHOLDOS_UI_TEST_SEED_DELETION_KIND"] = kind
        return app
    }

    private func refreshFailureApp(count: Int) -> XCUIApplication {
        let app = englishApp()
        app.launchEnvironment["HOUSEHOLDOS_UI_TESTING"] = "1"
        app.launchEnvironment["HOUSEHOLDOS_UI_TEST_RESET"] = "1"
        app.launchEnvironment["HOUSEHOLDOS_UI_TEST_REFRESH_FAILURE_COUNT"] = "\(count)"
        return app
    }

    private func residualFileMessage(in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(
            NSPredicate(
                format: "label CONTAINS %@ AND label CONTAINS %@",
                "local photo files could not be removed",
                "retry during later maintenance"
            )
        ).firstMatch
    }

    private func englishApp() -> XCUIApplication {
        localizedApp(language: "en", locale: "en_US")
    }

    private func localizedApp(language: String, locale: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale
        ]
        return app
    }
}
