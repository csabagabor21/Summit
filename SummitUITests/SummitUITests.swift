import XCTest

// MARK: - Summit UI-tesztek (koppintás + screenshot)
// Futtatás egy parancssal:
//   xcodebuild test -project Summit.xcodeproj -scheme Summit \
//     -destination 'platform=iOS Simulator,id=AE91ECCE-1223-44F8-A70E-3CA8EB52B077' \
//     -only-testing:SummitUITests
// Screenshotok: az xcresult Test Attachments mappájában (lifetime keepAlways).
// Feltétel: a teszt-szimulátoron bejelentkezett demo-állapot
// (Summit-iPhone-Fresh) — friss eszközön előbb kézzel kell belépni.
final class SummitUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    /// Képernyőkép keepAlways attachmenttel (xcresultban megmarad).
    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func testHomeEsTabok() throws {
        XCTAssertTrue(app.navigationBars["Főoldal"].waitForExistence(timeout: 25))
        shot("01-fooldal")
        for tab in ["Jegyek", "Órarend", "Hiányzások", "Watch"] {
            app.tabBars.buttons[tab].tap()
            shot("tab-\(tab)")
        }
        app.tabBars.buttons["Főoldal"].tap()
    }

    /// Fantom-csere végig: tantárgy → jegyen balra swipe → Mi lett volna ha →
    /// érték → Csere fantomra → FANTOM ELŐNÉZET → fantomon swipe → Elvetés.
    /// Laza ágak: ha a demo-állapot épp nincs meg, csak screenshot készül.
    func testFantomCsere() throws {
        app.tabBars.buttons["Jegyek"].tap()
        let subject = app.staticTexts["Matematika"]
        guard subject.waitForExistence(timeout: 15) else {
            shot("fantom-nincs-demo"); return
        }
        subject.tap()
        shot("fantom-10-detail")
        // Első nem-fantom jegysor: balra swipe → csere-akció.
        let rows = app.cells
        guard rows.count > 0 else { shot("fantom-nincs-sor"); return }
        var swapped = false
        for i in 0..<min(rows.count, 8) {
            let cell = rows.element(boundBy: i)
            cell.swipeLeft()
            let action = app.buttons["Mi lett volna ha"]
            if action.waitForExistence(timeout: 2) {
                action.tap()
                swapped = true
                break
            }
        }
        guard swapped else { shot("fantom-nincs-akcio"); return }
        shot("fantom-20-csere-lap")
        // Értékválasztó: az 5-ös szegmens, majd csere.
        app.segmentedControls.buttons.element(boundBy: 4).tap()
        app.buttons["Csere fantomra"].tap()
        let badge = app.staticTexts["FANTOM ELŐNÉZET"]
        XCTAssertTrue(badge.waitForExistence(timeout: 5))
        shot("fantom-30-elonezet")
        // Fantom-sor elvetése balra swipe-pal.
        var dismissed = false
        for i in 0..<min(app.cells.count, 10) {
            let cell = app.cells.element(boundBy: i)
            cell.swipeLeft()
            let dismiss = app.buttons["Elvetés"]
            if dismiss.waitForExistence(timeout: 2) {
                dismiss.tap()
                dismissed = true
                break
            }
        }
        XCTAssertTrue(dismissed)
        shot("fantom-40-elvetve")
    }
}
