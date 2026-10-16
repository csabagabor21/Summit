import AppIntents
import Foundation

// MARK: - Siri / App Shortcuts: órarend hanggal
//
// "Hey Siri, what lessons do I have tomorrow?" / "Holnapi óráim"
// Az adatok a widget-snapshotból jönnek (App Group, a TimetableView írja)
// — hálózat és KRÉTA-token nélkül, offline is válaszol. Csak olvas:
// tárgy, terem, időpont (személyes adat nem hagyja el a telefont).
//
// Válasz nyelve: magyar (az app nyelve). Az angol hívó-mondatokra is
// magyarul válaszol — ez tudatos v1-határ, nem hiba.

/// Holnapi órák egy mondatban ("1. Matek (A1) 8:00, 2. Angol (B2) 9:00…").
struct TomorrowLessonsIntent: AppIntent {
    static var title: LocalizedStringResource = "Holnapi órák"
    static var description = IntentDescription("Megmondja, milyen óráid lesznek holnap.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = SiriTimetable.answer(for: .tomorrow)
        AnalyticsStore.recordStep("siri_tomorrow")
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

/// Mai hátralévő órák ("Még 3 órád van: …").
struct TodayLessonsIntent: AppIntent {
    static var title: LocalizedStringResource = "Mai órák"
    static var description = IntentDescription("Megmondja, milyen óráid vannak még ma.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = SiriTimetable.answer(for: .today)
        AnalyticsStore.recordStep("siri_today")
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

struct SummitShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TomorrowLessonsIntent(),
            phrases: [
                "Holnapi óráim \(.applicationName)-ban",
                "Milyen óráim lesznek holnap \(.applicationName)-ban",
                "Mutasd a holnapi óráimat \(.applicationName)-ban",
                "What lessons do I have tomorrow with \(.applicationName)",
                "What are my lessons tomorrow with \(.applicationName)",
                "Show my timetable for tomorrow with \(.applicationName)",
            ],
            shortTitle: "Holnapi órák",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: TodayLessonsIntent(),
            phrases: [
                "Mai óráim \(.applicationName)-ban",
                "Milyen óráim vannak ma \(.applicationName)-ban",
                "What lessons do I have today with \(.applicationName)",
                "What are my remaining lessons with \(.applicationName)",
            ],
            shortTitle: "Mai órák",
            systemImageName: "clock"
        )
    }
}

/// Válasz-összeállítás a widget-snapshotból (AppIntent- és UI-független,
/// ezért külön enum — a holnapi nap logikája egy helyen él).
enum SiriTimetable {
    enum Day { case today, tomorrow }

    static func answer(for day: Day, now: Date = Date(), calendar: Calendar = .current) -> String {
        // Utazás alatt nincs suli — ezt mondjuk is.
        if TravelMode.isActive(at: now) {
            return "Utazás mód aktív — most pihenj, nincs suli!"
        }
        guard let snap = TimetableWidgetStore.load(), !snap.lessons.isEmpty else {
            return "Még nem tudom az órarended — nyisd meg egyszer az app Órarend fülét, és legközelebb megmondom."
        }
        let target: Date
        let prefix: String
        switch day {
        case .today:
            target = now
            prefix = "Ma"
        case .tomorrow:
            target = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            prefix = "Holnap"
        }
        let lessons = snap.lessons
            .filter { calendar.isDate($0.start, inSameDayAs: target) }
            .filter { !$0.subject.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.start < $1.start }
        guard !lessons.isEmpty else {
            switch day {
            case .today: return "Mára nincs több órád."
            case .tomorrow: return "Holnap nincs tanítás."
            }
        }
        let tf = DateFormatter()
        tf.locale = Locale(identifier: "hu_HU")
        tf.dateFormat = "H:mm"
        let shown: [TimetableWidgetStore.Lesson]
        if day == .today {
            // Ma: csak a még hátra lévők számítanak.
            let rest = lessons.filter { $0.end > now }
            guard !rest.isEmpty else { return "Mára nincs több órád." }
            shown = rest
        } else {
            shown = lessons
        }
        let parts = shown.map { l -> String in
            let room = l.room.isEmpty || l.room == "-" ? "" : " (\(l.room))"
            return "\(l.index). \(l.subject)\(room) \(tf.string(from: l.start))"
        }
        let head: String
        switch day {
        case .today: head = "Még \(shown.count) órád van: "
        case .tomorrow: head = "Holnap \(shown.count) órád lesz: "
        }
        return head + parts.joined(separator: ", ")
    }
}
