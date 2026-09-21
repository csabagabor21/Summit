import SwiftUI
import UniformTypeIdentifiers

/// Iskolai események (tannaptár) — egyszeri bevitel a Beállításokban.
/// Három iPhone-barát út (fájl, link, beillesztett szöveg), mind ugyanabba
/// a store-ba ír: a tisztított események a SummitSync-kel minden eszközre
/// átmennek (újra bevinni sehol nem kell).
struct SchoolEventsSection: View {
    @EnvironmentObject var summitSync: SummitSync
    @EnvironmentObject var session: SessionStore
    @Environment(\.colorScheme) var scheme
    @AppStorage(SchoolEventsStore.showKey) private var showInTimetable = true
    @State private var events: [SchoolEvent] = SchoolEventsStore.load()
    @State private var source: String? = SchoolEventsStore.sourceName()
    @State private var importing = false
    @State private var message = ""
    @State private var linkText = ""
    @State private var savedLink: String? = SchoolEventsStore.savedURL()
    @State private var downloading = false
    @State private var showPaste = false
    @State private var pastedText = ""
    @State private var adminEntry: SchoolCalendarDirectory.Entry?
    @State private var adminChecked = false
    @State private var adminBusy = false

    private var icsTypes: [UTType] {
        if let ics = UTType(filenameExtension: "ics") { return [ics, .plainText] }
        return [.plainText]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { showInTimetable },
                set: { new in
                    showInTimetable = new
                    // Explicit jelölés: a store-értesítés csak a blobot
                    // (`schoolEvents`) tolná fel feleslegesen is.
                    summitSync.markDirty(.schoolEventsShow)
                }
            )) {
                Label("Mutatás az órarendben", systemImage: "calendar.badge.clock")
                    .font(.subheadline.weight(.medium))
            }

            if events.isEmpty {
                Text("Még nincs tannaptár — linkből, szövegből vagy .ics fájlból.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(summaryText).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 0) Iskolai alapértelmezés (admin adatbázis): ha az iskola
            // megadta a központi naptárat, egy gombnyomás — a kézi
            // beállítás alább bármikor felülírhatja (az is szinkronizálódik).
            if let admin = adminEntry {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Iskolai alapértelmezés").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    HStack {
                        Text(admin.name ?? "Központi naptár")
                            .font(.subheadline.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button(adminBusy || downloading ? "…" : (savedLink == admin.calendarURL ? "Frissítés" : "Betöltés")) {
                            Task { await downloadAdmin() }
                        }
                        .font(.caption.weight(.bold))
                        .disabled(adminBusy || downloading)
                    }
                    if savedLink == admin.calendarURL {
                        Text("Ezt használod.")
                            .font(.caption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if !events.isEmpty {
                        Text("Saját beállításod van — az marad.")
                            .font(.caption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            // 1) Link: a suli naptárjának webcíme (suli honlap, Google Naptár
            // nyilvános ICS-linkje) — letölteni nem kell, az app lehúzza.
            VStack(alignment: .leading, spacing: 6) {
                Text("Linkből").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                HStack {
                    TextField("Naptár-link beillesztése", text: $linkText)
                        .font(.subheadline)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .summitInput()
                        .disabled(downloading)
                    Button(downloading ? "…" : "Letöltés") {
                        Task { await download(linkText) }
                    }
                    .font(.caption.weight(.bold))
                    .disabled(downloading || linkText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if savedLink != nil {
                    Button("Frissítés a mentett linkről") {
                        Task { await download(savedLink ?? "") }
                    }
                    .font(.caption.weight(.bold))
                    .disabled(downloading)
                }
            }

            // 2) Szöveg: kimásolt lista beillesztése (Safari, Mail, KRÉTA-üzenet).
            VStack(alignment: .leading, spacing: 6) {
                Text("Szövegből").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if showPaste {
                    TextEditor(text: $pastedText)
                        .font(.subheadline)
                        .frame(minHeight: 110, maxHeight: 200)
                        .padding(6)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.22)))
                    Text("Soronként: dátum + cím. Nyers ICS is mehet.")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 16) {
                        Button("Feldolgozás") { importText() }
                            .font(.caption.weight(.bold))
                            .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Bezárás") { showPaste = false }
                            .font(.caption.weight(.bold))
                    }
                } else {
                    Button("Szöveg beillesztése") { showPaste = true }
                        .font(.caption.weight(.bold))
                }
            }

            // 3) Fájl (.ics) — akinek az jön be (pl. AI-jal generáltatta).
            HStack(spacing: 16) {
                Button(importing ? "Importálás…" : (events.isEmpty ? "Fájlból (.ics)" : "Új fájl (.ics)")) {
                    importing = true
                }
                .font(.caption.weight(.bold))
                .disabled(importing)
                if !events.isEmpty {
                    Button("Törlés", role: .destructive) {
                        // A törlés is terjed: a store-értesítés dirty-zi a
                        // `schoolEvents` mezőt, a `"[]"` felmegy a szerverre.
                        SchoolEventsStore.removeAll()
                        SchoolEventsStore.saveURL(nil)
                        refresh()
                        message = "Törölve — a törlés is szinkronizálódik."
                    }
                    .font(.caption.weight(.bold))
                    .disabled(importing)
                }
            }

            if !message.isEmpty {
                Text(message).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: icsTypes, allowsMultipleSelection: false) { result in
            importing = false
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                importICS(from: url)
            case .failure:
                message = "Nem sikerült beolvasni a fájlt."
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: SchoolEventsStore.changedNotification)) { _ in
            refresh()
        }
        .onAppear {
            refresh()
            checkAdmin()
        }
    }

    /// Admin-bejegyzés az aktuális iskola kódjához (csak olvasás, nincs
    /// letöltés — a gomb / a belépéskori automatika tölt le).
    private func checkAdmin() {
        guard let code = session.selectedUser?.instituteCode,
              SchoolCalendarDirectory.key(forInstituteCode: code) != nil else {
            adminChecked = true
            return
        }
        Task {
            adminEntry = await SchoolCalendarDirectory.fetchEntry(instituteCode: code)
            adminChecked = true
        }
    }

    /// Iskolai alapértelmezés letöltése — ugyanaz az út, mint a kézi link:
    /// mentés után a SummitSync viszi a többi eszközre.
    private func downloadAdmin() async {
        guard let entry = adminEntry else { return }
        adminBusy = true
        defer { adminBusy = false }
        await download(entry.calendarURL)
    }

    private var summaryText: String {
        var parts = ["\(events.count) esemény"]
        if let s = source { parts.append("· \(s)") }
        else { parts.append("· szinkronból") }
        let days = events.map(\.day).sorted()
        if let first = days.first, let last = days.last, first != last {
            parts.append("· \(huDate(first)) – \(huDate(last))")
        } else if let first = days.first {
            parts.append("· \(huDate(first))")
        }
        return parts.joined(separator: " ")
    }

    private func huDate(_ iso: String) -> String {
        let p = iso.split(separator: "-")
        guard p.count == 3 else { return iso }
        return "\(p[0]). \(p[1]). \(p[2])."
    }

    private func refresh() {
        events = SchoolEventsStore.load()
        source = SchoolEventsStore.sourceName()
        savedLink = SchoolEventsStore.savedURL()
        if linkText.isEmpty { linkText = savedLink ?? "" }
    }

    /// Linkről lehúzott naptár — Google-megosztólinkből (`?cid=`) és
    /// `webcal://`-ból is közvetlen ICS-címet csinál, letölteni nem kell.
    private func download(_ raw: String) async {
        guard let url = SchoolEventsStore.directDownloadURL(fromLink: raw) else {
            message = "Ez nem tűnik naptár-linknek (webcím, Google-megosztólink vagy webcal kell)."
            return
        }
        downloading = true
        defer { downloading = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let text = SchoolEventsStore.decodeData(data),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                message = "Üres vagy olvashatatlan a link tartalma."
                return
            }
            // ICS-t várunk, de ha sima listát ad a lap, a szöveg-olvasóval
            // is megpróbáljuk — az egyiket úgyis megfogja.
            let parsed = SchoolEventsStore.parseAny(text)
            guard !parsed.isEmpty else {
                message = "Nincs benne felismerhető esemény."
                return
            }
            SchoolEventsStore.replaceAll(parsed, sourceName: url.host ?? "link")
            // Az eredeti (megosztó)linket mentjük — a frissítés újrafeloldja.
            SchoolEventsStore.saveURL(raw.trimmingCharacters(in: .whitespacesAndNewlines))
            refresh()
            message = syncedMessage("\(parsed.count) esemény letöltve linkről")
        } catch {
            message = "Nem sikerült letölteni — ellenőrizd a címet és a kapcsolatot."
        }
    }

    /// Beillesztett szöveg feldolgozása — nyers ICS-tartalom is mehet
    /// egyben (azt a szabványos olvasó fogja meg, nem a szöveges).
    private func importText() {
        let parsed = SchoolEventsStore.parseAny(pastedText)
        guard !parsed.isEmpty else {
            message = "Nincs benne felismerhető dátum. Soronként: dátum + cím (pl. „2026.09.01. Tanévnyitó”) — vagy nyers ICS-tartalom egyben."
            return
        }
        SchoolEventsStore.replaceAll(parsed, sourceName: "beillesztett szöveg")
        pastedText = ""
        showPaste = false
        refresh()
        message = syncedMessage("\(parsed.count) esemény feldolgozva szövegből")
    }

    private func syncedMessage(_ base: String) -> String {
        if summitSync.isEnabled {
            return base + " — szinkronizálva a többi eszközre."
        } else {
            return base + " ezen az eszközön."
        }
    }

    private func importICS(from url: URL) {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let text = SchoolEventsStore.decodeData(data),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "Üres vagy olvashatatlan fájl."
            return
        }
        let parsed = SchoolEventsICS.parse(text)
        guard !parsed.isEmpty else {
            message = "Nincs benne naptáresemény (VEVENT / DTSTART kell)."
            return
        }
        // Mentés → store-értesítés → `schoolEvents` dirty → SummitSync feltölti.
        SchoolEventsStore.replaceAll(parsed, sourceName: url.lastPathComponent)
        refresh()
        if summitSync.isEnabled {
            message = "\(parsed.count) esemény importálva — szinkronizálva."
        } else {
            message = "\(parsed.count) esemény importálva."
        }
    }
}
