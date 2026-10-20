import Foundation

// MARK: - Órai közvetlen AI-kérdezés (az óra saját lábán)
// Az óra a saját netjén hívja a Meta-végpontot — telefon sem kell
// hozzá. A kulcsot a telefon tolja át (WatchPayloadKey.metaKey,
// WatchSharedStore.metaAIKey). Csak Foundation: ugyanez a fájl
// önállóan is fordítható + futtatható macOS-en ellenőrzéshez.
// Sorrend a telefonival azonosan: 1) órai jegyzet-törzsek (az órára
// csak vágott, 1500 karakteres törzsek utaznak), 2) web (Wikipédia),
// 3) saját tudás jelölve ("rendes AI-válasz"), 4) őszinte "nincs meg".
// A prompt NINCS_MEG őrszóval kényszeríti ki a bevallást, a
// parafrázisokat ("nincs benne a témában", ...) a WatchAskGate
// ismeri fel — ilyenkor fut a webes + tudásos tartalék.
// Anyag-korlát: a teljes feltöltött anyag NINCS az órán (csak a
// vágott témák) — ha az kevés, a telefonos tartalék (WatchSyncStore)
// a teljes anyaggal válaszol.
enum WatchAskDirect {
    /// Kérdés-környezet plafonja (az órai vágott törzsekhez mérve).
    private static let maxNoteChars = 12_000
    /// Válasz-plafon: watch-értesítésbe is belefér, órán is olvasható.
    private static let maxAnswerChars = 2_000

    enum DirectError: Error {
        case noKey
        case noMaterial
        case network(String)
        case badStatus(Int)
        case rateLimited
        case badResponse
    }

    /// Teljes kérdezési kör az órán: jegyzet, aztán web. Hibánál dob —
    /// a hívó ilyenkor a telefonos tartalékra kapcsolhat.
    static func answer(
        question: String,
        sheet: WatchCheatSheet,
        topics: [WatchCheatTopic],
        apiKey: String
    ) async throws -> (text: String, source: String) {
        let q = String(question.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        guard !q.isEmpty else { throw DirectError.noMaterial }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw DirectError.noKey }

        let note = String(topics
            .map { "\($0.title): \($0.body)" }
            .joined(separator: "\n\n")
            .prefix(maxNoteChars))
        guard !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DirectError.noMaterial
        }

        // 1) Saját anyag — szigorú őrszóval: ami nincs benne, arra
        // NINCS_MEG a teljes válasz (semmi más), nem saját tudás.
        let systemOwn = """
        Magyar nyelvű tanulási segítő vagy egy konkrét jegyzetlaphoz. \
        SZIGORÚ SZABÁLY: kizárólag a megadott JEGYZET szövegéből \
        vehetsz tényeket. Ha a kérdés ezek alapján nem megválaszolható, \
        a teljes válaszod pontosan ez legyen: NINCS_MEG — semmi más, \
        semmi magyarázat. Soha ne írj a saját tanult tudásodból tényeket, \
        és soha ne találj ki semmit.
        """
        let userOwn = """
        Tantárgy: \(sheet.subject). Lap: \(sheet.title).

        JEGYZET:
        \(note)

        KÉRDÉS: \(q)

        Válaszolj röviden, magyarul, az órai kijelzőre (pár mondat, felsorolás ha illik).
        """
        let first = try await metaChat(system: systemOwn, user: userOwn, apiKey: key)
        if !WatchAskGate.isNoMaterial(first) {
            return (String(first.prefix(maxAnswerChars)), WatchAskSource.material)
        }

        // 2) Web — a saját anyagban nem volt meg. Wikipédia
        // (kulcs nélkül) megy kontextusként, a megfogalmazást a
        // Meta-modell végzi.
        let snippets = await WatchWebSearch.search(query: q)
        if !snippets.isEmpty {
            let webCtx = String(snippets
                .map { "### \($0.title)\n\($0.extract)" }
                .joined(separator: "\n\n")
                .prefix(maxNoteChars))
            let systemWeb = """
            Magyar nyelvű tanulási segítő vagy. Az alábbi WEBES FORRÁSOKból \
            válaszolsz — csak ami bennük szerepel. Ha a kérdés ezek alapján \
            nem megválaszolható, a teljes válaszod pontosan ez legyen: \
            NINCS_MEG — semmi más. Soha ne írj a saját tanult tudásodból \
            tényeket, és soha ne találj ki semmit.
            """
            // Web-hiba (net, státusz) nem állítja meg a kört: ilyenkor
            // a saját tudásos tartalék következik, nem dobunk.
            if let second = try? await metaChat(
                system: systemWeb,
                user: "WEBES FORRÁSOK:\n\(webCtx)\n\nKÉRDÉS: \(q)\n\nVálaszolj röviden, magyarul, az órai kijelzőre.",
                apiKey: key
            ), !WatchAskGate.isNoMaterial(second) {
                let srcTitles = snippets.prefix(3).map { $0.title }.joined(separator: ", ")
                let withSrc = "\(second)\n\n(Forrás: web — \(srcTitles))"
                return (String(withSrc.prefix(maxAnswerChars)), WatchAskSource.web)
            }
        }
        // 3) Saját tudás — jelölve. A jegyzetben és a weben sincs meg,
        // de a modell ettől még tudhatja: ez már "rendes AI-válasz",
        // viszont MINDIG megjelöljük, hogy nem a jegyzetből van.
        let systemFree = """
        Magyar nyelvű tanulási segítő vagy. A kérdésre a saját tudásodból \
        válaszolsz, röviden, magyarul, az órai kijelzőre (pár mondat, \
        felsorolás ha illik). Ha valamit nem tudsz, azt mondd meg őszintén.
        """
        let third = try await metaChat(
            system: systemFree,
            user: "Tantárgy: \(sheet.subject). Lap: \(sheet.title).\n\nKÉRDÉS: \(q)\n\nVálaszolj röviden, magyarul.",
            apiKey: key
        )
        let t = third.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !WatchAskGate.isNoMaterial(third) else {
            return (
                "Erre sem a jegyzetben, sem a weben nincs válasz — kérdezz mást, vagy bővítsd a lap anyagát.",
                WatchAskSource.none
            )
        }
        return (
            String("\(t)\n\n(Megj.: nem a jegyzetből, saját tudásból — ellenőrizd.)".prefix(maxAnswerChars)),
            WatchAskSource.knowledge
        )
    }

    // MARK: - Meta chat (exkluzív modell)

    private static func metaChat(system: String, user: String, apiKey: String) async throws -> String {
        let body: [String: Any] = [
            "model": WatchAI.model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
            "temperature": 0.2,
        ]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            throw DirectError.badResponse
        }
        var req = URLRequest(url: WatchAI.endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = httpBody
        req.timeoutInterval = 120
        let data: Data
        let status: Int
        do {
            let (d, resp) = try await URLSession.shared.data(for: req)
            data = d
            status = (resp as? HTTPURLResponse)?.statusCode ?? -1
        } catch {
            throw DirectError.network(error.localizedDescription)
        }
        if status == 429 { throw DirectError.rateLimited }
        guard status == 200 else { throw DirectError.badStatus(status) }
        guard let content = extractContent(from: data) else { throw DirectError.badResponse }
        return content
    }

    // MARK: - Válaszfejtés

    private struct WireChoiceMsg: Decodable { var content: String? }
    private struct WireChoice: Decodable { var message: WireChoiceMsg? }
    private struct WireResp: Decodable { var choices: [WireChoice]? }

    /// OpenAI-kompatibilis válaszból a szöveg (kerítés-lefejtéssel).
    /// `internal` az önálló macOS-harness kedvéért (azonos modulban fut).
    static func extractContent(from data: Data) -> String? {
        guard let resp = try? JSONDecoder().decode(WireResp.self, from: data),
              let content = resp.choices?.first?.message?.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return stripFences(content).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Órára szabott, rövid hibaüzenet a Meta-hibákból.
    static func friendlyError(_ error: Error) -> String {
        if let e = error as? DirectError {
            switch e {
            case .noKey:
                return "Nincs Meta AI-kulcs az órán — add meg a telefonon, és újra megy."
            case .rateLimited:
                return "A közös keret épp betelt — próbáld később."
            case .badStatus(let c) where c == 401 || c == 403:
                return "A Meta-kulcsot elutasították — ellenőrizd a telefonon."
            case .network:
                return "Nincs net az órán — próbáld újra."
            default:
                return "Az AI most nem válaszolt — próbáld újra."
            }
        }
        return "Az AI most nem válaszolt — próbáld újra."
    }

    // MARK: - Webes fallback: közös réteg (Wikipédia + DuckDuckGo)
    // Lásd WatchWebSearch — a webes kiegészítés az órán és a telefonon
    // azonos, hogy a két kérdezési út ugyanazt tudja.

    static func stripFences(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("```") else { return t }
        var lines = t.components(separatedBy: "\n")
        if lines.first?.hasPrefix("```") == true { lines.removeFirst() }
        if lines.last?.trimmingCharacters(in: .whitespaces) == "```" { lines.removeLast() }
        return lines.joined(separator: "\n")
    }
}
