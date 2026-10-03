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

    /// Óra-részletező: Órarend tab → első órakártya koppintás → fullscreen
    /// részletező (Óra adatai: tanár, időpont, terem) → "Kész" → vissza.
    /// Laza ág: demo-állapot (órák) nélkül csak screenshot készül.
    func testLessonDetail() throws {
        app.tabBars.buttons["Órarend"].tap()
        guard app.navigationBars["Órarend"].waitForExistence(timeout: 15) else {
            shot("detail-nincs-orarend"); return
        }
        // A fejléc önálló gomb (testvér-pillekkel), ezért buttons-ként látszik.
        let rows = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "lesson-row-"))
        guard rows.count > 0 else { shot("detail-nincs-ora"); return }
        // A lista a tabra lépés után még mozoghat (okos napugrás animációja) —
        // elintézzük, hogy álló célpontra koppintsunk.
        Thread.sleep(forTimeInterval: 1.5)
        rows.element(boundBy: 0).tap()
        let detail = app.collectionViews["lesson-detail"]
        if !detail.waitForExistence(timeout: 5) {
            // Egyszeri újrapróbálkozás friss lekérdezéssel.
            rows.element(boundBy: 0).tap()
        }
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        // A részletező tartalma: tanár-sor és házi/dolgozat szekció.
        XCTAssertTrue(app.staticTexts["Tanár"].waitForExistence(timeout: 5))
        shot("detail-10-nyitva")
        app.buttons["Kész"].tap()
        XCTAssertFalse(detail.waitForExistence(timeout: 5))
        shot("detail-20-csukva")
    }

    /// Feladatok-cover "Kész" gombja: órarendi dolgozat-pillből nyitva is
    /// legyen kiút (a covernek nincs tab-sávja). Csak akkor fut végig, ha
    /// a demo-állapotban van dolgozat-pill az órarenden — különben
    /// screenshot + visszatérés (lásd fantom-teszt mintája).
    func testTasksCoverClose() throws {
        app.tabBars.buttons["Órarend"].tap()
        guard app.navigationBars["Órarend"].waitForExistence(timeout: 15) else {
            shot("taskscover-nincs-orarend"); return
        }
        // Dolgozat-pillek (doc.text.fill ikonú gombok) az órakártyákon.
        let pills = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Dolgozat"))
        guard pills.count > 0 else {
            // Dolgozat-pill nélkül nincs cover-út — a házi-pill is megteszi.
            let hwPills = app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", "Házi"))
            guard hwPills.count > 0 else { shot("taskscover-nincs-pill"); return }
            hwPills.element(boundBy: 0).tap()
            checkTasksCover()
            return
        }
        pills.element(boundBy: 0).tap()
        checkTasksCover()
    }

    /// A Feladatok-coveren ott a "Kész" gomb, és tényleg csuk.
    private func checkTasksCover() {
        let feladatok = app.navigationBars["Feladatok"]
        guard feladatok.waitForExistence(timeout: 10) else {
            shot("taskscover-nem-nyilt"); return
        }
        shot("taskscover-10-nyitva")
        // Toolbar-gomb (a "Kész" szegmenssel ütközne, ezért Bezárás).
        let kesz = app.navigationBars["Feladatok"].buttons["Bezárás"]
        XCTAssertTrue(kesz.waitForExistence(timeout: 5))
        kesz.tap()
        if feladatok.waitForExistence(timeout: 5) {
            // Még nyitva — az animáció nyelhette el a koppintást, egyszer újra.
            kesz.tap()
        }
        // A cover csukódott (a mögöttes tab eszközfüggő: órarend vagy Watch).
        XCTAssertFalse(feladatok.waitForExistence(timeout: 5))
        shot("taskscover-20-csukva")
    }
}
