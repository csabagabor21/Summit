import Foundation
import WidgetKit

// MARK: - Órarend widget publikálás — CSAK fő app target
// LessonItem → widget-snapshot mapping egy helyen (TimetableView + BG-ébresztés).
// WidgetKit-import miatt nem kerülhet a shared snapshot-fájlba.
enum TimetableWidgetPublish {
    /// Telefonos státusz-port az órára/widgetbe: felmentett (zöld) +
    /// aznapi házi/dolgozat (szürke) — ugyanaz a szabály, mint a
    /// TimetableView.hasAssignment (tárgy+nap házi, tűzött dolgozat).
    static func fromLessons(_ lessons: [LessonItem], homeworks: [HomeworkItem] = [], exams: [ExamItem] = []) -> [TimetableWidgetStore.Lesson] {
        let cal = Calendar.current
        return lessons.sorted { $0.start < $1.start }.map { lesson in
            let sameDayHW = homeworks.contains {
                SubjectMatcher.same($0.subject, lesson.subject)
                && cal.isDate($0.deadline, inSameDayAs: lesson.start)
            }
            let sameDayExam = ExamMatcher.exam(for: lesson, in: exams) != nil
            return TimetableWidgetStore.Lesson(
                id: lesson.id, subject: lesson.subject, room: lesson.room, teacher: lesson.teacher,
                index: lesson.index, start: lesson.start, end: lesson.end,
                isCancelled: lesson.isCancelled, isSubstituted: lesson.isSubstituted,
                isExempted: ExemptedStore.isExempted(lesson.subject),
                hasAssignment: sameDayHW || sameDayExam
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

    /// Következő tanítási nap rendkívüliségei a "ma nincs több óra"
    /// kártyához — dolgozat > elmaradó / helyettesített óra > iskolai
    /// esemény. Nil = semmi rendkívüli (vagy nincs több nap a cache-ben).
    static func nextDayNote(
        lessons: [LessonItem],
        exams: [ExamItem] = [],
        events: [SchoolEvent] = [],
        eventsVisible: Bool = true,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TimetableWidgetStore.NextDayNote? {
        let today = calendar.startOfDay(for: now)
        let futureDays = Set(lessons.map { calendar.startOfDay(for: $0.start) })
            .filter { $0 > today }.sorted()
        guard let nextDay = futureDays.first else { return nil }
        let dayLessons = lessons.filter { calendar.isDate($0.start, inSameDayAs: nextDay) }
        let dayExams = exams.filter { calendar.isDate($0.date, inSameDayAs: nextDay) }
            .sorted { $0.date < $1.date }
        let dayEvents = eventsVisible ? SchoolEventsStore.events(on: nextDay, from: events) : []
        let cancelled = dayLessons.filter { $0.isCancelled }.sorted { $0.start < $1.start }
        let substituted = dayLessons.filter { !$0.isCancelled && $0.isSubstituted }
            .sorted { $0.start < $1.start }
        guard !dayExams.isEmpty || !cancelled.isEmpty || !substituted.isEmpty || !dayEvents.isEmpty else { return nil }
        var ordered: [TimetableWidgetStore.NextDayItem] = []
        ordered += dayExams.map {
            TimetableWidgetStore.NextDayItem(kind: "exam", title: $0.subject, subtitle: friendlyExamMode($0.mode))
        }
        ordered += cancelled.map {
            let idx = $0.index.trimmingCharacters(in: .whitespaces)
            return TimetableWidgetStore.NextDayItem(
                kind: "cancelled", title: $0.subject,
                subtitle: idx.isEmpty ? "Elmarad" : "\(idx). óra elmarad")
        }
        ordered += substituted.map {
            let idx = $0.index.trimmingCharacters(in: .whitespaces)
            return TimetableWidgetStore.NextDayItem(
                kind: "substituted", title: $0.subject,
                subtitle: idx.isEmpty ? "Helyettesítés" : "\(idx). óra • helyettesítés")
        }
        ordered += dayEvents.map {
            TimetableWidgetStore.NextDayItem(kind: "event", title: $0.title, subtitle: $0.subtitle)
        }
        return TimetableWidgetStore.NextDayNote(
            day: nextDay,
            items: Array(ordered.prefix(3)),
            examCount: dayExams.count,
            cancelledCount: cancelled.count,
            substitutedCount: substituted.count,
            eventCount: dayEvents.count
        )
    }

    /// Teljes heti snapshot írása (TimetableView.load() végéről).
    static func publishWeek(_ lessons: [LessonItem], homeworks: [HomeworkItem] = [], exams: [ExamItem] = [], events: [SchoolEvent] = [], eventsVisible: Bool = true) {
        guard !lessons.isEmpty else { return }
        let preview = previewState()
        TimetableWidgetStore.save(TimetableWidgetStore.Snapshot(
            savedAt: Date(), accentHex: currentAccentHex(),
            lessons: fromLessons(lessons, homeworks: homeworks, exams: exams),
            previewActive: preview.active, previewMinutes: preview.minutes,
            nextNote: nextDayNote(lessons: lessons, exams: exams, events: events, eventsVisible: eventsVisible)
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

    /// Ha a snapshotban nincs több jövőbeli óra (pl. péntek este a heti
    /// cache kimerült), a következő 7 napot egyben lehúzza és mergeli —
    /// így a widget a holnapi / hétfői napot mutatja, nem "Mára vége"-t.
    /// A merge után timeline-reload is kell (a mergeFuture — shared
    /// fájl, WidgetKit nélkül — nem tölt újra).
    static func prefetchUpcomingIfExhausted(now: Date, kreta: KretaClient, iss: String) async {
        if let snap = TimetableWidgetStore.load(),
           snap.lessons.contains(where: { $0.start > now }) { return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        guard let end = cal.date(byAdding: .day, value: 7, to: start) else { return }
        let lessons = await kreta.fetchTimetable(iss: iss, from: start, to: end)
        guard !lessons.isEmpty else { return }
        guard TimetableWidgetStore.mergeFuture(
            lessons: fromLessons(lessons), accentHex: currentAccentHex(), now: now
        ) else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: TimetableWidgetStore.kind)
    }
}
