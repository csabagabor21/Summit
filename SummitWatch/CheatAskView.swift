import SwiftUI

// MARK: - Kérdezés a jegyzetből (óra)
// Egy lapon belül, a témák alatt indul: a gomb megnyitja ezt a nézetet,
// a fókuszált mezőre azonnal feljön a natív beviteli UI (billentyűzet /
// diktálás / firkálás — a rendszer adja, külön kód nem kell hozzá).
// A válasz az iPhone-on születik (mentett Meta-kulcs, exkluzív
// muse-spark-1.3-contributor): előbb a saját feltöltött anyagból,
// ha ott nincs meg, webes kereséssel — saját tudásból soha.
// Double Tap: amíg nincs válasz, a Kérdezés a fő gomb; ha megjött,
// a Kész veszi át a szerepet (mindig csak az egyik látszik, így a
// rendszer gesztusa mindig a jót választja).
/// Navigációs útvonal a témalista aljáról a kérdezőnézetbe.
struct WatchAskRoute: Hashable {
    let sheetID: String
}

/// Double Tap-főgomb watchOS 10-en is: a `handGestureShortcut` csak
/// watchOS 11-től létezik, alatta a gomb sima gomb marad (a Double
/// Tap ott rendszer-szinten nem címezhető).
private extension View {
    @ViewBuilder
    func watchPrimaryAction() -> some View {
        if #available(watchOS 11, *) {
            self.handGestureShortcut(.primaryAction)
        } else {
            self
        }
    }
}

struct CheatAskView: View {
    let sheet: WatchCheatSheet

    @EnvironmentObject var store: WatchSyncStore
    @State private var question = ""
    @State private var answer: String?
    @State private var source = WatchAskSource.none
    @State private var errorText: String?
    @State private var isAsking = false
    @FocusState private var isInputFocused: Bool

    private var canAsk: Bool {
        !isAsking && !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sourceCaption: String {
        switch source {
        case WatchAskSource.material: return "Forrás: saját anyag"
        case WatchAskSource.web: return "Forrás: web"
        default: return "Forrás: nincs találat"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Kérdezz vagy diktálj…", text: $question)
                    .font(.caption)
                    .focused($isInputFocused)
                    .onSubmit { ask() }

                if answer == nil {
                    Button {
                        ask()
                    } label: {
                        if isAsking {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.7)
                                Text("Gondolkodom…")
                            }
                        } else {
                            Label("Kérdezés", systemImage: "mic.fill")
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(canAsk || isAsking ? Color.green : Color.gray.opacity(0.5))
                    .clipShape(Capsule())
                    // Fő gomb válasz előtt: Double Tap ezt választja.
                    .watchPrimaryAction()
                    .disabled(!canAsk && !isAsking)
                }

                if let err = errorText {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                if let answer {
                    Text(answer)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(sourceCaption)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    Button {
                        WatchHaptics.tick()
                        self.answer = nil
                        errorText = nil
                        question = ""
                        isInputFocused = true
                    } label: {
                        Label("Kész", systemImage: "checkmark")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.green)
                    .clipShape(Capsule())
                    // Válasz után a Kész a fő gomb: Double Tap eltünteti.
                    .watchPrimaryAction()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .navigationTitle("Kérdezés")
        .onAppear { isInputFocused = true }
    }

    private func ask() {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isAsking else { return }
        WatchHaptics.tick()
        isInputFocused = false
        errorText = nil
        answer = nil
        isAsking = true
        Task {
            let result = await store.askQuestion(sheetID: sheet.id, question: q)
            isAsking = false
            switch result {
            case .answer(let text, let src):
                answer = text
                source = src
            case .error(let msg):
                errorText = msg
                isInputFocused = true
            }
        }
    }
}
