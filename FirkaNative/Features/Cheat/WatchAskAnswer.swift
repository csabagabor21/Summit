import Foundation

// MARK: - Órai jegyzet-kérdés megválaszolása (iPhone-oldal)
// Az óra csak a kérdést + a lap-ID-t küldi (WatchPayloadKey.ask),
// a válasz itt születik, mert itt van a Meta-kulcs ÉS a TELJES
// feltöltött anyag (az órára csak vágott, 1500 karakteres
// jegyzet-törzsek utaznak). A kulcs sosem hagyja el a telefont.
// Modell KIZÁRÓLAG a mentett Meta-kulcshoz tartozó
// muse-spark-1.3-contributor (MetaAIClient) — kulcs nélkül nincs
// válasz (nincs néma Gemini-tartalék ezen az úton).
// Sorrend: 1) saját jegyzet + feltöltött anyag, 2) web (Wikipédia),
// 3) saját tudás jelölve ("rendes AI-válasz"), 4) őszinte "nincs meg".
// A prompt NINCS_MEG őrszóval kényszeríti ki a bevallást, a
// parafrázisokat ("nincs benne a témában", ...) a WatchAskGate
// ismeri fel — ilyenkor fut a webes + tudásos tartalék.
enum WatchAskAnswer {
    /// Jegyzet-környezet plafonja (karakter): az órai kijelzőhöz
    /// mérten bőven elég, a kérést pedig kordában tartja.
    private static let maxNoteChars = 12_000
    private static let maxCorpusChars = 12_000
    /// Válasz-plafon: WCSession-üzenetbe is belefér, órán is olvasható.
    private static let maxAnswerChars = 2_000

    /// WCSession-üzenetből reply-szótár (mindig String értékek).
    static func answer(message: [String: Any]) async -> [String: String] {
        let question = ((message[WatchAskField.question] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sheetID = (message[WatchAskField.sheetID] as? String) ?? ""
        guard !question.isEmpty else {
            return [WatchAskField.error: "Üres kérdésre nem tudok válaszolni."]
        }
        let q = String(question.prefix(500))
        guard let sheet = CheatStore.load().first(where: { $0.id == sheetID }) else {
            return [WatchAskField.error: "Ez a lap már nincs meg a telefonon — szinkronizáld újra."]
        }
        guard MetaAIKeyStore.hasKey else {
            return [WatchAskField.error: "Nincs Meta AI-kulcs a telefonon — add meg a Beállításokban, és újra megy."]
        }

        let note = String(sheet.topics
            .map { "\($0.title): \($0.body)" }
            .joined(separator: "\n\n")
            .prefix(maxNoteChars))
        let corpus = String(sheet.materials
            .map { CheatStore.fullText(id: $0.id) ?? $0.text }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(maxCorpusChars))
        guard !note.isEmpty || !corpus.isEmpty else {
            return [WatchAskField.error: "Ehhez a laphoz nincs anyag — tölts fel jegyzetet a telefonon."]
        }

        // 1) Saját anyag — szigorú őrszóval: ami nincs benne, arra
        // NINCS_MEG a teljes válasz (semmi más), nem saját tudás.
        let systemOwn = """
        Magyar nyelvű tanulási segítő vagy egy konkrét jegyzetlaphoz. \
        SZIGORÚ SZABÁLY: kizárólag a megadott JEGYZET és TANANYAG szövegéből \
        vehetsz tényeket. Ha a kérdés ezek alapján nem megválaszolható, \
        a teljes válaszod pontosan ez legyen: NINCS_MEG — semmi más, \
        semmi magyarázat. Soha ne írj a saját tanult tudásodból tényeket, \
        és soha ne találj ki semmit.
        """
        let userOwn = """
        Tantárgy: \(sheet.subject). Lap: \(sheet.title).

        JEGYZET:
        \(note)

        TANANYAG:
        \(corpus)

        KÉRDÉS: \(q)

        Válaszolj röviden, magyarul, az órai kijelzőre (pár mondat, felsorolás ha illik).
        """
        let first: String
        do {
            first = try await metaChat(system: systemOwn, user: userOwn)
        } catch {
            return [WatchAskField.error: Self.friendlyError(error)]
        }
        if !WatchAskGate.isNoMaterial(first) {
            return [
                WatchAskField.answer: String(first.prefix(maxAnswerChars)),
                WatchAskField.source: WatchAskSource.material,
            ]
        }

        // 2) Web — a saját anyagban nem volt meg. Wikipédia
        // (kulcs nélkül) megy kontextusként, a megfogalmazást továbbra
        // is a Meta-modell végzi (a modell ezen az úton is exkluzív).
        let snippets = await WatchWebSearch.search(query: q)
        if !snippets.isEmpty {
            let webCtx = String(snippets
                .map { "### \($0.title)\n\($0.extract)" }
                .joined(separator: "\n\n")
                .prefix(maxCorpusChars))
            let systemWeb = """
            Magyar nyelvű tanulási segítő vagy. Az alábbi WEBES FORRÁSOKból \
            válaszolsz — csak ami bennük szerepel. Ha a kérdés ezek alapján \
            nem megválaszolható, a teljes válaszod pontosan ez legyen: \
            NINCS_MEG — semmi más. Soha ne írj a saját tanult tudásodból \
            tényeket, és soha ne találj ki semmit.
            """
            // Web-hiba (net, státusz) nem állítja meg a kört: ilyenkor
            // a saját tudásos tartalék következik, nem hibaüzenet.
            if let second = try? await metaChat(
                system: systemWeb,
                user: "WEBES FORRÁSOK:\n\(webCtx)\n\nKÉRDÉS: \(q)\n\nVálaszolj röviden, magyarul, az órai kijelzőre."
            ), !WatchAskGate.isNoMaterial(second) {
                let srcTitles = snippets.prefix(3).map { $0.title }.joined(separator: ", ")
                let withSrc = "\(second)\n\n(Forrás: web — \(srcTitles))"
                return [
                    WatchAskField.answer: String(withSrc.prefix(maxAnswerChars)),
                    WatchAskField.source: WatchAskSource.web,
                ]
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
        let third: String
        do {
            third = try await metaChat(
                system: systemFree,
                user: "Tantárgy: \(sheet.subject). Lap: \(sheet.title).\n\nKÉRDÉS: \(q)\n\nVálaszolj röviden, magyarul."
            )
        } catch {
            return [WatchAskField.error: Self.friendlyError(error)]
        }
        let t = third.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !WatchAskGate.isNoMaterial(third) else {
            return [
                WatchAskField.answer: "Erre sem a jegyzetben, sem a weben nincs válasz — kérdezz mást, vagy bővítsd a lap anyagát.",
                WatchAskField.source: WatchAskSource.none,
            ]
        }
        return [
            WatchAskField.answer: String("\(t)\n\n(Megj.: nem a jegyzetből, saját tudásból — ellenőrizd.)".prefix(maxAnswerChars)),
            WatchAskField.source: WatchAskSource.knowledge,
        ]
    }

    // MARK: - Meta chat (exkluzív modell)

    private static func metaChat(system: String, user: String) async throws -> String {
        let body: [String: Any] = [
            "model": MetaAIClient.model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
            "temperature": 0.2,
        ]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            throw MetaAIClient.AIError.badResponse
        }
        var req = URLRequest(url: MetaAIClient.endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(MetaAIKeyStore.apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = httpBody
        req.timeoutInterval = 120
        let data: Data
        let status: Int
        do {
            let (d, resp) = try await URLSession.shared.data(for: req)
            data = d
            status = (resp as? HTTPURLResponse)?.statusCode ?? -1
        } catch {
            throw MetaAIClient.AIError.network(error.localizedDescription)
        }
        if status == 429 { throw MetaAIClient.AIError.rateLimited }
        guard status == 200 else { throw MetaAIClient.AIError.badStatus(status) }
        guard let resp = try? JSONDecoder().decode(MetaAIClient.WireResp.self, from: data),
              let content = resp.choices?.first?.message?.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MetaAIClient.AIError.badResponse
        }
        return MetaAIClient.stripFences(content).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Órára szabott, rövid hibaüzenet a Meta-hibákból.
    private static func friendlyError(_ error: Error) -> String {
        if let ai = error as? MetaAIClient.AIError {
            switch ai {
            case .rateLimited:
                return "A közös keret épp betelt — próbáld később."
            case .badStatus(let c) where c == 401 || c == 403:
                return "A Meta-kulcsot elutasították — ellenőrizd a telefonon."
            case .network:
                return "Nincs net a telefonon — próbáld újra."
            default:
                return "Az AI most nem válaszolt — próbáld újra."
            }
        }
        return "Az AI most nem válaszolt — próbáld újra."
    }

    // MARK: - Webes fallback: közös réteg (Wikipédia + DuckDuckGo)
    // Lásd WatchWebSearch — a webes kiegészítés az órán és a telefonon
    // azonos, hogy a két kérdezési út ugyanazt tudja.
}
