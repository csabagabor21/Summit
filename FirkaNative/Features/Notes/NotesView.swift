import SwiftUI

struct NotesView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var kreta: KretaClient
    @EnvironmentObject var completed: CompletedStore
    @State private var homeworks: [HomeworkItem] = []
    @State private var exams: [ExamItem] = []
    /// Órarendi órák az óraszám-pillekhez (a csatolmány-lehúzás mellékterméke).
    @State private var lessons: [LessonItem] = []
    @State private var isLoading = true
    @State private var filter = 0 // 0 = Feladatok, 1 = Dolgozatok, 2 = Kész
    @State private var expandedIDs: Set<String> = []
    @State private var flashedID: String?
    @State private var flashPulse = false
    @State private var scrollProxy: ScrollViewProxy?
    private let switchToTasks = Notification.Name("summit.switchToTasks")
    @Environment(\.colorScheme) var scheme
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPad: Bool { hSize == .regular }
    var colors: AppColors { theme.colors(for: scheme) }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            List {
                Section {
                    Picker("", selection: $filter) {
                        Text("Feladatok").tag(0); Text("Dolgozatok").tag(1); Text("Kész").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(.hidden)
                    .animation(SummitMotion.gentle, value: filter)
                }

                if isLoading {
                    ForEach(0..<3, id: \.self) { _ in
                        HStack { Text("Betöltés…").redacted(reason: .placeholder) }
                            .listRowBackground(colors.surface)
                    }
                } else if currentIsEmpty {
                    Section {
                        ContentUnavailableView(
                            filter == 1 ? "Nincs dolgozat" : filter == 2 ? "Nincs kész feladat" : "Nincs feladat",
                            systemImage: filter == 1 ? "doc.text" : "checklist",
                            description: Text(filter == 1 ? "Nincs bejelentett számonkérés" : filter == 2 ? "A kipipált feladatok ide kerülnek" : "Minden kész")
                        )
                            .frame(maxWidth: .infinity, minHeight: 220)
                            .padding(.vertical, 16)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 24, leading: 16, bottom: 24, trailing: 16))
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                } else {
                    // Napra bontott szekciók — nem ömlesztett lista.
                    Group {
                        if filter == 1 {
                            ForEach(examDayGroups, id: \.day) { g in
                                Section {
                                    ForEach(g.items, id: \.id) { exam in
                                        examRow(exam, isFlash: flashedID == exam.id)
                                    }
                                } header: {
                                    dayHeader(day: g.day, count: g.items.count)
                                }
                            }
                        } else if filter == 2 {
                            ForEach(doneDayGroups, id: \.day) { g in
                                Section {
                                    ForEach(g.items) { entry in
                                        switch entry {
                                        case .homework(let hw):
                                            homeworkRow(hw, isFlash: flashedID == hw.id)
                                        case .exam(let exam):
                                            examRow(exam, isFlash: flashedID == exam.id)
                                        }
                                    }
                                } header: {
                                    dayHeader(day: g.day, count: g.items.count)
                                }
                            }
                        } else {
                            ForEach(homeworkDayGroups, id: \.day) { g in
                                Section {
                                    ForEach(g.items, id: \.id) { hw in
                                        homeworkRow(hw, isFlash: flashedID == hw.id)
                                    }
                                } header: {
                                    dayHeader(day: g.day, count: g.items.count)
                                }
                            }
                        }
                    }
                    .id(filter)
                    .transition(.opacity)
                }
            }
            .listStyle(.insetGrouped)
            .frame(maxWidth: isPad ? MacSupport.contentWidth(ipad: 1000, mac: 1150) : .infinity)
            .frame(maxWidth: .infinity)
            .scrollContentBackground(.hidden)
            .background(colors.background)
            .animation(SummitMotion.gentle, value: currentIsEmpty)
            .animation(SummitMotion.gentle, value: filter)
            .navigationTitle("Feladatok")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.visible, for: .navigationBar)
            .task { await load() }
            .refreshable { await load() }
            // Órarend-pillből érkezve a megfelelő szegmensre ugrik + kiemeli a sort
            .onReceive(NotificationCenter.default.publisher(for: switchToTasks)) { notif in
                if (notif.userInfo?["segment"] as? String) == "exams" {
                    filter = 1
                } else {
                    filter = 0
                }
                if let fid = notif.userInfo?["flash"] as? String {
                    // Tabváltás után fusson, hogy a sorok már legyenek
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { flash(id: fid) }
                } else {
                    flashedID = nil; flashPulse = false
                }
            }
            .onAppear { scrollProxy = proxy }
            }
        }
        .tint(colors.accent)
    }

    /// Kiemelőszínű flash + odagörgetés az órarendből átjött feladathoz/dolgozathoz.
    private func flash(id: String) {
        withAnimation { flashedID = id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeInOut(duration: 0.45).repeatCount(3, autoreverses: true)) { flashPulse = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation { scrollProxy?.scrollTo(id, anchor: .center) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation { flashedID = nil; flashPulse = false }
        }
    }

    // Élő házi: kipipált és lejárt nem jelenik meg (a Készbe kerül),
    // Home-on a kipipált zölden marad
    var filteredHomeworks: [HomeworkItem] {
        homeworks.filter { !completed.isHomeworkDone($0.id) && !HomeworkExpiry.isExpired($0) }.sorted { $0.deadline < $1.deadline }
    }
    /// Kész szegmens: kipipált + lejárt házi és lejárt dolgozat, időrendben.
    /// A kipipálás innen vissza is vonható; a lejárt csak történet.
    enum DoneEntry: Identifiable {
        case homework(HomeworkItem)
        case exam(ExamItem)
        var id: String {
            switch self {
            case .homework(let hw): return "hw-" + hw.id
            case .exam(let ex): return "ex-" + ex.id
            }
        }
        var date: Date {
            switch self {
            case .homework(let hw): return hw.deadline
            case .exam(let ex): return ex.date
            }
        }
    }
    var doneEntries: [DoneEntry] {
        let today = Calendar.current.startOfDay(for: Date())
        // A dolgozat-történet nem nőhet végtelenre: az elmúlt 30 nap lejártjai
        // (a házi-lista amúgy is -30 napos ablakból jön).
        let examCutoff = Calendar.current.date(byAdding: .day, value: -30, to: today)!
        var out: [DoneEntry] = homeworks
            .filter { completed.isHomeworkDone($0.id) || $0.isDone || HomeworkExpiry.isExpired($0) }
            .map { .homework($0) }
        out += exams
            .filter { ExamExpiry.isExpired($0) && $0.date >= examCutoff }
            .map { .exam($0) }
        return out.sorted { $0.date < $1.date }
    }
    // Élő dolgozat: csak a mai és jövőbeli — a lejárt a Készbe kerül
    var filteredExams: [ExamItem] {
        exams.filter { !ExamExpiry.isExpired($0) }.sorted { $0.date < $1.date }
    }
    // MARK: - Napra bontás (Feladatok, Dolgozatok, Kész — mindhárom)
    private func groupByDay<T>(_ items: [T], date: (T) -> Date) -> [(day: Date, items: [T])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: items) { cal.startOfDay(for: date($0)) }
        return grouped.keys.sorted().map { day in
            (day: day, items: grouped[day]!.sorted { date($0) < date($1) })
        }
    }
    var homeworkDayGroups: [(day: Date, items: [HomeworkItem])] {
        groupByDay(filteredHomeworks) { $0.deadline }
    }
    var examDayGroups: [(day: Date, items: [ExamItem])] {
        groupByDay(filteredExams) { $0.date }
    }
    var doneDayGroups: [(day: Date, items: [DoneEntry])] {
        groupByDay(doneEntries) { $0.date }
    }
    /// Napcím: Ma / Holnap / Tegnap, különben "szept. 22., hétfő" + darabszám.
    private func dayHeader(day: Date, count: Int) -> some View {
        let cal = Calendar.current
        let title: String
        if cal.isDateInToday(day) { title = "Ma" }
        else if cal.isDateInTomorrow(day) { title = "Holnap" }
        else if cal.isDateInYesterday(day) { title = "Tegnap" }
        else {
            let f = DateFormatter(); f.locale = Locale(identifier: "hu_HU"); f.dateFormat = "MMM d., EEEE"
            title = f.string(from: day).capitalized
        }
        return Text("\(title) • \(count) db")
    }
    private var currentIsEmpty: Bool {
        if filter == 1 { return filteredExams.isEmpty }
        if filter == 2 { return doneEntries.isEmpty }
        return filteredHomeworks.isEmpty
    }
    // Magyar dátum — az eszköz nyelve angol is lehet, a KRÉTA-dátum éjfélkor időpont nélkül
    private func huDate(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "hu_HU"); f.dateFormat = "yyyy. MMM d."
        return f.string(from: d)
    }
    private func huDateTime(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        if c.hour == 0 && c.minute == 0 { return huDate(d) }
        let f = DateFormatter(); f.locale = Locale(identifier: "hu_HU"); f.dateFormat = "yyyy. MMM d. HH:mm"
        return f.string(from: d)
    }
    /// Házipill: nem a dátum (az a szekciófejlécben van), hanem hogy
    /// hányadik órára van feladva (tárgy + határidő-nap illesztéssel).
    private func lessonIndexText(for hw: HomeworkItem) -> String? {
        guard let lesson = HomeworkMatcher.lesson(for: hw, in: lessons) else { return nil }
        return "\(lesson.index). óra"
    }
    /// Részletező dátumsor: időpont (ha van) + hányadik óra
    private func examDateLine(_ exam: ExamItem) -> String {
        if let n = exam.lessonIndex { return "\(huDateTime(exam.date)) (\(n). óra)" }
        return huDateTime(exam.date)
    }
    private func toggleExpanded(_ id: String, expanded: Bool) {
        withAnimation(SummitMotion.snappy) {
            if expanded { expandedIDs.remove(id) } else { expandedIDs.insert(id) }
        }
    }

    @ViewBuilder
    private func homeworkRow(_ hw: HomeworkItem, isFlash: Bool = false) -> some View {
        let done = completed.isHomeworkDone(hw.id) || hw.isDone
        let expanded = expandedIDs.contains(hw.id)
        HStack(alignment: .top, spacing: 10) {
            Button { withAnimation(SummitMotion.snappy) { completed.toggleHomework(hw.id) } } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(done ? Color.green : .secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                // Csak a fejléc és az előnézet nyit-csuk — a kinyitott
                // részletező blokkban a gombok önállóan működnek
                HStack { Text(hw.subject).font(.subheadline.weight(.semibold)); Spacer(); if !hw.attachments.isEmpty { HStack(spacing: 3) { Image(systemName: "paperclip"); if hw.attachments.count > 1 { Text("\(hw.attachments.count)") } }.font(.caption2.weight(.semibold)).foregroundStyle(.secondary).accessibilityLabel("\(hw.attachments.count) csatolmány") }; if let idx = lessonIndexText(for: hw) { Text(idx).font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(Color.primary.opacity(0.06))) } }
                    .contentShape(Rectangle())
                    .onTapGesture { toggleExpanded(hw.id, expanded: expanded) }
                if expanded {
                    // Teljes szöveg KRÉTA-formázással (félkövér, listák, linkek),
                    // nyers HTML-tagek nélkül
                    Text(HomeworkHTML.formatted(hw.title))
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // Határidő időponttal — ebből látszik, melyik nap órájára csatolódik
                    Label(hw.deadline.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                        .font(.caption).foregroundStyle(.secondary)
                    if !hw.teacher.isEmpty {
                        Label(hw.teacher, systemImage: "person.fill")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    // Órarend-ugrás (a csatolmány-blokk fölött), majd a fájlok.
                    Button {
                        NotificationCenter.default.post(name: Notification.Name("summit.switchToTimetable"), object: nil, userInfo: ["subject": hw.subject, "deadline": hw.deadline.timeIntervalSince1970, "hwId": hw.id])
                    } label: {
                        Label("Mutatás az órarendben", systemImage: "calendar")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(colors.accent)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Capsule().strokeBorder(colors.accent.opacity(0.35), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    // Csatolt fájlok (PDF, kép…) — koppintásra QuickLook.
                    AttachmentsBlock(attachments: hw.attachments, ownerId: hw.id)
                } else {
                    Text(hw.plainTitle.isEmpty ? "(nincs leírás)" : hw.plainTitle)
                        .font(.callout).foregroundStyle(.secondary).lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { toggleExpanded(hw.id, expanded: expanded) }
                }
            }
            Spacer(minLength: 0)
            Button { toggleExpanded(hw.id, expanded: expanded) } label: {
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 6)
            }
            .buttonStyle(.plain)
        }
        .listRowBackground(done ? Color.green.opacity(scheme == .dark ? 0.10 : 0.07) : colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(colors.accent.opacity(isFlash ? (flashPulse ? 0.95 : 0.22) : 0), lineWidth: isFlash ? 2.2 : 0)
        )
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colors.accent.opacity(isFlash ? (flashPulse ? 0.16 : 0.04) : 0))
        )
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
    }

    @ViewBuilder
    private func examRow(_ exam: ExamItem, isFlash: Bool = false) -> some View {
        let expanded = expandedIDs.contains(exam.id)
        // Kipipálható (ready vagy-e), de a listában marad — nem tűnik el, mint a házi
        let ready = completed.isExamDone(exam.id)
        HStack(alignment: .top, spacing: 10) {
            Button { withAnimation(SummitMotion.snappy) { completed.toggleExam(exam.id) } } label: {
                Image(systemName: ready ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(ready ? Color.green : .secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                HStack { Text(exam.subject).font(.subheadline.weight(.semibold)); Spacer(); if let n = exam.lessonIndex { Text("\(n). óra").font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(Color.orange.opacity(0.14))) } }
                    .contentShape(Rectangle())
                    .onTapGesture { toggleExpanded(exam.id, expanded: expanded) }
                if expanded {
                    Text(exam.mode)
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !exam.plainDescription.isEmpty {
                        Text(exam.plainDescription)
                            .font(.callout).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !exam.teacher.isEmpty {
                        Label(exam.teacher, systemImage: "person.fill")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    // Dátum időponttal (éjfélkor csak dátum) + hányadik óra — a hivatalos
                    // app is írja: "2026. szeptember 15., kedd (1. óra)"
                    Label(examDateLine(exam), systemImage: "clock")
                        .font(.caption).foregroundStyle(.secondary)
                    if let announced = exam.announcedDate {
                        Label("Bejelentve: \(huDate(announced))", systemImage: "megaphone")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !exam.groupName.isEmpty {
                        Label(exam.groupName, systemImage: "person.2.fill")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button {
                        NotificationCenter.default.post(name: Notification.Name("summit.switchToTimetable"), object: nil, userInfo: ["subject": exam.subject, "deadline": exam.date.timeIntervalSince1970])
                    } label: {
                        Label("Mutatás az órarendben", systemImage: "calendar")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(colors.accent)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Capsule().strokeBorder(colors.accent.opacity(0.35), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    AttachmentsBlock(attachments: exam.attachments, ownerId: exam.id)
                } else {
                    Text(exam.plainDescription.isEmpty ? exam.mode : "\(exam.mode) • \(exam.plainDescription)")
                        .font(.callout).foregroundStyle(.secondary).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { toggleExpanded(exam.id, expanded: expanded) }
                }
            }
            Spacer(minLength: 0)
            Button { toggleExpanded(exam.id, expanded: expanded) } label: {
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 6)
            }
            .buttonStyle(.plain)
        }
        .listRowBackground(ready ? Color.green.opacity(scheme == .dark ? 0.10 : 0.07) : colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(colors.accent.opacity(isFlash ? (flashPulse ? 0.95 : 0.22) : 0), lineWidth: isFlash ? 2.2 : 0)
        )
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colors.accent.opacity(isFlash ? (flashPulse ? 0.16 : 0.04) : 0))
        )
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
    }

    func load() async {
        // Egy adatsáv: demo usert is a KretaClient szolgálja ki helyből.
        guard let user = session.selectedUser else { isLoading = false; return }
        isLoading=true; let iss=user.instituteCode.isEmpty ? (JWT.instituteCode(from: user.accessToken) ?? "") : user.instituteCode
        let hadData = !(homeworks.isEmpty && exams.isEmpty)
        let prevHW = homeworks, prevEx = exams
        async let hw = kreta.fetchHomework(iss: iss)
        async let ex = kreta.fetchExams(iss: iss)
        let (hwR, exR) = await (hw, ex)
        // Totális fetch-hiba (lejárt token, offline): a legutóbbi lista marad,
        // nem ürül ki a Feladatok tab egy sikertelen refresh-től.
        if hwR.isEmpty && exR.isEmpty && hadData {
            homeworks = prevHW; exams = prevEx
        } else {
            let (mergedHW, fetchedLessons) = await lessonAttachments(hwR, kreta: kreta, iss: iss)
            homeworks = mergedHW; exams = exR; lessons = fetchedLessons
        }
        isLoading=false
    }

    /// Firka-minta: a KRÉTA a fájlokat az órarendi elemre teszi
    /// (`OrarendElemek[].Csatolmanyok`), a házi-payloadban gyakran semmi
    /// sincs. A fájl a FELADÁS hetének óráján is lehet (HaziFeladatUid-kapocs),
    /// nem csak a határidő napján — ezért a teljes listaablakot (-35 nap)
    /// plusz a határidőket nézzük át, heti darabokban, párhuzamosan.
    /// Üres/sikertelen órarendnél a házi-lista változatlanul marad.
    private func lessonAttachments(_ hwR: [HomeworkItem], kreta: KretaClient, iss: String) async -> ([HomeworkItem], [LessonItem]) {
        guard !hwR.isEmpty else { return (hwR, []) }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let deadlines = hwR.map(\.deadline)
        guard let from = cal.date(byAdding: .day, value: -35, to: today),
              let to = cal.date(byAdding: .day, value: 2, to: cal.startOfDay(for: max(deadlines.max() ?? today, today))),
              to > from else { return (hwR, []) }
        // Heti darabolás (nagy ablakra az órarend-végpont megbízhatatlan),
        // max ~3 hónap — a listaablak és a tipikus határidők beleférnek.
        var chunks: [(Date, Date)] = []
        var cur = from
        while cur < to && chunks.count < 12 {
            let end = min(cal.date(byAdding: .day, value: 7, to: cur)!, to)
            chunks.append((cur, end))
            cur = end
        }
        let lessons: [LessonItem] = await withTaskGroup(of: [LessonItem].self) { group in
            for (s, e) in chunks {
                group.addTask { await kreta.fetchTimetable(iss: iss, from: s, to: e) }
            }
            var out: [LessonItem] = []
            for await part in group { out.append(contentsOf: part) }
            return out
        }
        // Ami órarendből sem jött meg (vagy üres volt az órarend),
        // annak a részlet-végpont adhat fájlt.
        if lessons.isEmpty { return (await kreta.fetchHomeworkDetails(hwR, iss: iss), []) }
        let merged = HomeworkLessonAttachments.merged(hwR, lessons: lessons)
        let hits = merged.filter { !$0.attachments.isEmpty }.count
        kreta.diag("feladat-csatolmány: \(hits)/\(hwR.count) házihoz van fájl (\(lessons.count) óra átnézve)")
        return (await kreta.fetchHomeworkDetails(merged, iss: iss), lessons)
    }
}

/// KRÉTA házi-szöveg (HTML) formázott megjelenítése: félkövér/dőlt,
/// aláhúzott/áthúzott, listák, linkek megmaradnak, nyers tagek nem látszanak.
/// Szándékosan NEM az NSAttributedString HTML-importjával: az WebKitet használ
/// és SwiftUI body-ból hívva AttributeGraph-crash-t (SIGABRT) okozott.
/// Ez kézi szegmens-építés (HomeworkRich) + Dynamic Type-barát preferred font,
/// színek nélkül — világos/sötét módban is a rendszer szövegszínével jelenik meg.
enum HomeworkHTML {
    static func formatted(_ html: String) -> AttributedString {
        let segs = HomeworkRich.segments(from: html)
        guard !segs.isEmpty else {
            let p = HomeworkPlain.text(from: html)
            return AttributedString(p.isEmpty ? "(nincs leírás)" : p)
        }
        var out = AttributedString()
        for s in segs {
            var c = AttributeContainer()
            var font = UIFont.preferredFont(forTextStyle: s.heading ? .headline : .body)
            var traits: UIFontDescriptor.SymbolicTraits = []
            if s.bold { traits.insert(.traitBold) }
            if s.italic { traits.insert(.traitItalic) }
            if !traits.isEmpty, let d = font.fontDescriptor.withSymbolicTraits(traits) {
                font = UIFont(descriptor: d, size: 0)
            }
            c.font = font
            if s.underline { c.underlineStyle = NSUnderlineStyle.single }
            if s.strike { c.strikethroughStyle = NSUnderlineStyle.single }
            if let l = s.link { c.link = l }
            var part = AttributedString(s.text)
            part.mergeAttributes(c)
            out += part
        }
        return out
    }
}
