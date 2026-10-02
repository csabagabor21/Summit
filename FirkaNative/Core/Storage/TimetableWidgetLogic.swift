import Foundation

// MARK: - Widget timeline-logika — tiszta, UI-független számítások
// A Widget Extension ÉS a /tmp-s próbák is ezt fordítják (csak Foundation),
// így a provider viselkedése a szállított kóddal ellenőrizhető.
// A provider (TimetableWidget.swift) kizárólag ezeket hívja.
enum TimetableWidgetLogic {
    /// Napválasztás adott időpontra: ma, ha van még hátra / tartó óra —
    /// különben a következő órás nap a snapshotból.
    static func pickDay(now: Date, lessons: [TimetableWidgetStore.Lesson], calendar: Calendar = .current) -> (Date, [TimetableWidgetStore.Lesson]) {
        let cal = calendar
        let todays = lessons.filter { cal.isDate($0.start, inSameDayAs: now) }.sorted { $0.start < $1.start }
        if todays.contains(where: { $0.end > now }) {
            return (cal.startOfDay(for: now), todays)
        }
        let upcoming = lessons.filter { $0.start > now }.sorted { $0.start < $1.start }
        if let first = upcoming.first {
            let day = cal.startOfDay(for: first.start)
            return (day, lessons.filter { cal.isDate($0.start, inSameDayAs: day) }.sorted { $0.start < $1.start })
        }
        return (cal.startOfDay(for: now), todays)
    }

    /// Timeline-pillanatok: most + minden hátra lévő mai órahatár
    /// (kezdés/vég). Csak a határok: az élő visszaszámlálót a
    /// Text(timerInterval:) magától tickeli reload nélkül, az 5 perces
    /// köztes belépők csak a WidgetKit-költségkeretet égették (a
    /// költségkeret kimerülése = beragadt, "meghalt" widget).
    /// A lista így magától továbbmegy órahatárokon át, késleltetett
    /// rendszer-újratöltés mellett is. Max `cap` elem, időrendben.
    static func timelineMoments(now: Date, lessons: [TimetableWidgetStore.Lesson], calendar: Calendar = .current, cap: Int = 61) -> [Date] {
        let cal = calendar
        let todays = lessons.filter { cal.isDate($0.start, inSameDayAs: now) }.sorted { $0.start < $1.start }
        var moments = Set<Date>()
        for l in todays {
            if l.start > now { moments.insert(l.start) }
            if l.end > now { moments.insert(l.end) }
        }
        guard !moments.isEmpty else { return [] }
        return [now] + Array(moments.sorted().prefix(cap - 1))
    }

    /// Lista-ablak a medium/large nézetnek: legfelül a tartó óra (ha nincs,
    /// a következő), alatta a rákövetkezők, max `maxRows` sor. Így az 5. óra
    /// alatt az 5–6–7. látszik, nem az 1–2–3. A `later` a rejtett hátralévők
    /// ("+N további óra"), az `earlier` a feljebb lévők száma.
    static func window(lessons: [TimetableWidgetStore.Lesson], now: Date, maxRows: Int) -> (earlier: Int, rows: [TimetableWidgetStore.Lesson], later: Int) {
        let sorted = lessons.sorted { $0.start < $1.start }
        guard !sorted.isEmpty else { return (0, [], 0) }
        let r = resolve(at: now, lessons: sorted)
        var startIdx = 0
        if let cur = r.current, let i = sorted.firstIndex(where: { $0.id == cur.id }) {
            startIdx = i
        } else if let nxt = r.next, let i = sorted.firstIndex(where: { $0.id == nxt.id }) {
            startIdx = i
        } else if let last = sorted.last, now >= last.end {
            // Nap vége (nincs több adat): az utolsó sorok maradnak láthatóan.
            startIdx = max(0, sorted.count - maxRows)
        }
        let rows = Array(sorted[startIdx...].prefix(maxRows))
        return (startIdx, rows, sorted.count - startIdx - rows.count)
    }

    /// Egy belépő felbontása: tartó és következő óra az adott időpontban.
    /// (A small nézet ebből dönt: tartó → "Most", következő → "Következő",
    /// egyik sem → "Mára vége"; a medium lista ugyanígy emel ki.)
    static func resolve(at now: Date, lessons: [TimetableWidgetStore.Lesson]) -> (current: TimetableWidgetStore.Lesson?, next: TimetableWidgetStore.Lesson?) {
        let sorted = lessons.sorted { $0.start < $1.start }
        let current = sorted.first(where: { $0.start <= now && $0.end >= now })
        let next = sorted.first(where: { $0.start > now })
        return (current, next)
    }

    /// Következő órakezdés / óravég az ELTOLT órához mérve, valós időre
    /// visszaszámolva (így a csúszkás preview sem pörgeti a timeline-t),
    /// de legkésőbb +8 óra (WidgetKit büdzsé). Az egy-belépős
    /// fallback-úthoz (nincs adat / üres nap / dev csúszka).
    static func nextRefresh(now: Date, effectiveNow: Date, lessons: [TimetableWidgetStore.Lesson]) -> Date {
        let cap = now.addingTimeInterval(8 * 3600)
        let bounds = lessons.flatMap { [$0.start, $0.end] }.filter { $0 > effectiveNow }.sorted()
        guard let next = bounds.first else { return cap }
        let refresh = now.addingTimeInterval(next.timeIntervalSince(effectiveNow) + 60)
        return min(max(refresh, now.addingTimeInterval(60)), cap)
    }
}
