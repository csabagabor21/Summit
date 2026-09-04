import SwiftUI

struct NotesView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var kreta: KretaClient
    @EnvironmentObject var completed: CompletedStore
    @State private var homeworks: [HomeworkItem] = []
    @State private var isLoading = true
    @State private var filter = 0
    @State private var expandedIDs: Set<String> = []
    @Environment(\.colorScheme) var scheme
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPad: Bool { hSize == .regular }
    var colors: AppColors { theme.colors(for: scheme) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("", selection: $filter) {
                        Text("Mind").tag(0); Text("Határidős").tag(1); Text("Kész").tag(2)
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
                } else if filtered.isEmpty {
                    Section {
                        ContentUnavailableView("Nincs feladat", systemImage: "checklist", description: Text("Minden kész"))
                            .frame(maxWidth: .infinity, minHeight: 220)
                            .padding(.vertical, 16)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 24, leading: 16, bottom: 24, trailing: 16))
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                } else {
                    Section {
                        ForEach(filtered, id: \.id) { hw in
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
            .animation(.spring(response: 0.36, dampingFraction: 0.84), value: filtered.isEmpty)
            .animation(.spring(response: 0.36, dampingFraction: 0.84), value: filter)
            .navigationTitle("Feladatok")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.visible, for: .navigationBar)
            .task { await load() }
            .refreshable { await load() }
        }
        .tint(colors.accent)
    }

    var filtered: [HomeworkItem] {
        let base: [HomeworkItem]
        switch filter {
        case 1: base = homeworks.filter { $0.deadline > Date() && !completed.isHomeworkDone($0.id) }.sorted { $0.deadline < $1.deadline }
        case 2: base = homeworks.filter { completed.isHomeworkDone($0.id) || $0.isDone }.sorted { $0.deadline < $1.deadline }
        default:
            // "Mind" — kipipált ne jelenjen meg (eltűnik a Feladatok tabról), Home-on marad zölden
            base = homeworks.filter { !completed.isHomeworkDone($0.id) }.sorted { $0.deadline < $1.deadline }
        }
        return base
    }
    private func toggleExpanded(_ id: String, expanded: Bool) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            if expanded { expandedIDs.remove(id) } else { expandedIDs.insert(id) }
        }
    }
    func load() async {
        guard let user = session.selectedUser, !user.isDemo else { homeworks=DemoData.homeworks(); isLoading=false; return }
        isLoading=true; let iss=user.instituteCode.isEmpty ? (JWT.instituteCode(from: user.accessToken) ?? "") : user.instituteCode
        homeworks = await kreta.fetchHomework(iss: iss); isLoading=false
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
