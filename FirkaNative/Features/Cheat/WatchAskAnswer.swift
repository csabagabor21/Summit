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
// 3) őszinte "nincs meg". Saját tanult tudásból SOHA — a prompt
// NINCS_MEG őrszóval kényszeríti ki a bevallást.
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
        if first.trimmingCharacters(in: .whitespacesAndNewlines) != "NINCS_MEG", !first.isEmpty {
            return [
                WatchAskField.answer: String(first.prefix(maxAnswerChars)),
                WatchAskField.source: WatchAskSource.material,
            ]
        }

        // 2) Web — a saját anyagban nem volt meg. Wikipédia-kivonatok
        // mennek kontextusként, a megfogalmazást továbbra is a Meta-modell
        // végzi (a modell ezen az úton is exkluzív).
        let snippets = await webSnippets(for: q)
        guard !snippets.isEmpty else {
            return [
                WatchAskField.answer: "Erre sem a jegyzetben, sem a weben nincs válasz — kérdezz mást, vagy bővítsd a lap anyagát.",
                WatchAskField.source: WatchAskSource.none,
            ]
        }
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
        let second: String
        do {
            second = try await metaChat(
                system: systemWeb,
                user: "WEBES FORRÁSOK:\n\(webCtx)\n\nKÉRDÉS: \(q)\n\nVálaszolj röviden, magyarul, az órai kijelzőre."
            )
        } catch {
            return [WatchAskField.error: Self.friendlyError(error)]
        }
        if second.trimmingCharacters(in: .whitespacesAndNewlines) != "NINCS_MEG", !second.isEmpty {
            let srcTitles = snippets.prefix(3).map { $0.title }.joined(separator: ", ")
            let withSrc = "\(second)\n\n(Forrás: web — Wikipédia: \(srcTitles))"
            return [
                WatchAskField.answer: String(withSrc.prefix(maxAnswerChars)),
                WatchAskField.source: WatchAskSource.web,
            ]
        }
        return [
            WatchAskField.answer: "Erre sem a jegyzetben, sem a weben nincs válasz — kérdezz mást, vagy bővítsd a lap anyagát.",
            WatchAskField.source: WatchAskSource.none,
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

    // MARK: - Webes fallback (Wikipédia, kulcs nélkül)

    private struct Snippet {
        var title: String
        var extract: String
    }

    /// Wikipédia-keresés + bevezető-kivonatok (magyarul, találat nélkül
    /// angolul). Üres = a weben sincs használható találat.
    private static func webSnippets(for query: String) async -> [Snippet] {
        if let hu = await wikipediaSnippets(query: query, lang: "hu"), !hu.isEmpty {
            return hu
        }
        return await wikipediaSnippets(query: query, lang: "en") ?? []
    }

    private static func wikipediaSnippets(query: String, lang: String) async -> [Snippet]? {
        guard let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "https://\(lang).wikipedia.org/w/api.php?action=query&list=search&srsearch=\(q)&format=json&srlimit=5") else {
            return nil
        }
        struct SearchHit: Decodable { var title: String }
        struct SearchQuery: Decodable { var search: [SearchHit]? }
        struct SearchResp: Decodable { var query: SearchQuery? }
        var req = URLRequest(url: searchURL)
        req.timeoutInterval = 15
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(SearchResp.self, from: data),
              let hits = decoded.query?.search, !hits.isEmpty else {
            return nil
        }
        let titles = hits.prefix(3).map { $0.title }
        guard let t = titles.joined(separator: "|").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let extURL = URL(string: "https://\(lang).wikipedia.org/w/api.php?action=query&prop=extracts&exintro&explaintext&titles=\(t)&format=json") else {
            return nil
        }
        var ereq = URLRequest(url: extURL)
        ereq.timeoutInterval = 15
        guard let (edata, eresp) = try? await URLSession.shared.data(for: ereq),
              (eresp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: edata) as? [String: Any],
              let pages = (json["query"] as? [String: Any])?["pages"] as? [String: Any] else {
            return nil
        }
        var out: [Snippet] = []
        for title in titles {
            if let page = pages.values.compactMap({ $0 as? [String: Any] })
                .first(where: { ($0["title"] as? String) == title }),
               let extract = page["extract"] as? String, !extract.isEmpty {
                out.append(Snippet(title: title, extract: String(extract.prefix(1_500))))
            }
        }
        return out
    }
}
