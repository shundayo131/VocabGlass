//
//  CardLibraryUITests.swift
//  VocabGlassUITests
//
//  The card library end to end: empty state, browsing the grid, delete
//  with confirmation, edit, and the flashcard review flow. Each test
//  launches with seed or reset arguments so the app starts in a known
//  state (see UITestSupport in the app target).
//

import XCTest

final class CardLibraryUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    // MARK: - States

    func testEmptyDeckShowsEmptyState() {
        let app = launch(["--uitest-reset", "--uitest-tab-deck"])
        XCTAssertTrue(element(app, "deck.empty").waitForExistence(timeout: 10))
    }

    func testSeededDeckShowsGridAndReviewButton() {
        let app = launch(["--uitest-seed", "--uitest-tab-deck"])
        XCTAssertTrue(element(app, "deck.grid").waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "deck.tile.植物").exists)
        XCTAssertTrue(element(app, "deck.reviewButton").exists)
    }

    func testForcedLoadingAndErrorStatesRender() {
        let loading = launch(["--uitest-seed", "--uitest-tab-deck", "--uitest-deck-loading"])
        XCTAssertTrue(element(loading, "deck.loading").waitForExistence(timeout: 10))
        loading.terminate()

        let errored = launch(["--uitest-seed", "--uitest-tab-deck", "--uitest-deck-error"])
        XCTAssertTrue(element(errored, "deck.error").waitForExistence(timeout: 10))
    }

    // MARK: - Detail, delete, edit

    func testDeleteFromDetailAsksForConfirmationThenRemoves() {
        let app = launch(["--uitest-seed", "--uitest-tab-deck"])
        XCTAssertTrue(element(app, "deck.tile.植物").waitForExistence(timeout: 10))

        element(app, "deck.tile.植物").tap()
        XCTAssertTrue(element(app, "detail.deleteButton").waitForExistence(timeout: 5))

        element(app, "detail.deleteButton").tap()
        let confirm = element(app, "detail.confirmDeleteButton")
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "delete must ask for confirmation")

        confirm.tap()
        XCTAssertTrue(element(app, "deck.grid").waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "deck.tile.植物").exists, "deleted card must leave the grid")
        XCTAssertTrue(element(app, "deck.tile.杯子").exists, "other cards must survive")
    }

    func testEditFromDetailUpdatesTheCard() {
        let app = launch(["--uitest-seed", "--uitest-tab-deck"])
        XCTAssertTrue(element(app, "deck.tile.植物").waitForExistence(timeout: 10))

        element(app, "deck.tile.植物").tap()
        XCTAssertTrue(element(app, "detail.editButton").waitForExistence(timeout: 5))
        element(app, "detail.editButton").tap()

        let field = app.textFields["edit.translationField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.clearText()
        field.typeText("green plant")

        element(app, "edit.saveButton").tap()
        element(app, "detail.doneButton").tap()

        // Reopen to prove the edit persisted through the store.
        element(app, "deck.tile.植物").tap()
        XCTAssertTrue(app.staticTexts["green plant"].waitForExistence(timeout: 5))
    }

    // MARK: - Review

    func testFlashcardReviewRevealsAndAdvances() {
        let app = launch(["--uitest-seed", "--uitest-tab-deck"])
        XCTAssertTrue(element(app, "deck.reviewButton").waitForExistence(timeout: 10))
        element(app, "deck.reviewButton").tap()

        let show = element(app, "review.showAnswerButton")
        XCTAssertTrue(show.waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "review.answer").exists, "answer must start hidden")

        show.tap()
        XCTAssertTrue(element(app, "review.answer").waitForExistence(timeout: 5))

        element(app, "review.nextButton").tap()
        XCTAssertTrue(element(app, "review.showAnswerButton").waitForExistence(timeout: 5),
                      "next card must start hidden again")

        element(app, "review.closeButton").tap()
        XCTAssertTrue(element(app, "deck.grid").waitForExistence(timeout: 5))
    }
}

private extension XCUIElement {
    // Clear a text field: put the cursor at the end, then delete back
    // through the current value.
    func clearText() {
        guard let value = value as? String, !value.isEmpty else { return }
        coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
    }
}
