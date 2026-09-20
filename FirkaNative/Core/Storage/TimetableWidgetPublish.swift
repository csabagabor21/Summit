import Foundation
import WidgetKit

// MARK: - Órarend widget publikálás — CSAK fő app target
// LessonItem → widget-snapshot mapping egy helyen (TimetableView + BG-ébresztés).
// WidgetKit-import miatt nem kerülhet a shared snapshot-fájlba.
enum TimetableWidgetPublish {
    static func fromLessons(_ lessons: [LessonItem]) -> [TimetableWidgetStore.Lesson] {
        lessons.sorted { $0.start < $1.start }.map {
            TimetableWidgetStore.Lesson(
                id: $0.id, subject: $0.subject, room: $0.room, teacher: $0.teacher,
                index: $0.index, start: $0.start, end: $0.end,
                isCancelled: $0.isCancelled, isSubstituted: $0.isSubstituted
            )
        }
    }

    static func currentAccentHex() -> Int {
        UserDefaults.standard.object(forKey: "theme.accentHex") as? Int ?? 0x4A90E2
    }

    /// Dev idő-eltolás csúszka állása (csak eszköz-helyi preview, sosem szinkron).
    static func previewState() -> (active: Bool, minutes: Double) {
        let dev = UserDefaults.standard.bool(forKey: "developer.enabled")
        let active = dev && UserDefaults.standard.bool(forKey: "home.demoPreviewActive")
        let minutes: Double
        if let v = UserDefaults.standard.object(forKey: "home.demoPreviewMinutes") as? Double {
            minutes = v
        } else {
            minutes = 540
        }
        return (active, minutes)
    }

    /// Teljes heti snapshot írása (TimetableView.load() végéről).
    static func publishWeek(_ lessons: [LessonItem]) {
        guard !lessons.isEmpty else { return }
        let preview = previewState()
        TimetableWidgetStore.save(TimetableWidgetStore.Snapshot(
            savedAt: Date(), accentHex: currentAccentHex(),
            lessons: fromLessons(lessons),
            previewActive: preview.active, previewMinutes: preview.minutes
        ))
        WidgetCenter.shared.reloadTimelines(ofKind: TimetableWidgetStore.kind)
    }

    /// Mai nap mergelése háttér-ébresztésből (csak a mai szelet frissül).
    /// Csak akkor ír, ha már létezik snapshot (azaz a user egyszer
    /// megnyitotta az Órarendet) — üres állapotot nem kreál.
    static func mergeToday(_ lessons: [LessonItem], now: Date = Date()) {
        let dayLessons = lessons.filter { Calendar.current.isDate($0.start, inSameDayAs: now) }
        guard TimetableWidgetStore.mergeDay(
            lessons: fromLessons(dayLessons), day: now, accentHex: currentAccentHex()
        ) else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: TimetableWidgetStore.kind)
    }
}
