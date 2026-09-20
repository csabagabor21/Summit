import SwiftUI
import UniformTypeIdentifiers

/// Iskolai események (tannaptár) — egyszeri bevitel a Beállításokban.
/// Három iPhone-barát út (fájl, link, beillesztett szöveg), mind ugyanabba
/// a store-ba ír: a tisztított események a SummitSync-kel minden eszközre
/// átmennek (újra bevinni sehol nem kell).
struct SchoolEventsSection: View {
    @EnvironmentObject var summitSync: SummitSync
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
                Text("Még nincs tannaptár — linkből, beillesztett szövegből vagy .ics fájlból viheted be (pl. a suli honlapjáról kimásolva).")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(summaryText).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 1) Link: a suli naptárjának webcíme (suli honlap, Google Naptár
            // nyilvános ICS-linkje) — letölteni nem kell, az app lehúzza.
            VStack(alignment: .leading, spacing: 6) {
                Text("Linkből").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                HStack {
                    TextField("https://… .ics link", text: $linkText)
                        .font(.subheadline.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
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
                        .font(.subheadline.monospaced())
                        .frame(minHeight: 110, maxHeight: 200)
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12)))
                    Text("Soronként: dátum + cím. Pl.\n2026.09.01. Tanévnyitó 8:00\nokt 26-28. Őszi szünet\n01.15. Félévi értesítők")
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
        .onAppear { refresh() }
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

    /// Linkről lehúzott ICS — letölteni nem kell, az app intézi.
    private func download(_ raw: String) async {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            message = "Ez nem tűnik webcímnek (http/https kell)."
            return
        }
        downloading = true
        defer { downloading = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let text = decode(data),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                message = "Üres vagy olvashatatlan a link tartalma."
                return
            }
            // ICS-t várunk, de ha sima listát ad a lap, a szöveg-olvasóval
            // is megpróbáljuk — az egyiket úgyis megfogja.
            var parsed = SchoolEventsICS.parse(text)
            if parsed.isEmpty { parsed = SchoolEventsText.parse(text) }
            guard !parsed.isEmpty else {
                message = "Nincs benne felismerhető esemény."
                return
            }
            SchoolEventsStore.replaceAll(parsed, sourceName: url.host ?? "link")
            SchoolEventsStore.saveURL(trimmed)
            refresh()
            message = syncedMessage("\(parsed.count) esemény letöltve linkről")
        } catch {
            message = "Nem sikerült letölteni — ellenőrizd a címet és a kapcsolatot."
        }
    }

    /// Beillesztett szabad szöveg feldolgozása.
    private func importText() {
        let parsed = SchoolEventsText.parse(pastedText)
        guard !parsed.isEmpty else {
            message = "Nincs benne felismerhető dátum. Soronként: dátum + cím (pl. „2026.09.01. Tanévnyitó”)."
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
            return base + " — szinkronizálódik a többi eszközre."
        } else {
            return base + " ezen az eszközön. Ha bekapcsolod a szinkront, átmegy a többire is."
        }
    }

    private func importICS(from url: URL) {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let text = decode(data),
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
            message = "\(parsed.count) esemény importálva — szinkronizálódik a többi eszközre."
        } else {
            message = "\(parsed.count) esemény importálva ezen az eszközön. Ha bekapcsolod a szinkront, átmegy a többire is."
        }
    }

    /// Magyar ékezetek miatt: UTF-8, aztán közép-európai kódlapok.
    private func decode(_ data: Data) -> String? {
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .windowsCP1250) { return s }
        return String(data: data, encoding: .isoLatin1)
    }
}
