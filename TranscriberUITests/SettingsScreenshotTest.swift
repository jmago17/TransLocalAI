import XCTest

final class SettingsScreenshotTest: XCTestCase {
    @MainActor
    func testSettingsTerminologySection() throws {
        let app = XCUIApplication()
        app.launch()
        sleep(2)

        // Go to Settings tab
        let ajustes = app.tabBars.buttons.element(boundBy: 2)
        if ajustes.waitForExistence(timeout: 5) { ajustes.tap() }
        sleep(1)

        // Scroll down to the terminology section
        app.swipeUp()
        sleep(1)
        saveShot(app, name: "settings_terminology")

        // Open the bulk editor
        let editAsText = app.buttons["Edit as text"]
        if editAsText.waitForExistence(timeout: 3) {
            editAsText.tap()
            sleep(1)
            saveShot(app, name: "bulk_editor")
        }
    }

    @MainActor
    private func saveShot(_ app: XCUIApplication, name: String) {
        let shot = app.screenshot()
        let url = URL(fileURLWithPath: "/tmp/\(name).png")
        try? shot.pngRepresentation.write(to: url)
    }
}
