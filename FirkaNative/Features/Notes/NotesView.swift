import SwiftUI

struct NotesView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var kreta: KretaClient
    @EnvironmentObject var completed: CompletedStore
    @State private var homeworks: [HomeworkItem] = []
    @State private var exams: [ExamItem] = []
    @State private var isLoading = true
    @State private var filter = 0 // 0 = Feladatok, 1 = Dolgozatok
    @State private var expandedIDs: Set<String> = []
    private let switchToTasks = Notification.Name("flint.switchToTasks")
    @Environment(\.colorScheme) var scheme
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPad: Bool { hSize == .regular }
    var colors: AppColors { theme.colors(for: scheme) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("", selection: $filter) {
                        Text("Feladatok").tag(0); Text("Dolgozatok").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(.hidden)
                    .animation(.spring(response: 0.34, dampingFraction: 0.82), value: filter)
                }

                if isLoading {
                    ForEach(0..<3, id: \.self) { _ in
                        HStack { Text("Betöltés…").redacted(reason: .placeholder) }
                            .listRowBackground(colors.surface)
                    }
                } else if currentIsEmpty {
                    Section {
                        ContentUnavailableView(
                            filter == 1 ? "Nincs dolgozat" : "Nincs feladat",
                            systemImage: filter == 1 ? "doc.text" : "checklist",
                            description: Text(filter == 1 ? "Nincs bejelentett számonkérés" : "Minden kész")
                        )
                            .frame(maxWidth: .infinity, minHeight: 220)
                            .padding(.vertical, 16)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 24, leading: 16, bottom: 24, trailing: 16))
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                } else {
                    Section {
                        if filter == 1 {
                            ForEach(filteredExams, id: \.id) { exam in
                                examRow(exam)
                            }
                        } else {
                            ForEach(filteredHomeworks, id: \.id) { hw in
                                homeworkRow(hw)
                            }
                        }
                    }
                    .id(filter)
                    .transition(.opacity)
                }
            }
            .listStyle(.insetGrouped)
            .frame(maxWidth: isPad ? 860 : .infinity)
            .frame(maxWidth: .infinity)
            .scrollContentBackground(.hidden)
            .background(colors.background)
            .animation(.spring(response: 0.36, dampingFraction: 0.84), value: currentIsEmpty)
            .animation(.spring(response: 0.36, dampingFraction: 0.84), value: filter)
            .navigationTitle("Feladatok")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.visible, for: .navigationBar)
            .task { await load() }
            .refreshable { await load() }
            // Órarend-pillből érkezve a Dolgozatok szegmensre ugrik
            .onReceive(NotificationCenter.default.publisher(for: switchToTasks)) { notif in
                if (notif.userInfo?["segment"] as? String) == "exams" {
                    filter = 1
                } else {
                    filter = 0
                }
            }
        }
        .tint(colors.accent)
    }

    // Kipipált házi nem jelenik meg (eltűnik a Feladatok tabról), Home-on marad zölden
    var filteredHomeworks: [HomeworkItem] {
        homeworks.filter { !completed.isHomeworkDone($0.id) }.sorted { $0.deadline < $1.deadline }
    }
    // Régi dolgozatok nem kellenek — tegnaptól felfelé, időrendben
    var filteredExams: [ExamItem] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))!
        return exams.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
    }
    private var currentIsEmpty: Bool { filter == 1 ? filteredExams.isEmpty : filteredHomeworks.isEmpty }
    private func toggleExpanded(_ id: String, expanded: Bool) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            if expanded { expandedIDs.remove(id) } else { expandedIDs.insert(id) }
        }
    }

    @ViewBuilder
    private func homeworkRow(_ hw: HomeworkItem) -> some View {
        let done = completed.isHomeworkDone(hw.id) || hw.isDone
        let expanded = expandedIDs.contains(hw.id)
        HStack(alignment: .top, spacing: 10) {
            Button { withAnimation(.spring(response: 0.3)) { completed.toggleHomework(hw.id) } } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(done ? Color.green : .secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                // Csak a fejléc és az előnézet nyit-csuk — a kinyitott
                // részletező blokkban a gombok önállóan működnek
                HStack { Text(hw.subject).font(.subheadline.weight(.semibold)); Spacer(); Text(hw.deadline.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(Color.primary.opacity(0.06))) }
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
                    Button {
                        NotificationCenter.default.post(name: Notification.Name("flint.switchToTimetable"), object: nil, userInfo: ["subject": hw.subject, "deadline": hw.deadline.timeIntervalSince1970])
                    } label: {
                        Label("Mutatás az órarendben", systemImage: "calendar")
                            .font(.caption.weight(.semibold))
                    }
                    .tint(colors.accent)
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
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
    }

    @ViewBuilder
    private func examRow(_ exam: ExamItem) -> some View {
        let expanded = expandedIDs.contains(exam.id)
        // Kipipálható (ready vagy-e), de a listában marad — nem tűnik el, mint a házi
        let ready = completed.isExamDone(exam.id)
        HStack(alignment: .top, spacing: 10) {
            Button { withAnimation(.spring(response: 0.3)) { completed.toggleExam(exam.id) } } label: {
                Image(systemName: ready ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(ready ? Color.green : .secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                HStack { Text(exam.subject).font(.subheadline.weight(.semibold)); Spacer(); Text(exam.date.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(Color.orange.opacity(0.14))) }
                    .contentShape(Rectangle())
                    .onTapGesture { toggleExpanded(exam.id, expanded: expanded) }
                if expanded {
                    Text(exam.mode)
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !exam.description.isEmpty {
                        Text(exam.description)
                            .font(.callout).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    // Dátum időponttal — ebből látszik, melyik nap órájára csatolódik
                    Label(exam.date.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                        .font(.caption).foregroundStyle(.secondary)
                    Button {
                        NotificationCenter.default.post(name: Notification.Name("flint.switchToTimetable"), object: nil, userInfo: ["subject": exam.subject, "deadline": exam.date.timeIntervalSince1970])
                    } label: {
                        Label("Mutatás az órarendben", systemImage: "calendar")
                            .font(.caption.weight(.semibold))
                    }
                    .tint(colors.accent)
                } else {
                    Text(exam.description.isEmpty ? exam.mode : "\(exam.mode) • \(exam.description)")
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
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
    }

    func load() async {
        guard let user = session.selectedUser, !user.isDemo else { homeworks=DemoData.homeworks(); exams=DemoData.exams(); isLoading=false; return }
        isLoading=true; let iss=user.instituteCode.isEmpty ? (JWT.instituteCode(from: user.accessToken) ?? "") : user.instituteCode
        async let hw = kreta.fetchHomework(iss: iss)
        async let ex = kreta.fetchExams(iss: iss)
        let (hwR, exR) = await (hw, ex)
        homeworks = hwR; exams = exR; isLoading=false
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
