import SwiftUI
import UniformTypeIdentifiers

/// Iskolai események (tannaptár) — egyszeri ICS-import a Beállításokban.
/// A fájl csak egyszer kell: a tisztított események a SummitSync-kel
/// minden eszközre átmennek (újraimportálni sehol nem kell).
struct SchoolEventsSection: View {
    @EnvironmentObject var summitSync: SummitSync
    @Environment(\.colorScheme) var scheme
    @AppStorage(SchoolEventsStore.showKey) private var showInTimetable = true
    @State private var events: [SchoolEvent] = SchoolEventsStore.load()
    @State private var source: String? = SchoolEventsStore.sourceName()
    @State private var importing = false
    @State private var message = ""

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
                Text("Még nincs tannaptár — importálj egy .ics fájlt (pl. AI-jal generáltathatsz a suli táblázatából/képéből).")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(summaryText).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 16) {
                Button(importing ? "Importálás…" : (events.isEmpty ? "ICS importálása" : "Új ICS")) {
                    importing = true
                }
                .font(.caption.weight(.bold))
                .disabled(importing)
                if !events.isEmpty {
                    Button("Törlés", role: .destructive) {
                        // A törlés is terjed: a store-értesítés dirty-zi a
                        // `schoolEvents` mezőt, a `"[]"` felmegy a szerverre.
                        SchoolEventsStore.removeAll()
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
