import SwiftUI
import UserNotifications

// MARK: - Kérdezés (óra)
// Csak beviteli nézet: megnyitáskor a fókusz azonnal felhozza a natív
// billentyűzetet / diktálást, beküldéskor a nézet ELTŰNIK, és a válasz
// watch-értesítésben jön meg — közben a többi jegyzet szabadon
// lapozható. Nincs helyben várakozó "gondolkodom" képernyő.
// A válasz az iPhone-on születik (mentett Meta-kulcs, exkluzív
// muse-spark-1.3-contributor): előbb a saját feltöltött anyagból,
// ha ott nincs meg, webes kereséssel — saját tudásból soha.
// Double Tap: a Kérdezés a fő gomb (mindig ez látszik a válasz
// előtt, mert a válasz már értesítésben érkezik).
/// Navigációs útvonal a témalista aljáról a kérdezőnézetbe.
struct WatchAskRoute: Hashable {
    let sheetID: String
}

struct CheatAskView: View {
    let sheet: WatchCheatSheet

    @EnvironmentObject var store: WatchSyncStore
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @FocusState private var isInputFocused: Bool

    /// Késleltetett fókusz: a navigációs animáció alatt kért fókuszt a
    /// rendszer eldobja, ezért a nézet megérkezése után kérjük újra —
    /// így a billentyűzet / diktálás megnyitáskor magától feljön, nem
    /// kell külön a mezőre koppintani. Ha az első kérést a rendszer
    /// mégis eldobná, fél mp múlva újra próbáljuk.
    private func focusInput(delayMs: UInt64 = 350) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
            isInputFocused = true
            try? await Task.sleep(nanoseconds: 600_000_000)
            if !isInputFocused {
                isInputFocused = true
            }
        }
    }

    var body: some View {
        List {
            Section {
                TextField("Kérdés", text: $question, prompt: Text("Kérdezz vagy diktálj…"))
                    .focused($isInputFocused)
                    .onSubmit { ask() }
            } footer: {
                Text(sheet.title)
            }

            Section {
                Button {
                    ask()
                } label: {
                    Label {
                        Text("Kérdezés")
                    } icon: {
                        Image("MetaAI")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 18, height: 18)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                // Fő gomb: Double Tap ezt választja. Üres kérdéssel
                // sem hibázik, hanem felhozza a billentyűzetet.
                .watchPrimaryAction()
            } footer: {
                // Egy mondat, hogy hova megy a válasz — ez nem
                // marketing-szöveg, hanem a folyamat ígérete.
                Text("A válasz értesítésben jön meg.")
            }
        }
        .navigationTitle("Kérdezés")
        .onAppear {
            focusInput()
            // Kontextusos engedélykérés: a footer megígéri, hogy a
            // válasz értesítésben jön — itt kérünk rá engedélyt,
            // nem az app indulásakor. Idempotens, csak egyszer kérdez.
            Task {
                try? await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])
            }
        }
    }

    private func ask() {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        // Üres kérdéssel a gomb nem hibázik, hanem felhozza a
        // billentyűzetet — így a Double Tap is mindig csinál valamit.
        guard !q.isEmpty else {
            WatchHaptics.tick()
            focusInput(delayMs: 0)
            return
        }
        WatchHaptics.tick()
        isInputFocused = false
        // A nézet azonnal eltűnik — a válasz háttérben készül, és
        // watch-értesítésben érkezik, a jegyzetek addig használhatók.
        dismiss()
        store.askInBackground(sheetID: sheet.id, sheetTitle: sheet.title, question: String(q.prefix(500)))
    }
}
