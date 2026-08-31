import SwiftUI

struct HomeView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var kreta: KretaClient
    @EnvironmentObject var completed: CompletedStore
    @StateObject private var vm = HomeViewModel()
    @Environment(\.colorScheme) var scheme
    var colors: AppColors { theme.colors(for: scheme) }
    // Előnézet csúszka — melyik óra van épp (demo teszteléshez)
    @AppStorage("home.demoOverride") private var demoOverride = false
    @State private var isPreviewActive = false
    @State private var previewMinutes: Double = {
        let c = Calendar.current
        let h = c.component(.hour, from: Date())
        let m = c.component(.minute, from: Date())
        return Double(max(420, min(960, h*60+m)))
    }()
    private var isDemoEffective: Bool { demoOverride || session.selectedUser?.isDemo == true }

    var body: some View {
        let user = session.selectedUser ?? .demo
        let firstName = user.name.split(separator: " ").last.map(String.init) ?? user.name

        NavigationStack {
            List {
                // Greeting
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(vm.greeting), \(firstName)!").font(.title2.weight(.bold)).foregroundStyle(.primary)
                        Text(Date.now.formatted(date: .complete, time: .omitted).capitalized).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(.hidden)
                }

                // LIVE TOP CARD — continuously shows current lesson + progress + next + rögzítve
                HomeLiveCard(lessons: vm.lessonsToday, exams: vm.exams, homeworks: vm.homeworks, overrideNow: isPreviewActive && isDemoEffective ? previewDate : nil)
                    .animation(.spring(response: 0.42, dampingFraction: 0.86), value: isDemoEffective)

                // Demo / valós toggle — fluid
                if session.selectedUser?.isDemo != true {
                    Section {
                        Toggle(isOn: $demoOverride) {
                            Label(demoOverride ? "Demo adatok" : "Valós adatok", systemImage: demoOverride ? "flask.fill" : "person.crop.rectangle.stack.fill")
                                .font(.subheadline.weight(.medium))
                        }
                        .tint(colors.accent)
                    } header: { Text("Adatok").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase) }
                    .listRowBackground(colors.surface)
                }

                // Csúszka: csak demo módban
                if isDemoEffective {
                    Section {
                        Toggle(isOn: $isPreviewActive) {
                            Label("Idő előnézet", systemImage: "slider.horizontal.3")
                                .font(.subheadline.weight(.medium))
                        }
                        .tint(colors.accent)
                        if isPreviewActive {
                            VStack(spacing: 8) {
                                Slider(value: $previewMinutes, in: 420...960, step: 5)
                                    .tint(colors.accent)
                                HStack {
                                    Text("07:00").font(.caption2).foregroundStyle(.tertiary)
                                    Spacer()
                                    Text(previewTimeText).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(colors.accent)
                                    Spacer()
                                    Text("16:00").font(.caption2).foregroundStyle(.tertiary)
                                }
                                if let l = previewLesson {
                                    Label("\(l.index). óra • \(l.subject) • \(l.room)", systemImage: "clock.fill")
                                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                } else {
                                    Text(previewStateText).font(.caption).foregroundStyle(.secondary)
                                }
                                Button("Vissza élő időre") { withAnimation { isPreviewActive = false } }
                                    .font(.caption.weight(.semibold)).tint(colors.accent)
                            }
                            .padding(.vertical, 4)
                        }
                    } header: { Text("Előnézet").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase) }
                    .listRowBackground(colors.surface)
                }

                // Legújabb jegyek — koppintva a tantárgyba visz
                Section {
                    if vm.grades.isEmpty {
                        Text("Nincs jegy").foregroundStyle(.secondary)
                    } else {
                        ForEach(vm.grades.sorted { $0.date > $1.date }.prefix(3)) { g in
                            NavigationLink {
                                let grouped = Dictionary(grouping: vm.grades, by: { $0.subject })
                                SubjectDetailView(subject: g.subject, grades: (grouped[g.subject] ?? [g]).sorted { $0.date < $1.date })
                            } label: {
                                HStack(spacing: 10) {
                                    GradeCircle(value: g.value, size: 32)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(g.subject).font(.subheadline.weight(.semibold)).lineLimit(1)
                                        if !g.topic.isEmpty {
                                            Text(g.topic).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    Text(g.date.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        NavigationLink("Összes jegy") { GradesView() }
                    }
                } header: { Text("Legújabb jegyek").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase) }

                // Közelgő dolgozatok — csak top 3 + egyetlen nyíl a láblécben
                Section {
                    let sorted = vm.exams.sorted { $0.date < $1.date }
                    if sorted.isEmpty {
                        Text("Nincs közelgő dolgozat").foregroundStyle(.secondary)
                    } else {
                        ForEach(sorted.prefix(3)) { e in
                            let done = completed.isExamDone(e.id)
                            let lesson = vm.lessonsToday.first { $0.subject == e.subject && Calendar.current.isDate($0.start, inSameDayAs: e.date) }
                                ?? vm.lessonsToday.first { $0.subject.lowercased() == e.subject.lowercased() }
                            HStack(spacing: 12) {
                                Button { withAnimation(.spring(response: 0.3)) { completed.toggleExam(e.id) } } label: {
                                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 21, weight: .regular))
                                        .foregroundStyle(done ? Color.green : .secondary)
                                        .frame(width: 22, height: 22)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(e.subject).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Text(e.description.isEmpty ? e.mode : "\(e.mode) • \(e.description)").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    HStack(spacing: 6) {
                                        Text(e.date.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(.secondary)
                                        if let l = lesson {
                                            Label("\(l.index). óra • \(l.room)", systemImage: "graduationcap.fill")
                                                .font(.caption2.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                            .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] + 16 }
                            .listRowBackground(
                                done
                                ? Color.green.opacity(scheme == .dark ? 0.10 : 0.07)
                                : colors.surface
                            )
                        }
                        if sorted.count > 3 {
                            NavigationLink { NotesView() } label: {
                                Text("Összes dolgozat (\(sorted.count))")
                            }
                        }
                    }
                } header: { Text("Közelgő dolgozatok").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase) }

                // Közelgő feladatok — csak top 3 + egyetlen nyíl a láblécben
                Section {
                    let sorted = vm.homeworks.sorted { $0.deadline < $1.deadline }
                    if sorted.isEmpty {
                        Text("Nincs feladat").foregroundStyle(.secondary)
                    } else {
                        ForEach(sorted.prefix(3)) { h in
                            let done = completed.isHomeworkDone(h.id)
                            let lesson = vm.lessonsToday.first { $0.subject == h.subject && Calendar.current.isDate($0.start, inSameDayAs: h.deadline) }
                                ?? vm.lessonsToday.first { $0.subject.lowercased() == h.subject.lowercased() }
                            HStack(spacing: 12) {
                                Button { withAnimation(.spring(response: 0.3)) { completed.toggleHomework(h.id) } } label: {
                                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 21))
                                        .foregroundStyle(done ? Color.green : .secondary)
                                        .frame(width: 22, height: 22)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(h.subject).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Text(h.title.isEmpty ? "(nincs leírás)" : h.title).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                                    HStack(spacing: 6) {
                                        Text(h.deadline.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(.secondary)
                                        if let l = lesson {
                                            Label("\(l.index). óra • \(l.room)", systemImage: "book.fill")
                                                .font(.caption2.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                            .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] + 16 }
                            .listRowBackground(
                                done
                                ? Color.green.opacity(scheme == .dark ? 0.10 : 0.07)
                                : colors.surface
                            )
                        }
                        if sorted.count > 3 {
                            NavigationLink { NotesView() } label: {
                                Text("Összes feladat (\(sorted.count))")
                            }
                        }
                    }
                } header: { Text("Közelgő feladatok").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase) }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(colors.background)
            .refreshable { await vm.refresh(kreta: kreta, user: session.selectedUser, forceDemo: demoOverride) }
            .task { await vm.refresh(kreta: kreta, user: session.selectedUser, forceDemo: demoOverride) }
            .onChange(of: demoOverride) { _, new in
                Task { withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { } ; await vm.refresh(kreta: kreta, user: session.selectedUser, forceDemo: new) }
                if !new { isPreviewActive = false }
            }
            .onChange(of: session.selectedId) { _, _ in Task { await vm.refresh(kreta: kreta, user: session.selectedUser, forceDemo: demoOverride) } }
            .navigationTitle("Főoldal")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { SettingsView() } label: { ProfileImageView(name: user.name, userId: user.id).frame(width: 30, height: 30) }
                }
            }
        }
        .tint(colors.accent)
    }

    // MARK: - Preview helpers
    private var previewDate: Date {
        let base = Calendar.current.startOfDay(for: Date())
        return base.addingTimeInterval(previewMinutes * 60)
    }
    private var previewTimeText: String { previewDate.formatted(date: .omitted, time: .shortened) }
    private var previewLesson: LessonItem? {
        vm.lessonsToday.first { $0.start <= previewDate && $0.end >= previewDate }
    }
    private var previewStateText: String {
        let calc = LiveCalc(lessons: vm.lessonsToday, now: previewDate)
        switch calc.state {
        case .morning: return "Reggel — első óra előtt"
        case .duringBreak: return "Szünet"
        case .empty: return "Nincs több óra ma"
        case .duringLesson: return "Óra közben"
        case .summary: return "Vége"
        }
    }
}

// MARK: - Live top card (native Apple, TimelineView, progress bar, next + rögzítve)
private struct HomeLiveCard: View {
    var lessons: [LessonItem]
    var exams: [ExamItem]
    var homeworks: [HomeworkItem]
    var overrideNow: Date? = nil
    @Environment(\.colorScheme) var scheme
    @EnvironmentObject var theme: ThemeStore
    var colors: AppColors { theme.colors(for: scheme) }

    var body: some View {
        Group {
            if let fixed = overrideNow {
                let calc = LiveCalc(lessons: lessons, now: fixed)
                cardContent(calc: calc)
            } else {
                // TimelineView makes progress live every 15s without Timer
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    let calc = LiveCalc(lessons: lessons, now: context.date)
                    cardContent(calc: calc)
                }
            }
        }
    }

    private func cardBackground(for lesson: LessonItem?) -> Color {
        guard let l = lesson else { return colors.surface }
        if l.isCancelled { return Color.red.opacity(scheme == .dark ? 0.22 : 0.12) }
        if l.isSubstituted { return Color.orange.opacity(scheme == .dark ? 0.22 : 0.14) }
        return colors.surface
    }

    @ViewBuilder
    private func cardContent(calc: LiveCalc) -> some View {

            // During lesson gets colored background, others default
            let bg: Color = {
                if calc.state == .duringLesson, let c = calc.current { return cardBackground(for: c) }
                if calc.state == .duringBreak, let n = calc.next { return cardBackground(for: n) }
                if calc.state == .morning, let n = calc.next { return cardBackground(for: n) }
                return colors.surface
            }()

            Section {
                switch calc.state {
                case .empty:
                    Label("Ma nincs több órád", systemImage: "moon.zzz.fill").font(.subheadline).foregroundStyle(.secondary)
                case .summary:
                    Label("Vége a tanévnek! Irány az összefoglaláshoz", systemImage: "arrow.right").font(.subheadline)
                case .morning:
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Jó reggelt!", systemImage: "sun.max.fill").font(.headline)
                        if let n = calc.next {
                            Text(n.subject)
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                if let lbl = n.substitutionLabel {
                                    Text(lbl).font(.caption2.weight(.bold)).foregroundStyle(.white).padding(.horizontal, 7).padding(.vertical, 3).background(Capsule().fill(n.isCancelled ? Color.red : Color.orange))
                                }
                                // kiemelt kis négyzet — 1. óra distinction + terem mellette
                                Text("\(n.index)")
                                    .font(.caption2.weight(.bold).monospacedDigit())
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(colors.accent))
                                    .glassEffectIfAvailable(in: RoundedRectangle(cornerRadius: 6), tint: colors.accent)
                                Text(n.room).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(.secondary)
                                Text("•").foregroundStyle(.tertiary)
                                Text(n.teacher).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                Spacer()
                                Text(n.start.formatted(date: .omitted, time: .shortened)).font(.caption.weight(.medium).monospacedDigit()).foregroundStyle(.secondary)
                            }
                            attachedInfo(for: n)
                        } else { Text("Ma nincs órád").foregroundStyle(.secondary).font(.callout) }
                    }
                case .duringLesson:
                    if let c = calc.current {
                        VStack(alignment: .leading, spacing: 10) {
                            if let lbl = c.substitutionLabel {
                                Text(lbl).font(.caption2.weight(.bold)).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(c.isCancelled ? Color.red : Color.orange))
                            }
                            Text(c.subject)
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                Text("\(c.index)")
                                    .font(.caption2.weight(.bold).monospacedDigit())
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(colors.accent))
                                    .glassEffectIfAvailable(in: RoundedRectangle(cornerRadius: 6), tint: colors.accent)
                                Text(c.room).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(.secondary)
                                Text("•").foregroundStyle(.tertiary)
                                Text(c.teacher).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                Spacer()
                                Text("\(c.start.formatted(date: .omitted, time: .shortened))–\(c.end.formatted(date: .omitted, time: .shortened))").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                            }
                            // Progress bar
                            VStack(alignment: .leading, spacing: 4) {
                                ProgressView(value: calc.progress).tint(c.isCancelled ? Color.red : c.isSubstituted ? Color.orange : colors.accent)
                                HStack {
                                    Text(calc.remainingText).font(.caption2.weight(.medium)).foregroundStyle(.secondary).monospacedDigit()
                                    Spacer()
                                    Text("\(Int(calc.progress*100))%").font(.caption2.weight(.medium)).foregroundStyle(.secondary).monospacedDigit()
                                }
                            }
                            attachedInfo(for: c)
                            if let n = calc.next {
                                Divider().opacity(0.5)
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.right.circle.fill").font(.caption).foregroundStyle(.secondary)
                                    Text("Következő: \(n.subject) • \(n.room)").font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                                    if let lbl = n.substitutionLabel {
                                        Text(lbl).font(.caption2.weight(.bold)).foregroundStyle(n.isCancelled ? Color.red : Color.orange).padding(.horizontal, 5).padding(.vertical, 2).background(Capsule().fill((n.isCancelled ? Color.red : Color.orange).opacity(0.14)))
                                    }
                                    Spacer()
                                    Text(n.start.formatted(date: .omitted, time: .shortened)).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                                }
                                attachedInfo(for: n)
                            }
                        }
                    }
                case .duringBreak:
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Szünet", systemImage: "cup.and.saucer.fill").font(.headline)
                        if let n = calc.next {
                            Text(n.subject)
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                if let lbl = n.substitutionLabel {
                                    Text(lbl).font(.caption2.weight(.bold)).foregroundStyle(.white).padding(.horizontal, 7).padding(.vertical, 3).background(Capsule().fill(n.isCancelled ? Color.red : Color.orange))
                                }
                                Text("\(n.index)")
                                    .font(.caption2.weight(.bold).monospacedDigit())
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(colors.accent))
                                    .glassEffectIfAvailable(in: RoundedRectangle(cornerRadius: 6), tint: colors.accent)
                                Text("\(n.room) • \(n.teacher)").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                Spacer()
                                Text(n.start.formatted(date: .omitted, time: .shortened)).font(.caption.weight(.medium).monospacedDigit()).foregroundStyle(.secondary)
                            }
                            attachedInfo(for: n)
                        }
                        if let c = calc.previous {
                            Text("Előző: \(c.subject)").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
            } header: { Text("Most").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase) }
            .listRowBackground(bg)
    }

    @ViewBuilder
    func attachedInfo(for lesson: LessonItem) -> some View {
        // Rögzítve van-e valami erre az órára (dolgozat/feladat azonos tárgy + közeli dátum)
        let exam = exams.first { $0.subject == lesson.subject && Calendar.current.isDate($0.date, inSameDayAs: lesson.start) }
        let hw = homeworks.first { $0.subject == lesson.subject && Calendar.current.isDate($0.deadline, inSameDayAs: lesson.start) }
        if exam != nil || hw != nil {
            VStack(alignment: .leading, spacing: 3) {
                if let e = exam {
                    Label(e.description.isEmpty ? "\(e.mode)" : "\(e.mode): \(e.description)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.orange).lineLimit(1)
                }
                if let h = hw {
                    Label(h.title.isEmpty ? "Házi feladat" : h.title, systemImage: "checklist")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.top, 2)
        }
    }
}

private struct LiveCalc {
    enum State { case empty, morning, duringLesson, duringBreak, summary }
    var state: State
    var current: LessonItem?
    var next: LessonItem?
    var previous: LessonItem?
    var progress: Double = 0
    var remainingText: String = ""

    init(lessons: [LessonItem], now: Date) {
        if lessons.isEmpty {
            let h = Calendar.current.component(.hour, from: now)
            if h < 7 { state = .morning } else if h < 15 { state = .duringLesson } else { state = .empty }
            return
        }
        if let cur = lessons.first(where: { $0.start <= now && $0.end >= now }) {
            state = .duringLesson; current = cur
            let total = cur.end.timeIntervalSince(cur.start)
            progress = total > 0 ? min(1, max(0, now.timeIntervalSince(cur.start)/total)) : 0
            let rem = Int(ceil(cur.end.timeIntervalSince(now)/60))
            remainingText = rem <= 0 ? "Vége" : "\(rem) perc van hátra"
            next = lessons.first(where: { $0.start > now })
            previous = lessons.last(where: { $0.end < now })
        } else if let nxt = lessons.first(where: { $0.start > now }) {
            let prev = lessons.last(where: { $0.end < now })
            if let p = prev, nxt.start.timeIntervalSince(p.end) > 0 {
                state = .duringBreak
            } else if now < lessons.first!.start { state = .morning } else { state = .duringBreak }
            next = nxt; previous = prev
        } else {
            state = .empty
        }
    }
}
