import SwiftUI
#if os(watchOS)
import WatchKit
#endif

// MARK: - Órarend az órán — a telefonos editorial dizájn tükre, kompaktan
// Liquid glass óraszám-kör + badge + tárgy + terem/tanár + idősáv.
// Az aktuális óra kék tintet + vékony progresst kap. Koronával görgethető
// natív lista; napok közt a felső léptetővel lehet mozogni.
struct TimetableWatchView: View {
    @EnvironmentObject var store: WatchSyncStore
    @State private var selectedDay: Date?
    @State private var initializedForSavedAt: Date?

    private var colors: AppColors { .darkRevamped }
    private var accent: Color { Color(hex: UInt(store.accentHex)) }
    private var lessons: [TimetableWidgetStore.Lesson] {
        store.timetable?.lessons.sorted { $0.start < $1.start } ?? []
    }
    private var days: [Date] {
        let cal = Calendar.current
        return Array(Set(lessons.map { cal.startOfDay(for: $0.start) })).sorted()
    }

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 30)) { timeline in
            // Fejlesztői idő-előnézet: ha az iPhone csúszkája aktív, az óra
            // is az eltolt idő szerint rajzol (aktuális óra, progress, nap).
            let now = store.previewNow ?? timeline.date
            Group {
                if lessons.isEmpty && dayEvents(now: now).isEmpty {
                    ContentUnavailableView(
                        "Nincs órarend",
                        systemImage: "clock",
                        description: Text("Nyisd meg az Órarendet iPhone-on.")
                    )
                } else {
                    VStack(spacing: 0) {
                        if !lessons.isEmpty {
                            dayPager(days: days, now: now)
                        }
                        if let err = store.lastSyncError {
                            Text(err)
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                        }
                        List {
                            ForEach(dayEvents(now: now)) { event in
                                WatchSchoolEventRow(event: event, accent: accent)
                                    .listRowBackground(Color.clear)
                            }
                            ForEach(dayLessons(now: now), id: \.id) { lesson in
                                WatchLessonRow(
                                    lesson: lesson,
                                    isCurrent: lesson.start <= now && now <= lesson.end,
                                    isLast: lesson.id == dayLessons(now: now).last?.id,
                                    progress: progress(of: lesson, now: now),
                                    remainingText: remainingText(of: lesson, now: now),
                                    accent: accent,
                                    colors: colors
                                )
                                .listRowBackground(Color.clear)
                            }
                        }
                        .listStyle(.plain)
                        .refreshable { await store.requestSyncNow() }
                    }
                }
            }
            .onAppear { smartSelect(now: now) }
            .onChange(of: store.timetable?.savedAt) { smartSelect(now: now) }
            // Az előnézet utólag is beeshet (az első render még valós
            // idővel választ napot, aztán megjön a csúszka állása) —
            // ilyenkor muszáj újraválasztani, különben az óra beragad
            // egy rossz napra. Kézi lapozás ilyenkor eldobódik (dev
            // akció, az adatváltás amúgy is felülírná).
            .onChange(of: store.previewNow) { smartSelect(now: now, force: true) }
        }
        // A TabView-oldal legfelső szintjén: ha ez csak a belső VStacken
        // van, az első (üres) renderelés beragasztja a térközt, és a későn
        // megjövő adat már nem tudja összeomlasztani.
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Napválasztás

    /// A "Ma" gomb célja: ma, ha még van hátra óra; különben a következő
    /// órás nap (hétvégén pl. a hétfő). Sosem mutat üres napra, amíg van
    /// órarendi adat — az üres nap + tiltott chevronok okozták a hétvégi
    /// "meghalást".
    private func maTarget(now: Date) -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        if lessons.contains(where: { $0.end > now && cal.isDate($0.start, inSameDayAs: now) }) {
            return today
        }
        if let next = days.first(where: { $0 > today }) { return next }
        return days.last ?? today
    }

    private func smartSelect(now: Date, force: Bool = false) {
        // Telefonnal azonosan: ha a mai órák még tartanak/hátravannak, ma;
        // különben a következő órás nap. Kézi lapozás után nem nyúlunk hozzá.
        if !force, selectedDay != nil, initializedForSavedAt == store.timetable?.savedAt { return }
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        if lessons.contains(where: { $0.end > now && cal.isDate($0.start, inSameDayAs: now) }) {
            selectedDay = today
        } else if let next = days.first(where: { $0 > today }) {
            selectedDay = next
        } else {
            selectedDay = days.last ?? today
        }
        initializedForSavedAt = store.timetable?.savedAt
    }

    private func dayLessons(now: Date) -> [TimetableWidgetStore.Lesson] {
        let day = selectedDay ?? Calendar.current.startOfDay(for: now)
        return lessons.filter { Calendar.current.isDate($0.start, inSameDayAs: day) }
    }

    // MARK: - Iskolai események (tannaptár) — a telefonnal azonosan a lista tetején
    private func dayEvents(now: Date) -> [WatchSchoolEvent] {
        guard let snap = store.schoolEvents, snap.visible else { return [] }
        let day = selectedDay ?? Calendar.current.startOfDay(for: now)
        let key = Self.dayKey(day)
        return snap.events.filter { $0.day == key }.sorted {
            if $0.allDay != $1.allDay { return $0.allDay && !$1.allDay }
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.title < $1.title
        }
    }

    private static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func progress(of lesson: TimetableWidgetStore.Lesson, now: Date) -> Double {
        guard lesson.start <= now && now <= lesson.end else { return 0 }
        let total = lesson.end.timeIntervalSince(lesson.start)
        guard total > 0 else { return 0 }
        return min(1, max(0, now.timeIntervalSince(lesson.start) / total))
    }

    private func remainingText(of lesson: TimetableWidgetStore.Lesson, now: Date) -> String {
        let rem = Int(ceil(lesson.end.timeIntervalSince(now) / 60))
        if rem <= 0 { return "Vége" }
        return "\(rem)p"
    }

    // Üvegkapszulás napléptető az óra sávjában ("‹ Ma ›" pill).
    // A kapszula a tartalomra simul, a maxWidth-frame pedig balra
    // rögzíti — így a rendszeróra (jobb oldal) felé mindig marad lélegző
    // hely. A hétköznap rövid (3 betűs), hogy sose érjen az órába.
    @ViewBuilder
    private func dayPager(days: [Date], now: Date) -> some View {
        let cal = Calendar.current
        let day = selectedDay ?? cal.startOfDay(for: now)
        let idx = days.firstIndex(of: day)
        HStack(spacing: 6) {
            Button {
                // Naplépés = választás: halk click, de csak ha tényleg
                // lép (szinkron-választáskor és tiltott gombon néma).
                if let i = idx, i > 0 {
                    selectedDay = days[i - 1]
                    WatchHaptics.tick()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(idx == nil || idx == 0 ? .tertiary : .primary)
                    .frame(width: 22, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(idx == nil || idx == 0)
            .accessibilityLabel("Előző nap")
            Button {
                // Hétvégén / tanítás után a "Ma" üres napra állna (az órák
                // listája elfogyna — ez nézett ki összeomlásnak, és a
                // chevronok is beragadtak volna tiltva): ilyenkor a
                // következő órás napra ugrik (smartSelect-logika).
                let target = maTarget(now: now)
                if selectedDay != target {
                    selectedDay = target
                    WatchHaptics.tick()
                }
                initializedForSavedAt = store.timetable?.savedAt
            } label: {
                Text(dayTitle(day, now: now))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(cal.isDate(day, inSameDayAs: now) ? accent : .primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Vissza a mai napra")
            Button {
                if let i = idx, i + 1 < days.count {
                    selectedDay = days[i + 1]
                    WatchHaptics.tick()
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(idx == nil || idx == days.count - 1 ? .tertiary : .primary)
                    .frame(width: 22, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(idx == nil || idx == days.count - 1)
            .accessibilityLabel("Következő nap")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .watchGlassPill()
        // A lista az óra sávja alá is benyúlik (ignoresSafeArea) —
        // görgetéskor a sorok a pill ALÁ csúsznak, nem fölé.
        .zIndex(1)
        .frame(maxWidth: 132, alignment: .leading)
        // A TabView-oldalnak fix belső térköze van (S9 45 mm-en kimérve:
        // fent ~35 pt, balra ~7 pt) — ezt csak negatív padding egyenlíti
        // ki, hogy a pill az óra sávjába kerüljön, egy vonalba az idővel.
        // Képernyőképpel belőve S9 45 mm-en (cél: szöveg ~39px-nél,
        // egy vonalban az órával) — ne piszkáld.
        // A leading padding itt hatástalan (a maxWidth-frame rögzíti a
        // sort), ezért a bal sarokba offset visz: chevron ~48px-ről
        // ~14px-re. Csak render-eltolás, a lista nem mozdul.
        .padding(.leading, -7)
        .padding(.top, 16)
        .padding(.bottom, 10)
        .offset(x: -17)
    }

    private func dayTitle(_ day: Date, now: Date) -> String {
        let cal = Calendar.current
        if cal.isDate(day, inSameDayAs: now) { return "Ma" }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)),
           cal.isDate(day, inSameDayAs: tomorrow) { return "Holnap" }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "hu_HU")
        fmt.dateFormat = "EEEE"
        let name = fmt.string(from: day)
        // Rövid alak a felső sávba: Hét / Ked / Sze / Csü / Pén.
        let short = String(name.prefix(3))
        return short.prefix(1).uppercased() + short.dropFirst()
    }
}

// MARK: - Iskolai esemény-sor — SchoolEventCard (telefon) kompakt tükre
private struct WatchSchoolEventRow: View {
    let event: WatchSchoolEvent
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                Text("ISKOLAI ESEMÉNY")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
                Text(event.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                if !event.subtitle.isEmpty {
                    Text(event.subtitle)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            // Teljes sorszélesség (mint a telefon full-width kártyája):
            // a frame a háttér ELŐTT jön, hogy a színezett kártya is
            // végigérjen, ne csak a szöveg szélességéig.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(accent.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(accent.opacity(0.30), lineWidth: 1)
                )
        )
        .padding(.vertical, 2)
    }
}

// MARK: - Órasor — TimetableRow (telefon) kompakt tükre
private struct WatchLessonRow: View {
    let lesson: TimetableWidgetStore.Lesson
    let isCurrent: Bool
    let isLast: Bool
    let progress: Double
    let remainingText: String
    let accent: Color
    let colors: AppColors
    @Environment(\.colorScheme) var scheme

    private var ringTint: Color? {
        if lesson.isExempted { return .green }
        if lesson.isCancelled { return .red }
        if lesson.isSubstituted { return .orange }
        if isCurrent { return .blue }
        return nil
    }
    private var numberColor: Color {
        ringTint ?? .white
    }
    private var progressTint: Color {
        if lesson.isExempted { return .green }
        if lesson.isCancelled { return .red }
        if lesson.isSubstituted { return .orange }
        return .blue
    }
    private var badgeLabel: String? {
        if lesson.isExempted { return "Felmentett" }
        if lesson.isCancelled { return "Elmarad" }
        if lesson.isSubstituted { return "Helyettesítés" }
        return nil
    }
    private var badgeColor: Color {
        if lesson.isExempted { return .green }
        if lesson.isCancelled { return .red }
        return .orange
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // LEFT — glass óraszám-kör (mint a telefonon)
            Text(lesson.index)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(numberColor)
                .frame(width: 28, height: 28)
                .background {
                    Circle()
                        .fill(Color.clear)
                        .watchTintedGlassCircle(tint: (ringTint ?? .white).opacity(isCurrent ? 0.18 : 0.08))
                }
                .padding(.top, 2)

            // CENTER — editorial tartalom (kompakt: meta egy sorban)
            VStack(alignment: .leading, spacing: 2) {
                if let lbl = badgeLabel {
                    Text(lbl.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(0.4)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(badgeColor))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                Text(lesson.subject)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle((lesson.isCancelled || lesson.isExempted) ? .secondary : .primary)
                    .strikethrough((lesson.isCancelled || lesson.isExempted), color: .secondary)
                    .lineLimit(2)
                // A teremnév a fontos, az idősáv nem: a terem a teljes
                // sorszélességet megkapja és legfeljebb két sorba törik
                // ("Kollégium / gépterem"), az idősáv alatta külön sorban.
                // Egymás mellett a pill olyan keskeny lenne, hogy még egy
                // egész szó sem férne ki (szótag-elválasztás jönne).
                VStack(alignment: .leading, spacing: 3) {
                    if !lesson.room.isEmpty {
                        Text(lesson.room)
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(accent)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .watchGlassCube(tint: accent.opacity(0.16))
                            .lineLimit(2)
                            .truncationMode(.tail)
                    }
                    Text(timeRange)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isCurrent {
                    HStack(alignment: .center, spacing: 6) {
                        ProgressView(value: progress)
                            .tint(progressTint)
                        Text(remainingText)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.top, 1)
                }
            }
        }
        .padding(.vertical, 3)
    }

    private var timeRange: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "hu_HU")
        fmt.dateFormat = "H:mm"
        return "\(fmt.string(from: lesson.start))–\(fmt.string(from: lesson.end))"
    }
}
