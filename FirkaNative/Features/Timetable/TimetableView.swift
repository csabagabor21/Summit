import SwiftUI

struct TimetableView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var kreta: KretaClient
    @State private var lessons: [LessonItem] = []
    @State private var selectedDay: Int = Calendar.current.component(.weekday, from: Date())
    @State private var isLoading = true
    @Environment(\.colorScheme) var scheme
    var colors: AppColors { theme.colors(for: scheme) }
    let days = ["Hétfő","Kedd","Szerda","Csütörtök","Péntek"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Nap", selection: $selectedDay) {
                    ForEach(2...6, id: \.self) { d in Text(days[d-2]).tag(d) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(.ultraThinMaterial)

                List {
                    if isLoading {
                        ForEach(0..<4, id: \.self) { _ in Text("").redacted(reason: .placeholder) }
                    } else if filtered.isEmpty {
                        ContentUnavailableView("Nincs óra", systemImage: "calendar.badge.exclamationmark", description: Text("Pihenőnap"))
                    } else {
                        ForEach(filtered) { l in
                            let cur = isCurrent(l)
                            let bg: Color = {
                                if l.isCancelled { return Color.red.opacity(scheme == .dark ? 0.22 : 0.12) }
                                if l.isSubstituted { return Color.orange.opacity(scheme == .dark ? 0.22 : 0.14) }
                                return Color.clear
                            }()
                            HStack(spacing: 12) {
                                VStack(spacing: 2) {
                                    Text(l.index).font(.caption2.weight(.medium).monospacedDigit()).frame(width: 24, height: 24).background(cur ? colors.accent : Color.primary.opacity(0.06), in: Circle()).foregroundStyle(cur ? .white : .secondary)
                                    Text(l.room).font(.caption2.weight(.semibold).monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .frame(width: 36)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(l.subject).font(.subheadline.weight(.semibold)).lineLimit(1)
                                        if let lbl = l.substitutionLabel {
                                            Text(lbl).font(.caption2.weight(.bold)).foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(l.isCancelled ? Color.red : Color.orange))
                                        }
                                    }
                                    Text(l.teacher).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    Text("\(l.index). óra • \(l.room)").font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                                    if cur { ProgressView(value: progress(for: l)).tint(l.isCancelled ? Color.red : l.isSubstituted ? Color.orange : colors.accent) }
                                }
                                Spacer()
                                Text(l.start.formatted(date: .omitted, time: .shortened)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            .listRowBackground(bg == Color.clear ? colors.surface : bg)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .refreshable { await load() }
            }
            .background(colors.background)
            .navigationTitle("Órarend")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") } } }
            .task { await load() }
        }
        .tint(colors.accent)
    }

    var filtered: [LessonItem] {
        guard !lessons.isEmpty else { return [] }
        let byDay = lessons.filter { Calendar.current.component(.weekday, from: $0.start) == selectedDay }.sorted { $0.start < $1.start }
        if !byDay.isEmpty { return byDay }
        return lessons.enumerated().filter { $0.offset % 5 == (selectedDay-2+7)%5 }.map { $0.element }
    }
    func isCurrent(_ l: LessonItem) -> Bool { let n=Date(); return l.start<=n && l.end>=n }
    func progress(for l: LessonItem) -> Double { let t=l.end.timeIntervalSince(l.start); return t>0 ? min(1,max(0,Date().timeIntervalSince(l.start)/t)) : 0 }

    func load() async {
        guard let user = session.selectedUser, !user.isDemo else {
            lessons = (0..<8).map { i in let h=8+i%5; return LessonItem(id:"m\(i)", subject:["Matek","Irodalom","Töri","Angol","Bio","Fizika","Kémia","Tesi"][i%8], room:"\(100+i)", start: Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date())!, end: Calendar.current.date(bySettingHour: h, minute: 45, second: 0, of: Date())!, teacher:"Tanár \(i)", index:"\(i+1)") }
            isLoading=false; return
        }
        isLoading=true
        let iss = user.instituteCode.isEmpty ? (JWT.instituteCode(from: user.accessToken) ?? "") : user.instituteCode
        let start = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let end = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
        lessons = await kreta.fetchTimetable(iss: iss, from: start, to: end)
        isLoading=false
        var d = Calendar.current.component(.weekday, from: Date()); if d==1||d==7 { d=2 }; selectedDay=d
    }
}
