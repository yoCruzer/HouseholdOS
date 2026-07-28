import XCTest

@MainActor
final class Goal1UserJourneyUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDraftToSearchEditArchiveAndRelaunchJourney() throws {
        let app = XCUIApplication()
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
        XCTAssertTrue(app.buttons["Include Archived"].waitForExistence(timeout: 5))
        app.buttons["Include Archived"].tap()
        XCTAssertTrue(archivedItemRow.waitForExistence(timeout: 5))
    }
}
