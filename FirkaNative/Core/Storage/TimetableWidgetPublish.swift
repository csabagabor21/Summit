import Foundation
import WidgetKit

// MARK: - Órarend widget publikálás — CSAK fő app target
// LessonItem → widget-snapshot mapping egy helyen (TimetableView + BG-ébresztés).
// WidgetKit-import miatt nem kerülhet a shared snapshot-fájlba.
enum TimetableWidgetPublish {
    /// Telefonos státusz-port az órára/widgetbe: felmentett (zöld) +
    /// aznapi házi/dolgozat (szürke) — ugyanaz a szabály, mint a
    /// TimetableView.hasAssignment (tárgy+nap házi, tűzött dolgozat).
    /// Napra bontva (a párosítás csak azonos napi tételt néz) — eddig
    /// óránként a teljes házi- és dolgozatlista újraszkennelve.
    static func fromLessons(_ lessons: [LessonItem], homeworks: [HomeworkItem] = [], exams: [ExamItem] = []) -> [TimetableWidgetStore.Lesson] {
        let cal = Calendar.current
        var hwByDay: [Date: [HomeworkItem]] = [:]
        for h in homeworks { hwByDay[cal.startOfDay(for: h.deadline), default: []].append(h) }
        var exByDay: [Date: [ExamItem]] = [:]
        for e in exams { exByDay[cal.startOfDay(for: e.date), default: []].append(e) }
        var lessonsByDay: [Date: [LessonItem]] = [:]
        for l in lessons { lessonsByDay[cal.startOfDay(for: l.start), default: []].append(l) }
        return lessons.sorted { $0.start < $1.start }.map { lesson in
            let day = cal.startOfDay(for: lesson.start)
            let sameDayHW = hwByDay[day]?.contains { SubjectMatcher.same($0.subject, lesson.subject) } ?? false
            let sameDayExam = exByDay[day].map {
                ExamMatcher.exam(for: lesson, in: $0, calendar: cal, allLessons: lessonsByDay[day] ?? []) != nil
            } ?? false
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

    /// Egy adott nap rendkívüliségei — az iskolai esemény MINDIG
    /// legfelül, utána dolgozat, elmaradó óra, helyettesítés.
    /// Nil = semmi rendkívüli aznap.
    static func dayNote(
        forDay day: Date,
        lessons: [LessonItem],
        exams: [ExamItem] = [],
        events: [SchoolEvent] = [],
        eventsVisible: Bool = true,
        calendar: Calendar = .current
    ) -> TimetableWidgetStore.NextDayNote? {
        let dayLessons = lessons.filter { calendar.isDate($0.start, inSameDayAs: day) }
        let dayExams = exams.filter { calendar.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.date < $1.date }
        let dayEvents = eventsVisible ? SchoolEventsStore.events(on: day, from: events) : []
        let cancelled = dayLessons.filter { $0.isCancelled }.sorted { $0.start < $1.start }
        let substituted = dayLessons.filter { !$0.isCancelled && $0.isSubstituted }
            .sorted { $0.start < $1.start }
        guard !dayExams.isEmpty || !cancelled.isEmpty || !substituted.isEmpty || !dayEvents.isEmpty else { return nil }
        let examItems = dayExams.map {
            TimetableWidgetStore.NextDayItem(kind: "exam", title: $0.subject, subtitle: friendlyExamMode($0.mode))
        }
        let cancelledItems = cancelled.map {
            let idx = $0.index.trimmingCharacters(in: .whitespaces)
            return TimetableWidgetStore.NextDayItem(
                kind: "cancelled", title: $0.subject,
                subtitle: idx.isEmpty ? "Elmarad" : "\(idx). óra elmarad")
        }
        let substitutedItems = substituted.map {
            let idx = $0.index.trimmingCharacters(in: .whitespaces)
            return TimetableWidgetStore.NextDayItem(
                kind: "substituted", title: $0.subject,
                subtitle: idx.isEmpty ? "Helyettesítés" : "\(idx). óra • helyettesítés")
        }
        let eventItems = dayEvents.map {
            TimetableWidgetStore.NextDayItem(kind: "event", title: $0.title, subtitle: $0.subtitle)
        }
        let ordered = eventItems + examItems + cancelledItems + substitutedItems
        return TimetableWidgetStore.NextDayNote(
            day: calendar.startOfDay(for: day),
            items: Array(ordered.prefix(3)),
            examCount: dayExams.count,
            cancelledCount: cancelled.count,
            substitutedCount: substituted.count,
            eventCount: dayEvents.count
        )
    }

    /// Következő tanítási nap rendkívüliségei a "ma nincs több óra"
    /// kártyához. Nil = semmi rendkívüli (vagy nincs több nap a cache-ben).
    /// Naptári infókból (KRÉTA NaptariNapok) a tanítás nélküli
    /// hétköznapok listája a widget-snapshotba. Hétvégét nem jelölünk
    /// (az magától értetődik), csak hétfő–pénteket.
    static func noSchoolDays(
        from infos: [SchoolDayInfo],
        calendar: Calendar = .current
    ) -> [TimetableWidgetStore.NoSchoolDay] {
        var seen = Set<Date>()
        var out: [TimetableWidgetStore.NoSchoolDay] = []
        for info in infos where !info.isTimetableDay {
            let day = calendar.startOfDay(for: info.date)
            let wd = calendar.component(.weekday, from: day)
            guard (2...6).contains(wd), seen.insert(day).inserted else { continue }
            let name = info.typeName.trimmingCharacters(in: .whitespacesAndNewlines)
            out.append(TimetableWidgetStore.NoSchoolDay(
                day: day, name: name.isEmpty ? "Tanítás nélküli nap" : name))
        }
        return out.sorted { $0.day < $1.day }
    }

    /// Tanítás nélküli jelölés rátétele a napi jegyzetre: ha aznap nincs
    /// órája, de a tanév rendje jelöli, a kártya címe a típusnév lesz
    /// ("Tanítás nélküli munkanap"), az események az alcímbe kerülnek.
    /// Órák mellett a jelölés nem számít (oda kell menni).
    private static func attachNoSchool(
        _ note: TimetableWidgetStore.NextDayNote?,
        day: Date,
        lessons: [LessonItem],
        events: [SchoolEvent],
        eventsVisible: Bool,
        noSchoolDays: [TimetableWidgetStore.NoSchoolDay],
        calendar: Calendar
    ) -> TimetableWidgetStore.NextDayNote? {
        var note = note
        let hasLessons = lessons.contains { calendar.isDate($0.start, inSameDayAs: day) }
        guard !hasLessons,
              let ns = noSchoolDays.first(where: { calendar.isDate($0.day, inSameDayAs: day) }) else { return note }
        if note == nil {
            let dayEvents = eventsVisible ? SchoolEventsStore.events(on: day, from: events) : []
            let items = dayEvents.prefix(3).map {
                TimetableWidgetStore.NextDayItem(kind: "event", title: $0.title, subtitle: $0.subtitle)
            }
            note = TimetableWidgetStore.NextDayNote(
                day: calendar.startOfDay(for: day), items: Array(items),
                examCount: 0, cancelledCount: 0, substitutedCount: 0,
                eventCount: dayEvents.count, noSchoolName: ns.name)
        } else {
            note?.noSchoolName = ns.name
        }
        return note
    }

    /// Következő érdemi nap a "ma nincs több óra" kártyához: tanítási
    /// nap órákkal, vagy tanítás nélküli hétköznap (órák nélkül is).
    /// Nil = semmi (vagy nincs több nap a cache-ben).
    static func nextDayNote(
        lessons: [LessonItem],
        exams: [ExamItem] = [],
        events: [SchoolEvent] = [],
        eventsVisible: Bool = true,
        noSchoolDays: [TimetableWidgetStore.NoSchoolDay] = [],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TimetableWidgetStore.NextDayNote? {
        let today = calendar.startOfDay(for: now)
        var candidates = Set(lessons.map { calendar.startOfDay(for: $0.start) })
        for ns in noSchoolDays where ns.day > today { candidates.insert(ns.day) }
        guard let nextDay = candidates.filter({ $0 > today }).sorted().first else { return nil }
        let note = dayNote(forDay: nextDay, lessons: lessons, exams: exams, events: events, eventsVisible: eventsVisible, calendar: calendar)
        return attachNoSchool(note, day: nextDay, lessons: lessons, events: events, eventsVisible: eventsVisible, noSchoolDays: noSchoolDays, calendar: calendar)
    }

    /// Mai nap rendkívüliségei a "Mai nap" widgetnek.
    static func todayNote(
        lessons: [LessonItem],
        exams: [ExamItem] = [],
        events: [SchoolEvent] = [],
        eventsVisible: Bool = true,
        noSchoolDays: [TimetableWidgetStore.NoSchoolDay] = [],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TimetableWidgetStore.NextDayNote? {
        let note = dayNote(forDay: now, lessons: lessons, exams: exams, events: events, eventsVisible: eventsVisible, calendar: calendar)
        return attachNoSchool(note, day: now, lessons: lessons, events: events, eventsVisible: eventsVisible, noSchoolDays: noSchoolDays, calendar: calendar)
    }

    /// Teljes heti snapshot írása (TimetableView.load() végéről).
    /// Változatlan tartalomnál nincs írás és nincs reload-kérés sem
    /// (lásd TimetableWidgetStore.save).
    static func publishWeek(_ lessons: [LessonItem], homeworks: [HomeworkItem] = [], exams: [ExamItem] = [], events: [SchoolEvent] = [], eventsVisible: Bool = true, noSchoolDays: [TimetableWidgetStore.NoSchoolDay] = []) {
        guard !lessons.isEmpty else { return }
        let preview = previewState()
        guard TimetableWidgetStore.save(TimetableWidgetStore.Snapshot(
            savedAt: Date(), accentHex: currentAccentHex(),
            lessons: fromLessons(lessons, homeworks: homeworks, exams: exams),
            previewActive: preview.active, previewMinutes: preview.minutes,
            nextNote: nextDayNote(lessons: lessons, exams: exams, events: events, eventsVisible: eventsVisible, noSchoolDays: noSchoolDays),
            todayInfo: todayNote(lessons: lessons, exams: exams, events: events, eventsVisible: eventsVisible, noSchoolDays: noSchoolDays)
        )) else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: TimetableWidgetStore.kind)
        WidgetCenter.shared.reloadTimelines(ofKind: TimetableWidgetStore.dayKind)
    }

    /// Mai nap mergelése háttér-ébresztésből (csak a mai szelet frissül).
    /// Csak akkor ír, ha már létezik snapshot (azaz a user egyszer
    /// megnyitotta az Órarendet) — üres állapotot nem kreál.
    /// Változatlan tartalomnál nincs reload-kérés sem.
    static func mergeToday(_ lessons: [LessonItem], now: Date = Date()) {
        let dayLessons = lessons.filter { Calendar.current.isDate($0.start, inSameDayAs: now) }
        guard TimetableWidgetStore.mergeDay(
            lessons: fromLessons(dayLessons), day: now, accentHex: currentAccentHex()
        ) else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: TimetableWidgetStore.kind)
        WidgetCenter.shared.reloadTimelines(ofKind: TimetableWidgetStore.dayKind)
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
        WidgetCenter.shared.reloadTimelines(ofKind: TimetableWidgetStore.dayKind)
    }
}
