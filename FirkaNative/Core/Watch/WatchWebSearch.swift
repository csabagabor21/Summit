import Foundation

// MARK: - Közös webes keresőréteg az órai kérdezéshez
// Csak Foundation — az iPhone-app és az óra-app is fordítja, így a
// webes kiegészítés MINDKÉT kérdezési úton azonos. Kulcs nélkül,
// Wikipédiából (magyarul, találat nélkül angolul).
// (DuckDuckGo Instant Answer kiértékelve, ELVETVE: az Apple
// URLSession-klienseknek csonka teszt-választ ad — "Just Another
// Test" stubot — míg curl-lel ugyanaz a kérés rendes találatot hoz.
// Valódi netes kereséshez kulcsos API kellene, pl. Brave Search.)
// A Meta-modell nem böngészik, ezért a webes kontextust mi hozzuk.
struct WebSearchSnippet {
    var title: String
    var extract: String
}

// MARK: - Téma-őr felismerése (közös, mindkét kérdezési úton azonos)
// A saját-anyag prompt NINCS_MEG őrszót kér, de a modell néha
// átfogalmazza ("ez nincs benne a témában", "nem szerepel a
// jegyzetben", ...). Ha csak a pontos tokenre figyelünk, az ilyen
// parafrázis anyagi válaszként átmegy, és a webes + saját tudásos
// tartalék (a "rendes AI-válasz") sosem fut le. Ezért a kiürült
// választ itt ismerjük fel, nem a hívóknál egyenként.
enum WatchAskGate {
    /// Üres vagy témán-kívüli bevallás? Ilyenkor mehet a webes,
    /// majd a saját tudásos tartalék.
    static func isNoMaterial(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return true }
        if t.range(of: "NINCS_MEG", options: .caseInsensitive) != nil { return true }
        // Csak rövid, forráshiányra hivatkozó elutasításokat engedünk
        // tovább — egy hosszú, érdemi válaszban a "nincs" szó mást
        // jelenthet ("nincs kizárva, hogy...").
        guard t.count < 300 else { return false }
        let l = t.lowercased()
        let paraphrases = [
            "nincs benne",
            "nem szerepel",
            "nem tartalmaz",
            "nem található", "nem talalhato",
            "nincs információ", "nincs informacio",
            "nem tudom megválaszolni", "nem tudom megvalaszolni",
            "nincs a jegyzet", "nincs az anyag",
            "nem áll rendelkezésre", "nem all rendelkezesre",
        ]
        if paraphrases.contains(where: { l.contains($0) }) { return true }
        if l.contains("nincs")
            && (l.contains("jegyzet") || l.contains("anyag")
                || l.contains("téma") || l.contains("tema")
                || l.contains("forrás") || l.contains("forras")
                || l.contains("szöveg") || l.contains("szoveg")
                || l.contains("tananyag")) {
            return true
        }
        return false
    }
}

enum WatchWebSearch {
    /// Webes kiegészítés egy kérdéshez, forrásonként címkézve.
    /// Párhuzamosan kér, mindegyik forrás külön hibázhat.
    static func search(query: String) async -> [WebSearchSnippet] {
        let wiki = await wikipediaSnippets(query: query)
        var out: [WebSearchSnippet] = []
        var seen = Set<String>()
        for s in wiki {
            let k = s.title.lowercased()
            if !s.extract.isEmpty, !seen.contains(k) {
                seen.insert(k)
                out.append(s)
            }
        }
        return Array(out.prefix(6))
    }

    // MARK: - Wikipédia (hu, találat nélkül en)

    private static func wikipediaSnippets(query: String) async -> [WebSearchSnippet] {
        let hu = await wikipediaLang(query: query, lang: "hu", limit: 3)
        let en = await wikipediaLang(query: query, lang: "en", limit: 2)
        return hu + en
    }

    private static func wikipediaLang(query: String, lang: String, limit: Int) async -> [WebSearchSnippet] {
        guard let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "https://\(lang).wikipedia.org/w/api.php?action=query&list=search&srsearch=\(q)&format=json&srlimit=5") else {
            return []
        }
        struct SearchHit: Decodable { var title: String }
        struct SearchQuery: Decodable { var search: [SearchHit]? }
        struct SearchResp: Decodable { var query: SearchQuery? }
        var req = URLRequest(url: searchURL)
        req.timeoutInterval = 15
        // Azonosító fejléc: a Wikipédia a jelöletlen szkript-forgalmat
        // tiltja (403) — az app saját nevében kér, ahogy az API-szabály kéri.
        req.setValue("Summit-watch-ask/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(SearchResp.self, from: data),
              let hits = decoded.query?.search, !hits.isEmpty else {
            return []
        }
        let titles = hits.prefix(limit).map { $0.title }
        guard let t = titles.joined(separator: "|").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let extURL = URL(string: "https://\(lang).wikipedia.org/w/api.php?action=query&prop=extracts&exintro&explaintext&titles=\(t)&format=json") else {
            return []
        }
        var ereq = URLRequest(url: extURL)
        ereq.timeoutInterval = 15
        ereq.setValue("Summit-watch-ask/1.0", forHTTPHeaderField: "User-Agent")
        guard let (edata, eresp) = try? await URLSession.shared.data(for: ereq),
              (eresp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: edata) as? [String: Any],
              let pages = (json["query"] as? [String: Any])?["pages"] as? [String: Any] else {
            return []
        }
        var out: [WebSearchSnippet] = []
        for title in titles {
            if let page = pages.values.compactMap({ $0 as? [String: Any] })
                .first(where: { ($0["title"] as? String) == title }),
               let extract = page["extract"] as? String, !extract.isEmpty {
                out.append(WebSearchSnippet(title: title, extract: String(extract.prefix(1_500))))
            }
        }
        return out
    }

}
