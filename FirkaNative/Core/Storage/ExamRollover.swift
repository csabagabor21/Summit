import Foundation

/// Dolgozat-pótlás hiányzáskor (kapcsolható feature):
/// ha a dolgozat napján hiányoztál, a dolgozat átkerül a következő olyan
/// órára és piros körvonalat kap; ha arról az óráról is hiányzol, továbbmegy.
/// Swipe-pal elvethető (olyankor az eredeti dátumon marad).
///
/// Megjelenítési minta: a nézetek a `displayItems`-szel dolgoznak (az
/// átütemezett dolgozat új dátummal, de azonos ID-val jön — a pipák,
/// csatolmányok és az óracsatolás így megmaradnak), a `rolledIDs` alapján
/// rajzolják a piros keretet.
enum ExamRollover {
    /// Kapcsoló (hiányzó kulcs = BE, mint az értesítési kapcsolóknál).
    static let enabledKey = "exams.rolloverOnAbsence"
    /// Elvetett átütemezések (dolgozat-ID-k) — eszköz-helyi műkődési állapot.
    static let dismissedKey = "exams.rolloverDismissed.v1"
    static let changedNotification = Notification.Name("summit.examRolloverChanged")

    struct Resolution {
        /// Melyik napon mutassuk.
        var displayDate: Date
        /// Át lett-e téve (hiányzás miatt).
        var rolled: Bool
        /// Eredeti KRÉTA-dátum (az "Eredeti:" sorhoz).
        var originalDate: Date
        /// Betöltött órarendi órára esik-e (nem naptár-becslés).
        var viaLesson: Bool
    }

    static func isEnabled() -> Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: enabledKey)
        NotificationCenter.default.post(name: changedNotification, object: nil)
    }

    static func isDismissed(_ id: String) -> Bool { dismissed().contains(id) }

    /// Swipe-elvetés: az átütemezés eldobása, az eredeti dátum marad.
    static func dismiss(_ id: String) {
        var s = dismissed()
        s.insert(id)
        UserDefaults.standard.set(Array(s), forKey: dismissedKey)
        NotificationCenter.default.post(name: changedNotification, object: nil)
    }

    private static func dismissed() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: dismissedKey) ?? [])
    }

    /// Egy dolgozat feloldása: hiányzás a dolgozat napján → következő olyan
    /// óra (azonos tárgy, a dolgozat napja után, még nem elmúlt, hiányzás-
    /// mentes napon). Ha arról is van hiányzás, automatikusan továbbmegy.
    static func resolve(exam: ExamItem, absences: [AbsenceItem], lessons: [LessonItem],
                        now: Date = Date(), calendar: Calendar = .current) -> Resolution {
        let original = exam.date
        let plain = Resolution(displayDate: original, rolled: false, originalDate: original, viaLesson: false)
        guard isEnabled(), !isDismissed(exam.id) else { return plain }
        let absenceDays = Set(absences.map { calendar.startOfDay(for: $0.date) })
        let examDay = calendar.startOfDay(for: original)
        guard absenceDays.contains(examDay) else { return plain }
        let today = calendar.startOfDay(for: now)
        // Következő olyan óra a betöltött órarendből (max 60 nap előre).
        var seenDays = Set<Date>()
        for lesson in lessons.filter({ SubjectMatcher.same($0.subject, exam.subject) }).sorted(by: { $0.start < $1.start }) {
            let day = calendar.startOfDay(for: lesson.start)
            guard day > examDay, day >= today else { continue }
            guard seenDays.insert(day).inserted else { continue }
            guard !absenceDays.contains(day) else { continue }
            guard (calendar.dateComponents([.day], from: today, to: day).day ?? 0) <= 60 else { break }
            return Resolution(displayDate: lesson.start, rolled: true, originalDate: original, viaLesson: true)
        }
        // Nincs betöltött óra ilyen tárgyból: a következő hiányzásmentes
        // tanítási nap (becslés, max 14 nap) — swipe-pal elvethető.
        var day = max(examDay, today)
        for _ in 0..<14 {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
            let wd = calendar.component(.weekday, from: day)
            guard wd >= 2 && wd <= 6 else { continue }
            guard !absenceDays.contains(day) else { continue }
            return Resolution(displayDate: day, rolled: true, originalDate: original, viaLesson: false)
        }
        return plain
    }

    /// Megjelenítési lista a nézeteknek: átütemezett dolgozat új dátummal
    /// (ID marad), a piros kerethez ID-halmaz, a részletezőhöz eredeti dátum.
    static func displayItems(exams: [ExamItem], absences: [AbsenceItem], lessons: [LessonItem],
                             now: Date = Date(), calendar: Calendar = .current)
    -> (items: [ExamItem], rolledIDs: Set<String>, originalDates: [String: Date]) {
        var items: [ExamItem] = []
        var rolled: Set<String> = []
        var originals: [String: Date] = [:]
        for e in exams {
            let r = resolve(exam: e, absences: absences, lessons: lessons, now: now, calendar: calendar)
            guard r.rolled else {
                items.append(e)
                continue
            }
            rolled.insert(e.id)
            originals[e.id] = e.date
            items.append(ExamItem(id: e.id, subject: e.subject, date: r.displayDate, mode: e.mode,
                                  description: e.description, teacher: e.teacher, lessonIndex: e.lessonIndex,
                                  announcedDate: e.announcedDate, groupName: e.groupName,
                                  attachments: e.attachments))
        }
        return (items, rolled, originals)
    }
}
