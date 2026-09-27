import Foundation

// MARK: - Közös állapot-építés iOS-re és Mac Catalystre
//
// A push-terv feltöltés (SummitPushSync.buildEntries/kick) Mac-en is futhat,
// ezért az órarend → ContentState leképezésnek mindkét platformon elérhetőnek
// kell lennie — ActivityKit nélkül. Single source of truth: ha itt változol,
// az iOS Live Activity ÉS a Mac-es feltöltés is ugyanazt használja.

@MainActor
extension SummitLiveActivityManager {
    /// A token-kérés dobott és nil-lel (tisztán helyi módban). Utóbbi azt
    /// jelenti, hogy a build profiljában nincs Push — token sosem jön,
    /// a feltöltés tartósan kimarad (javított profillal újratelepítés kell).
    /// Perzisztens, mert az ok a buildhez kötődik, nem az activityhez
    /// (az app törlése viszi, így a javított build tiszta lappal indul).
    static let pushTypeNilKey = "liveActivity.pushTypeNil.v1"

    static func makeState(today: [LessonItem], current: LessonItem?, next: LessonItem?, now: Date) -> SummitLiveActivityAttributes.ContentState {
        // Hátralévő terv: múltbeli órák nélkül (méret-takarékosság, < 4 KB).
        let plan = today
            .filter { $0.end > now }
            .map {
                PlanLesson(subject: $0.subject, room: $0.room, teacher: $0.teacher,
                           index: $0.index, start: $0.start, end: $0.end,
                           isCancelled: $0.isCancelled, isSubstituted: $0.isSubstituted)
            }
        let dayEnd = plan.last?.end ?? now.addingTimeInterval(60)
        if let cur = current {
            var lessonEnd = cur.end
            if lessonEnd <= cur.start { lessonEnd = cur.start.addingTimeInterval(45 * 60) }
            return SummitLiveActivityAttributes.ContentState(
                subject: cur.subject, room: cur.room, teacher: cur.teacher, index: cur.index,
                isCancelled: cur.isCancelled, isSubstituted: cur.isSubstituted,
                lessonStart: cur.start, lessonEnd: lessonEnd,
                nextSubject: next?.subject, nextRoom: next?.room, nextStart: next?.start,
                phase: "lesson",
                // Nap végéig élő: óra közben nincs "stale" hervadás.
                staleDate: dayEnd,
                plan: plan, dayEnd: dayEnd
            )
        } else if let nxt = next {
            var breakEnd = nxt.start
            if breakEnd <= now { breakEnd = now.addingTimeInterval(60) }
            // A szünet kezdete az előző óra vége (nem a sync pillanata!):
            // így a break-állapot syncről syncre azonos, amíg a határok nem
            // változnak — enélkül a változás-figyelés sosem találna egyezést,
            // és minden percben kimenne egy felesleges update. A progress
            // csík is így értelmes (szünet eleje → következő óra kezdete).
            let breakStart = today.last(where: { $0.end <= now })?.end ?? now
            return SummitLiveActivityAttributes.ContentState(
                subject: "Szünet", room: nxt.room, teacher: nxt.teacher, index: nxt.index,
                isCancelled: false, isSubstituted: false,
                lessonStart: min(breakStart, breakEnd), lessonEnd: breakEnd,
                nextSubject: nxt.subject, nextRoom: nxt.room, nextStart: nxt.start,
                phase: "break",
                staleDate: dayEnd,
                plan: plan, dayEnd: dayEnd
            )
        } else {
            // Ide a guard miatt nem jutunk (nincs cur és nincs nxt), de a
            // típus teljessége miatt lefedjük: üres záró állapot.
            return SummitLiveActivityAttributes.ContentState(
                subject: "–", room: "", teacher: "", index: "",
                isCancelled: false, isSubstituted: false,
                lessonStart: now, lessonEnd: now.addingTimeInterval(60),
                nextSubject: nil, nextRoom: nil, nextStart: nil,
                phase: "empty", staleDate: dayEnd, plan: plan, dayEnd: dayEnd
            )
        }
    }
}
