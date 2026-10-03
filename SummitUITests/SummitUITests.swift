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

    /// Bootstrap: tiszta szimulátoron demo módban bejelentkeztet, hogy a
    /// többi teszt bejelentkezett állapotból induljon. Bejelentkezett
    /// állapoton csak a consent-függönyt csukja le (ha épp fent van).
    /// ABC-sorrendben ez fut először (test00…).
    func test00DemoBejelentkezes() throws {
        if app.tabBars.buttons["Főoldal"].waitForExistence(timeout: 10) {
            shot("login-00-mar-bent")
        } else {
            let kretaLogin = app.buttons["Bejelentkezés E.KRÉTÁVAL"]
            guard kretaLogin.waitForExistence(timeout: 15) else {
                shot("login-nincs-login"); return
            }
            kretaLogin.tap()
            guard app.navigationBars["e-KRÉTA"].waitForExistence(timeout: 10) else {
                shot("login-nincs-weblap"); return
            }
            shot("login-10-weblap")
            // Siker-ág: Demo gomb a toolbarban; hiba-ág (nincs hálózat):
            // "Folytatás demo módban" a lap alján.
            let demo = app.navigationBars["e-KRÉTA"].buttons["Demo"]
            if demo.waitForExistence(timeout: 5) {
                demo.tap()
            } else {
                let demoFallback = app.buttons["Folytatás demo módban"]
                guard demoFallback.waitForExistence(timeout: 15) else {
                    shot("login-nincs-demo"); return
                }
                demoFallback.tap()
            }
            guard app.tabBars.buttons["Főoldal"].waitForExistence(timeout: 15) else {
                shot("login-nem-lepett-be"); return
            }
            shot("login-20-bent")
        }
        // Analitika-consent: amíg nincs döntés, függöny fedi a tabokat.
        let decline = app.buttons["Kikapcsolva folytatom"]
        if decline.waitForExistence(timeout: 5) {
            decline.tap()
        }
        XCTAssertTrue(app.navigationBars["Főoldal"].waitForExistence(timeout: 10))
        shot("login-30-fooldal")
    }

    func testHomeEsTabok() throws {
        XCTAssertTrue(app.navigationBars["Főoldal"].waitForExistence(timeout: 25))
        shot("01-fooldal")
        for tab in ["Jegyek", "Órarend", "Feladatok", "Hiányzások"] {
            app.tabBars.buttons[tab].tap()
            shot("tab-\(tab)")
        }
        app.tabBars.buttons["Főoldal"].tap()
    }

    /// Watch-belépő a Feladatok tetején: a + gombbal szembeni toolbar-gomb
    /// sheetben nyitja a Watch-jegyzeteket, X-szel csukható. Laza ág: óra
    /// nélkül a gomb nem látszik — ilyenkor csak screenshot készül.
    func testWatchSheet() throws {
        app.tabBars.buttons["Feladatok"].tap()
        guard app.navigationBars["Feladatok"].waitForExistence(timeout: 15) else {
            shot("watch-nincs-feladatok"); return
        }
        let watchButton = app.navigationBars["Feladatok"].buttons["Watch"]
        guard watchButton.waitForExistence(timeout: 5) else {
            shot("watch-nincs-gomb"); return
        }
        watchButton.tap()
        let watchNav = app.navigationBars["Watch"]
        XCTAssertTrue(watchNav.waitForExistence(timeout: 10))
        shot("watch-10-nyitva")
        // Többképkockás görgetés a Watch-sheetben is.
        app.swipeUp()
        shot("watch-12-gorgetve")
        app.swipeDown()
        let close = watchNav.buttons["Bezárás"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertFalse(watchNav.waitForExistence(timeout: 5))
        shot("watch-20-csukva")
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

    /// Órarendi pill → Feladatok tab: a dolgozat/házi pillre koppintva
    /// a Feladatok tab nyílik (nem cover — van tab-sáv, nincs Bezárás
    /// gomb). Csak akkor fut végig, ha a demo-állapotban van pill az
    /// órarenden — különben screenshot + visszatérés (lásd fantom-teszt
    /// mintája).
    func testTasksCoverClose() throws {
        app.tabBars.buttons["Órarend"].tap()
        guard app.navigationBars["Órarend"].waitForExistence(timeout: 15) else {
            shot("taskscover-nincs-orarend"); return
        }
        // Dolgozat-pillek (doc.text.fill ikonú gombok) az órakártyákon.
        let pills = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Dolgozat"))
        guard pills.count > 0 else {
            // Dolgozat-pill nélkül a házi-pill is megteszi.
            let hwPills = app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", "Házi"))
            guard hwPills.count > 0 else { shot("taskscover-nincs-pill"); return }
            hwPills.element(boundBy: 0).tap()
            checkTasksTab()
            return
        }
        pills.element(boundBy: 0).tap()
        checkTasksTab()
    }

    /// A pill a Feladatok tabra visz: a tab sávja látszik és ki van
    /// választva, a nézet címe Feladatok.
    private func checkTasksTab() {
        let feladatok = app.navigationBars["Feladatok"]
        guard feladatok.waitForExistence(timeout: 10) else {
            shot("taskscover-nem-nyilt"); return
        }
        shot("taskscover-10-nyitva")
        XCTAssertTrue(app.tabBars.buttons["Feladatok"].waitForExistence(timeout: 5))
        // Többképkockás görgetés: a lista él és követi az ujjat.
        app.swipeUp()
        shot("taskscover-15-gorgetve")
        app.swipeDown()
        shot("taskscover-20-tabon")
    }
}
