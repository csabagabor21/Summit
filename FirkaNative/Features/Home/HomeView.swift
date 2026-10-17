import SwiftUI

struct HomeView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var kreta: KretaClient
    @EnvironmentObject var completed: CompletedStore
    @EnvironmentObject var summitSync: SummitSync
    @StateObject private var vm = HomeViewModel()
    @Environment(\.colorScheme) var scheme
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPad: Bool { hSize == .regular }
    var colors: AppColors { theme.colors(for: scheme) }
    /// Olvasatlan KRÉTA-üzenetek — a csengő piros pöttyéhez.
    private var unreadCount: Int { vm.messages.filter { !$0.isRead }.count }
    @AppStorage("home.demoPreviewActive") private var isPreviewActive = false
    @AppStorage("home.demoPreviewMinutes") private var previewMinutes: Double = 540
    @AppStorage("liveActivity.enabled") private var liveActivityEnabled = true
    @AppStorage("developer.enabled") private var devMode = false
    @State private var exemptedTick = 0
    @State private var liveSyncTask: Task<Void, Never>?
    /// Havi Wrapped kártya (banner koppintásból, elsejéig).
    @State private var wrappedMonth: MonthlyWrapped.Month?

    var body: some View {
        let user = session.selectedUser ?? .demo
        let firstName = user.name.split(separator: " ").last.map(String.init) ?? user.name

        NavigationStack {
            List {
                // Greeting — egyetlen finom belépés képernyőnként, nem soronként
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(vm.greeting), \(firstName)!").font(.title2.weight(.bold)).foregroundStyle(.primary)
                        Text(Date.now.formatted(date: .complete, time: .omitted).capitalized).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .summitEntrance()
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(.hidden)
                }

                // Havi Wrapped banner: elsejéig az előző hónap kártyája.
                // 6-ától magától eltűnik (az archívum a Beállítások →
                // profil alól mindig elérhető).
                if let banner = MonthlyWrapped.bannerMonth(grades: vm.grades) {
                    Section {
                        Button {
                            SummitHaptics.selection()
                            wrappedMonth = banner
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(colors.accent)
                                    .frame(width: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(banner.wrappedTitle)
                                        .font(.subheadline.weight(.bold))
                                    let st = MonthlyWrapped.stats(grades: vm.grades, month: banner, exams: vm.exams, absences: vm.absences)
                                    Text("\(st.count) jegy • \(String(format: "%.1f", st.avg)) átlag")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(colors.surface)
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                        .listRowSeparator(.hidden)
                    }
                }

                // Frissítési hiba (NEM halott munkamenet — arra ott a piros sáv):
                // végre látszik, miért üres az oldal, nem hal meg némán.
                if let err = vm.error, !kreta.sessionExpired {
                    Section {
                        Label(err, systemImage: "wifi.exclamationmark")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .listRowBackground(Color.orange.opacity(scheme == .dark ? 0.12 : 0.08))
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                            .listRowSeparator(.hidden)
                    }
                }

                // Halott KRÉTA-munkamenet ("Később" után): a pillanatnyi adatok
                // maradnak, de a MOST-kártya felett piros sáv jelzi, hogy a
                // KRÉTA-munkamenet már nem létezik és nincs frissítés.
                if kreta.sessionExpired {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.subheadline.weight(.semibold))
                            Text("A KRÉTA-munkamenet már nem létezik — csak a legutóbbi mentett adatokat látod.")
                                .font(.subheadline.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 4)
                            Button("Bejelentkezés") { session.logout() }
                                .font(.subheadline.weight(.bold))
                                .buttonStyle(.plain)
                        }
                        .foregroundStyle(.red)
                        .listRowBackground(Color.red.opacity(scheme == .dark ? 0.12 : 0.08))
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                        .listRowSeparator(.hidden)
                    }
                }

                // LIVE TOP CARD — continuously shows current lesson + progress + next + rögzítve
                // Az idő-eltolás csúszka a Fejlesztői módban él (Beállítások alján
                // feloldható) — itt csak az eltolt idő szerint rajzolunk, ha aktív.
                HomeLiveCard(lessons: vm.lessonsToday, exams: vm.exams, homeworks: vm.homeworks, overrideNow: isPreviewActive && devMode ? previewDate : nil)
                    .animation(SummitMotion.gentle, value: devMode)

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
                                        if !g.plainTopic.isEmpty {
                                            Text(g.plainTopic).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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

                // iPad: két oszlop egy Section-ben — kihasználja a szélességet, nem 3 külön nyújtott sor
                if isPad {
                    let examsSorted = vm.exams.sorted { $0.date < $1.date }.prefix(3)
                    // A szám és a sorok ugyanazt mutatják, mint a Feladatok tab:
                    // csak az élő, kipipálatlan házik (a kész a Kész szegmensben van).
                    let hwVisible = vm.homeworks.filter { !completed.isHomeworkDone($0.id) }
                    let hwSorted = hwVisible.sorted { $0.deadline < $1.deadline }.prefix(3)
                    Section {
                        HStack(alignment: .top, spacing: 16) {
                            // Bal: dolgozatok
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Közelgő dolgozatok", systemImage: "pencil.and.list.clipboard").font(.caption.weight(.bold)).foregroundStyle(.secondary).textCase(.uppercase)
                                if vm.exams.isEmpty {
                                    Text("Nincs dolgozat").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(12).background(RoundedRectangle(cornerRadius: 12).fill(colors.surface))
                                } else {
                                    ForEach(Array(examsSorted), id: \.id) { e in
                                        PadExamRow(exam: e, done: completed.isExamDone(e.id), colors: colors, scheme: scheme, rolled: vm.rolledExamIDs.contains(e.id)) {
                                            SummitHaptics.taskToggled(markedDone: !completed.isExamDone(e.id))
                                            withAnimation(SummitMotion.snappy) { completed.toggleExam(e.id) }
                                        }
                                    }
                                    NavigationLink("Összes dolgozat (\(vm.exams.count))") { NotesView(initialFilter: 1) }.font(.caption.weight(.semibold)).tint(colors.accent)
                                }
                            }.frame(maxWidth: .infinity, alignment: .topLeading)
                            // Jobb: feladatok
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Közelgő feladatok", systemImage: "checklist").font(.caption.weight(.bold)).foregroundStyle(.secondary).textCase(.uppercase)
                                if vm.homeworks.isEmpty {
                                    Text("Nincs feladat").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(12).background(RoundedRectangle(cornerRadius: 12).fill(colors.surface))
                                } else {
                                    ForEach(Array(hwSorted), id: \.id) { h in
                                        PadHomeworkRow(homework: h, done: completed.isHomeworkDone(h.id), colors: colors, scheme: scheme) {
                                            if !h.isDone { SummitHaptics.taskToggled(markedDone: !completed.isHomeworkDone(h.id)) }
                                            withAnimation(SummitMotion.snappy) { completed.toggleHomework(h.id) }
                                        }
                                    }
                                    NavigationLink("Összes feladat (\(hwVisible.count))") { NotesView() }.font(.caption.weight(.semibold)).tint(colors.accent)
                                }
                            }.frame(maxWidth: .infinity, alignment: .topLeading)
                        }.padding(.vertical, 4)
                    }
                    .listRowBackground(Color.clear).listRowSeparator(.hidden).listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
                } else {
                // iPhone: külön Section-ök, de ugyanazzal a sor-komponenssel
                // (HomeAssignmentRow) — a dolgozat és a feladat kiírása
                // betűtípusra, ikonra és meta-sorra is azonos.
                Section {
                    let sorted = vm.exams.sorted { $0.date < $1.date }
                    if sorted.isEmpty {
                        Text("Nincs közelgő dolgozat").foregroundStyle(.secondary)
                    } else {
                        ForEach(sorted.prefix(3)) { e in
                            // Csak határidő-napi óra jelölhető — fallback nélkül,
                            // különben rossz nap órája/terme jelenne meg (mint a házinál)
                            let lesson = HomeworkMatcher.lesson(
                                for: HomeworkItem(id: e.id, subject: e.subject, title: "", deadline: e.date, teacher: "", isDone: false),
                                in: vm.lessonsToday
                            )
                            HomeAssignmentRow(
                                subject: e.subject,
                                detail: e.plainDescription.isEmpty ? e.mode : "\(e.mode) • \(e.plainDescription)",
                                date: e.date,
                                lesson: lesson,
                                lessonIndexFallback: e.lessonIndex,
                                done: completed.isExamDone(e.id),
                                colors: colors,
                                scheme: scheme,
                                rolled: vm.rolledExamIDs.contains(e.id),
                                onToggle: {
                                    SummitHaptics.taskToggled(markedDone: !completed.isExamDone(e.id))
                                    withAnimation(SummitMotion.snappy) { completed.toggleExam(e.id) }
                                },
                                onTap: {
                                    SummitHaptics.selection()
                                    NotificationCenter.default.post(name: Notification.Name("summit.switchToTimetable"), object: nil, userInfo: ["subject": e.subject, "deadline": e.date.timeIntervalSince1970])
                                }
                            )
                        }
                        NavigationLink { NotesView(initialFilter: 1) } label: {
                            Text("Összes dolgozat (\(sorted.count))")
                        }
                    }
                } header: { Text("Közelgő dolgozatok").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase) }

                Section {
                    // A szám és a sorok ugyanazt mutatják, mint a Feladatok tab:
                    // csak az élő, kipipálatlan házik (a kész a Kész szegmensben van).
                    let sorted = vm.homeworks.filter { !completed.isHomeworkDone($0.id) }.sorted { $0.deadline < $1.deadline }
                    if sorted.isEmpty {
                        Text("Nincs feladat").foregroundStyle(.secondary)
                    } else {
                        ForEach(sorted.prefix(3)) { h in
                            // Csak határidő-napi óra jelölhető — fallback nélkül,
                            // különben rossz nap órája/terme jelenne meg (HomeworkMatcher)
                            let lesson = HomeworkMatcher.lesson(for: h, in: vm.lessonsToday)
                            HomeAssignmentRow(
                                subject: h.subject,
                                detail: h.plainTitle.isEmpty ? "(nincs leírás)" : h.plainTitle,
                                date: h.deadline,
                                lesson: lesson,
                                lessonIndexFallback: nil,
                                done: completed.isHomeworkDone(h.id),
                                colors: colors,
                                scheme: scheme,
                                onToggle: {
                                    if !h.isDone { SummitHaptics.taskToggled(markedDone: !completed.isHomeworkDone(h.id)) }
                                    withAnimation(SummitMotion.snappy) { completed.toggleHomework(h.id) }
                                },
                                onTap: {
                                    SummitHaptics.selection()
                                    NotificationCenter.default.post(name: Notification.Name("summit.switchToTimetable"), object: nil, userInfo: ["subject": h.subject, "deadline": h.deadline.timeIntervalSince1970])
                                }
                            )
                        }
                        NavigationLink { NotesView() } label: {
                            Text("Összes feladat (\(sorted.count))")
                        }
                    }
                } header: { Text("Közelgő feladatok").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase) }
                }
            }
            .listStyle(.insetGrouped)
            // iPad: keskenyebb, középre igazított lista — nem nyúlik szét 12.9"-en
            .frame(maxWidth: isPad ? MacSupport.contentWidth(ipad: 1000, mac: 1150) : .infinity)
            .padding(.horizontal, MacSupport.sidePadding)
            .frame(maxWidth: .infinity)
            .summitListChrome(colors: colors)
            .refreshable {
                // A főoldali lehúzás a SummitSyncet is oda-vissza
                // szinkronizálja (függő feltöltés + lehúzás) — különben
                // a KRÉTA-adat friss, de a másik eszköz/Mac sora marad,
                // és az egész „seamful" (széteső) érzetű.
                await vm.refresh(kreta: kreta, user: session.selectedUser, completed: completed, force: true)
                await summitSync.flushThenPull()
                SummitHaptics.light()
            }
            .task {
                // első indításkor a previewMinutes legyen a mostani idő (ne fix 09:00)
                if UserDefaults.standard.object(forKey: "home.demoPreviewMinutes") == nil {
                    let c = Calendar.current
                    let h = c.component(.hour, from: Date())
                    let m = c.component(.minute, from: Date())
                    previewMinutes = Double(max(420, min(960, h*60+m)))
                }
                await vm.refresh(kreta: kreta, user: session.selectedUser, completed: completed)
                await syncLiveActivity()
            }
            // Percenkénti élő sync: az activity különben beragad (óraváltáskor
            // semmi nem triggerelte az update-et), a percek és a progress pontatlanok.
            // Háttérben az iOS úgyis felfüggeszt — ez csak előtérben pörög.
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 60_000_000_000)
                    guard !Task.isCancelled else { break }
                    await syncLiveActivity()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                // Olvasottnak vesszük: jelvény nullázása (a frissítés úgyis diffel)
                if let uid = session.selectedUser?.id { NotificationManager.shared.clearBadge(userId: uid) }
                Task { await syncLiveActivity() }
            }
            .onReceive(NotificationCenter.default.publisher(for: ExemptedStore.changedNotification)) { _ in exemptedTick += 1 }
            // Felmentés-váltáskor a Live Activity is azonnal újraszámol
            // (a lessonsToday-tömb ilyenkor nem változik, így az onChange
            // nem tüzelne — csak a percenkénti sync futna le).
            .onChange(of: exemptedTick) { _, _ in Task { await syncLiveActivity() } }
            // Dolgozat-pótlás kapcsoló/elvetés — hálózat nélkül újraszámol.
            .onReceive(NotificationCenter.default.publisher(for: ExamRollover.changedNotification)) { _ in vm.applyRollover() }
            // Havi Wrapped kártya (banner koppintásból).
            .fullScreenCover(item: $wrappedMonth) { m in
                MonthlyWrappedCard(
                    month: m,
                    stats: MonthlyWrapped.stats(grades: vm.grades, month: m, exams: vm.exams, absences: vm.absences),
                    onClose: { wrappedMonth = nil },
                    userId: session.selectedUser?.id ?? "",
                    studentName: session.selectedUser?.name ?? ""
                )
                .environmentObject(theme)
            }
            // Üzenet megnyitva → a csengő-jelvény azonnal csökken (frissítés nélkül is).
            .onChange(of: kreta.readMessageIDs) { _, ids in
                vm.messages = vm.messages.map { ids.contains($0.id) ? $0.withRead() : $0 }
            }
            .onChange(of: vm.lessonsToday) { _, _ in Task { await syncLiveActivity() } }
            .onChange(of: session.selectedId) { _, _ in Task { await vm.refresh(kreta: kreta, user: session.selectedUser, completed: completed); await syncLiveActivity() } }
            .onChange(of: previewMinutes) { _, _ in
                if devMode && isPreviewActive { enqueueLiveSync() }
            }
            .onChange(of: isPreviewActive) { _, _ in
                enqueueLiveSync()
            }
            // A didChangeNotification MINDEN UserDefaults-írásra tüzelt (a csúszka is oda ír!),
            // így tickenként 2 párhuzamos sync futott → endAll/request verseny → stackelt activityk.
            // Helyette csak a Live Activity toggle-t figyeljük, debounce-olt single-flight sync-kel.
            .onChange(of: liveActivityEnabled) { _, _ in
                Task { await syncLiveActivity() }
            }
            .navigationTitle("Főoldal")
            .navigationBarTitleDisplayMode(.large)
            .summitToolbarBackground()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 18) {
                        // Értesítések (KRÉTA-postaláda) — a 6. tab helyett itt,
                        // hogy ne legyen rendszer-More tab a TabBaron.
                        NavigationLink { MessagesView() } label: {
                            Image(systemName: "bell.fill")
                                .font(.body)
                                .foregroundStyle(colors.accent)
                                .overlay(alignment: .topTrailing) {
                                    if unreadCount > 0 {
                                        Circle().fill(Color.red).frame(width: 9, height: 9)
                                            .offset(x: 5, y: -5)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        NavigationLink { SettingsView() } label: { ProfileImageView(name: user.name, userId: ProfileImageStore.key(userId: user.id, accessToken: user.accessToken), size: 30) }
                            .buttonStyle(.plain) // különben a rendszer glass-pilleket tesz a kör mögé
                    }
                }
            }
        }
        .tint(colors.accent)
    }

    // MARK: - Preview helpers (a csúszka a Fejlesztői módban él)
    private var previewDate: Date {
        let base = Calendar.current.startOfDay(for: Date())
        return base.addingTimeInterval(previewMinutes * 60)
    }

    /// Debounce-olt single-flight sync: csúszkahúzáskor tickenként csak az utolsó fut le,
    /// különben az endAll/request párok párhuzamosan versenyeznek és stackelődnek (több aktív).
    private func enqueueLiveSync() {
        liveSyncTask?.cancel()
        liveSyncTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await syncLiveActivity()
        }
    }

    @MainActor
    private func syncLiveActivity() async {
        // Fejlesztői módban az idő-csúszka mozgatja a Live Activity-t is,
        // hogy a Lock Screen / Dynamic Island tesztelhető legyen készüléken.
        if isPreviewActive && devMode {
            let previewNow = previewDate
            let realNow = Date()
            let delta = previewNow.timeIntervalSince(realNow)
            func shifted(_ l: LessonItem) -> LessonItem {
                LessonItem(
                    id: l.id, subject: l.subject, room: l.room,
                    start: l.start.addingTimeInterval(-delta),
                    end: l.end.addingTimeInterval(-delta),
                    teacher: l.teacher, index: l.index,
                    isSubstituted: l.isSubstituted, isCancelled: l.isCancelled,
                    originalTeacher: l.originalTeacher
                )
            }
            // `now` = valós idő, az órák shiftelve — így a rendszer
            // Text(timerInterval:) visszaszámlálója a valós órához igazodik,
            // de a preview időnek megfelelő állapotot mutatja.
            let shiftedAll = vm.lessonsToday.map(shifted)
            // Eltolt mű-idő: a cache-be nem írhat (cacheable: false),
            // különben a háttér-ébresztés valós határoknál ezt mutatná.
            await SummitLiveActivityManager.shared.syncDay(lessons: shiftedAll, now: realNow, accentHex: theme.accentHex, cacheable: false)
            // Push-teszt preview-ban is: külön `:preview` kulcsra megy,
            // a valós tervet nem szennyezi (SummitPushSync).
            await SummitLiveActivityManager.shared.pushPreviewPlan(lessons: shiftedAll, now: realNow, userId: session.selectedUser?.id ?? "")
            return
        }
        await SummitLiveActivityManager.shared.syncDay(lessons: vm.lessonsToday, accentHex: theme.accentHex)
    }
}

// iPad kétoszlopos sorok külön nézetenként — az egybeírt óriás-kifejezést
// a lassabb toolchain-ek nem tudták típusellenőrizni (150:41 hiba)
private struct PadExamRow: View {
    var exam: ExamItem
    var done: Bool
    var colors: AppColors
    var scheme: ColorScheme
    var rolled: Bool = false
    var onToggle: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20)).foregroundStyle(done ? Color.green : .secondary)
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(exam.subject).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(exam.plainDescription.isEmpty ? exam.mode : "\(exam.mode) • \(exam.plainDescription)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(examLessonLine(exam)).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            SummitHaptics.selection()
            NotificationCenter.default.post(name: Notification.Name("summit.switchToTimetable"), object: nil, userInfo: ["subject": exam.subject, "deadline": exam.date.timeIntervalSince1970])
        }
        .padding(10).background(cardBackground)
    }
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(done ? Color.green.opacity(scheme == .dark ? 0.10 : 0.07) : rolled ? Color.red.opacity(scheme == .dark ? 0.16 : 0.10) : colors.surface)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
    }
}

private func examLessonLine(_ exam: ExamItem) -> String {
    let d = exam.date.formatted(date: .abbreviated, time: .omitted)
    if let n = exam.lessonIndex { return "\(d) (\(n). óra)" }
    return d
}

private struct PadHomeworkRow: View {
    var homework: HomeworkItem
    var done: Bool
    var colors: AppColors
    var scheme: ColorScheme
    var onToggle: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20)).foregroundStyle(done ? Color.green : .secondary)
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(homework.subject).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(homework.plainTitle.isEmpty ? "(nincs leírás)" : homework.plainTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(homework.deadline.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            SummitHaptics.selection()
            NotificationCenter.default.post(name: Notification.Name("summit.switchToTimetable"), object: nil, userInfo: ["subject": homework.subject, "deadline": homework.deadline.timeIntervalSince1970])
        }
        .padding(10).background(cardBackground)
    }
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(done ? Color.green.opacity(scheme == .dark ? 0.10 : 0.07) : colors.surface)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
    }
}

// MARK: - Közös dolgozat/feladat sor (iPhone) — a két főoldali Section
// ugyanazt a tipót, ikont és meta-sort kapja, hogy a kiírás egységes legyen.
private struct HomeAssignmentRow: View {
    var subject: String
    var detail: String
    var date: Date
    var lesson: LessonItem?
    var lessonIndexFallback: Int?
    var done: Bool
    var colors: AppColors
    var scheme: ColorScheme
    var rolled: Bool = false
    var onToggle: () -> Void
    var onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(done ? Color.green : .secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 3) {
                Text(subject).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(detail).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 6) {
                    Text(date.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(.secondary)
                    if let l = lesson {
                        Label("\(l.index). óra • \(l.room)", systemImage: "clock.fill")
                            .font(.caption2.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                    } else if let n = lessonIndexFallback {
                        Text("(\(n). óra)").font(.caption2).foregroundStyle(.secondary)
                    }
                    if rolled {
                        Text("Pótló").font(.caption2.weight(.bold)).foregroundStyle(.red)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.red.opacity(0.12)))
                    }
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
        .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] + 16 }
        // Pótló dolgozat piros háttere (mint a kipipált zöld, csak piros)
        .listRowBackground(
            done
            ? Color.green.opacity(scheme == .dark ? 0.10 : 0.07)
            : rolled ? Color.red.opacity(scheme == .dark ? 0.16 : 0.10)
            : colors.surface
        )
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
        Section {
            Group {
                if let fixed = overrideNow {
                    let calc = LiveCalc(lessons: lessons, now: fixed)
                    innerContent(calc: calc)
                        .listRowBackground(bg(for: calc))
                } else {
                    // TimelineView makes progress live every 15s without Timer
                    // Header kívül — TimelineView csak a row tartalmát frissíti, nem a Section-t.
                    TimelineView(.periodic(from: .now, by: 15)) { context in
                        let calc = LiveCalc(lessons: lessons, now: context.date)
                        innerContent(calc: calc)
                            .listRowBackground(bg(for: calc))
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            .listRowSeparator(.hidden)
        } header: {
            Text("MOST")
                .font(.caption2.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
    }

    private func bg(for calc: LiveCalc) -> Color {
        if calc.state == .duringLesson, let c = calc.current { return cardBackground(for: c) }
        if calc.state == .duringBreak, let n = calc.next { return cardBackground(for: n) }
        if calc.state == .morning, let n = calc.next { return cardBackground(for: n) }
        return colors.surface
    }

    private func cardBackground(for lesson: LessonItem?) -> Color {
        guard let l = lesson else { return colors.surface }
        if ExemptedStore.isExempted(l.subject) { return Color.green.opacity(scheme == .dark ? 0.22 : 0.12) }
        if l.isCancelled { return Color.red.opacity(scheme == .dark ? 0.22 : 0.12) }
        if l.isSubstituted { return Color.orange.opacity(scheme == .dark ? 0.22 : 0.14) }
        return colors.surface
    }
    private func exemptLabel(for lesson: LessonItem) -> String? {
        if ExemptedStore.isExempted(lesson.subject) { return "Felmentett" }
        return lesson.substitutionLabel
    }
    private func exemptTint(for lesson: LessonItem) -> Color? {
        if ExemptedStore.isExempted(lesson.subject) { return Color.green }
        if lesson.isCancelled { return Color.red }
        if lesson.isSubstituted { return Color.orange }
        return nil
    }

    @ViewBuilder
    private func innerContent(calc: LiveCalc) -> some View {
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
                                .minimumScaleFactor(0.65)
                                .truncationMode(.tail)
                            HStack(spacing: 6) {
                                if let lbl = exemptLabel(for: n) {
                                    Text(lbl).font(.caption2.weight(.bold)).foregroundStyle(.white).padding(.horizontal, 7).padding(.vertical, 3).background(Capsule().fill(exemptTint(for: n) ?? Color.green))
                                }
                                Text(n.room)
                                    .font(.caption2.weight(.bold).monospacedDigit())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 7).padding(.vertical, 4)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(colors.accent))
                                    .glassEffectIfAvailable(in: RoundedRectangle(cornerRadius: 6), tint: colors.accent)
                                    .lineLimit(1)
                                Text("\(n.index). óra").font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(.secondary)
                                Text("•").foregroundStyle(.tertiary)
                                Text(n.teacher).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                Spacer()
                                Text(n.start.formatted(date: .omitted, time: .shortened)).font(.caption.weight(.medium).monospacedDigit()).foregroundStyle(.secondary)
                            }
                            if calc.progress > 0 {
                                HomeLiquidProgress(progress: calc.progress, tint: n.isCancelled ? Color.red : n.isSubstituted ? Color.orange : colors.accent, remainingText: calc.remainingText, scheme: scheme, colors: colors)
                                    .padding(.top, 2)
                            }
                            attachedInfo(for: n)
                        } else { Text("Ma nincs órád").foregroundStyle(.secondary).font(.callout) }
                    }
                case .duringLesson:
                    if let c = calc.current {
                        VStack(alignment: .leading, spacing: 10) {
                            if let lbl = exemptLabel(for: c) {
                                Text(lbl).font(.caption2.weight(.bold)).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(exemptTint(for: c) ?? Color.green))
                            }
                            Text(c.subject)
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .truncationMode(.tail)
                            HStack(spacing: 6) {
                                Text(c.room)
                                    .font(.caption2.weight(.bold).monospacedDigit())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 7).padding(.vertical, 4)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(colors.accent))
                                    .glassEffectIfAvailable(in: RoundedRectangle(cornerRadius: 6), tint: colors.accent)
                                    .lineLimit(1)
                                Text("\(c.index). óra").font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(.secondary)
                                Text("•").foregroundStyle(.tertiary)
                                Text(c.teacher).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                Spacer()
                                Text("\(c.start.formatted(date: .omitted, time: .shortened))–\(c.end.formatted(date: .omitted, time: .shortened))").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                            }
                            HomeLiquidProgress(progress: calc.progress, tint: exemptTint(for: c) ?? colors.accent, remainingText: calc.remainingText, scheme: scheme, colors: colors)
                            attachedInfo(for: c)
                            if let n = calc.next {
                                Divider().opacity(0.5)
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.right.circle.fill").font(.caption).foregroundStyle(.secondary)
                                    Text("Következő: \(n.subject) • \(n.room)").font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                                    if let lbl = exemptLabel(for: n) {
                                        Text(lbl).font(.caption2.weight(.bold)).foregroundStyle(exemptTint(for: n) ?? Color.green).padding(.horizontal, 5).padding(.vertical, 2).background(Capsule().fill((exemptTint(for: n) ?? Color.green).opacity(0.14)))
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
                                .minimumScaleFactor(0.65)
                                .truncationMode(.tail)
                            HStack(spacing: 6) {
                                if let lbl = exemptLabel(for: n) {
                                    Text(lbl).font(.caption2.weight(.bold)).foregroundStyle(.white).padding(.horizontal, 7).padding(.vertical, 3).background(Capsule().fill(exemptTint(for: n) ?? Color.green))
                                }
                                Text(n.room)
                                    .font(.caption2.weight(.bold).monospacedDigit())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 7).padding(.vertical, 4)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(colors.accent))
                                    .glassEffectIfAvailable(in: RoundedRectangle(cornerRadius: 6), tint: colors.accent)
                                    .lineLimit(1)
                                Text("\(n.index). óra • \(n.teacher)").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                Spacer()
                                Text(n.start.formatted(date: .omitted, time: .shortened)).font(.caption.weight(.medium).monospacedDigit()).foregroundStyle(.secondary)
                            }
                            if calc.progress > 0 {
                                HomeLiquidProgress(progress: calc.progress, tint: exemptTint(for: n) ?? colors.accent, remainingText: calc.remainingText, scheme: scheme, colors: colors)
                                    .padding(.top, 2)
                            }
                            attachedInfo(for: n)
                        }
                        if let c = calc.previous {
                            Text("Előző: \(c.subject)").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
    }

    @ViewBuilder
    func attachedInfo(for lesson: LessonItem) -> some View {
        // Rögzítve van-e valami erre az órára — kanonikus egyeztetés (Matek <-> Matematika).
        // Óraszámos dolgozat csak a saját órájára kerül; óraszám nélkül
        // naponta csak egy órára (ExamMatcher + aznapi órák).
        let exam = ExamMatcher.exam(for: lesson, in: exams, allLessons: lessons)
        let hw = homeworks.first { SubjectMatcher.same($0.subject, lesson.subject) && Calendar.current.isDate($0.deadline, inSameDayAs: lesson.start) }
        if exam != nil || hw != nil {
            VStack(alignment: .leading, spacing: 3) {
                if let e = exam {
                    let desc = e.plainDescription
                    Label(desc.isEmpty ? "\(e.mode)" : "\(e.mode): \(desc)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.orange).lineLimit(1)
                }
                if let h = hw {
                    Label(h.plainTitle.isEmpty ? "Házi feladat" : h.plainTitle, systemImage: "checklist")
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

    // Csak az adott nap órái — holnap órája ne szivárogjon be (600 perc hiba).
    // A záró felmentett órák nem részei a napnak (mint a Live Activity-ben):
    // utánuk "Ma nincs több órád" jön, nem szünet egy felmentett órára.
    private static func todayLessons(_ lessons: [LessonItem], now: Date) -> [LessonItem] {
        let cal = Calendar.current
        let day = lessons.filter { cal.isDate($0.start, inSameDayAs: now) || cal.isDate($0.end, inSameDayAs: now) }
            .filter { !$0.subject.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.start < $1.start }
        return ExemptedStore.trimmingTrailingExempted(day)
    }

    private static func formatRemaining(_ minutes: Int, past: Bool = false) -> String {
        if minutes <= 0 { return past ? "Vége" : "Kezdődik" }
        return past ? "\(minutes) perc van hátra" : "\(minutes) perc múlva kezdődik"
    }

    init(lessons: [LessonItem], now: Date) {
        let filtered = Self.todayLessons(lessons, now: now)
        if filtered.isEmpty {
            // Refilc: ha nincs mai óra, ne mutass 600 percet — üres
            state = .empty
            return
        }
        let sorted = filtered
        if let cur = sorted.first(where: { $0.start <= now && $0.end >= now }) {
            state = .duringLesson; current = cur
            let total = cur.end.timeIntervalSince(cur.start)
            progress = total > 0 ? min(1, max(0, now.timeIntervalSince(cur.start)/total)) : 0
            let rem = Int(ceil(cur.end.timeIntervalSince(now)/60))
            remainingText = Self.formatRemaining(rem, past: true)
            next = sorted.first(where: { $0.start > now })
            previous = sorted.last(where: { $0.end < now })
        } else if let nxt = sorted.first(where: { $0.start > now }) {
            let prev = sorted.last(where: { $0.end < now })
            if let p = prev, nxt.start.timeIntervalSince(p.end) > 0 {
                state = .duringBreak
                let total = nxt.start.timeIntervalSince(p.end)
                progress = total > 0 ? min(1, max(0, now.timeIntervalSince(p.end)/total)) : 0
                let rem = Int(ceil(nxt.start.timeIntervalSince(now)/60))
                // Refilc: szünet max 30-40 perc — ha ennél nagyobb, valószínű hibás adat, cap 60-ra ne mutasson 600-at
                remainingText = Self.formatRemaining(min(rem, 999), past: false)
            } else if now < sorted.first!.start {
                state = .morning
                let first = sorted.first!
                let cal = Calendar.current
                let morningStart = cal.date(bySettingHour: 7, minute: 0, second: 0, of: now) ?? now
                let total = first.start.timeIntervalSince(morningStart)
                if total > 0, now >= morningStart {
                    progress = min(1, max(0, now.timeIntervalSince(morningStart)/total))
                }
                let rem = Int(ceil(first.start.timeIntervalSince(now)/60))
                // Refilc: reggel max 3 óra (7→10) — 600 perc soha nem jelenik meg, ha mégis akkor holnap órája szivárgott be
                if rem > 180 {
                    state = .empty
                    remainingText = ""
                } else {
                    remainingText = Self.formatRemaining(rem, past: false)
                }
            } else {
                state = .duringBreak
                if let p = prev {
                    let total = nxt.start.timeIntervalSince(p.end)
                    progress = total > 0 ? min(1, max(0, now.timeIntervalSince(p.end)/total)) : 0
                    let rem = Int(ceil(nxt.start.timeIntervalSince(now)/60))
                    remainingText = Self.formatRemaining(rem, past: false)
                }
            }
            next = nxt; previous = prev
        } else {
            state = .empty
        }
    }
}

// MARK: - Home progress — a 15 mp-es Timeline-lépések közti ugrást
// lineárisan simítja, így az óra-csík folyamatosan kúszik, nem pattog.
private struct HomeLiquidProgress: View {
    let progress: Double
    let tint: Color
    let remainingText: String
    let scheme: ColorScheme
    let colors: AppColors
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: progress).tint(tint)
                .animation(SummitMotion.progress, value: progress)
            Text(remainingText).font(.caption2.weight(.medium)).foregroundStyle(.secondary).monospacedDigit().contentTransition(.numericText())
        }
    }
}


