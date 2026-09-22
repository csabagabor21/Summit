import Foundation

// MARK: - UI items (used by FeedView)
struct GradeItem: Identifiable, Hashable {
    let id: String
    let subject: String
    let value: Int
    let valueText: String
    let date: Date
    let teacher: String
    let type: String
    let weight: Int
    var topic: String = "" // Tema — mire kapta a jegyet (API: Tema)
    /// A Tema is hordozhat nyers HTML-t — kijelzéshez a tisztított változat.
    var plainTopic: String { HomeworkPlain.text(from: topic) }
}

/// Valós százalék a jegy szövegeiből: a tanár gyakran beleírja
/// ("85%", "Témazáró 72%"). Nincs kitalált érték — ha egyik mezőben
/// sincs explicit %, nil (a kártya ilyenkor nem mutat %sort a jegy
/// értékéből számolt kamuszám helyett).
enum GradePercent {
    static func parse(valueText: String, topic: String, type: String) -> Int? {
        for field in [valueText, topic, type] {
            if let p = firstPercent(in: field) { return p }
        }
        return nil
    }

    private static func firstPercent(in s: String) -> Int? {
        guard let rx = try? NSRegularExpression(pattern: "(\\d{1,3})\\s*%") else { return nil }
        let ns = s as NSString
        for m in rx.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            if m.numberOfRanges > 1, let v = Int(ns.substring(with: m.range(at: 1))), (0...100).contains(v) {
                return v
            }
        }
        return nil
    }
}
struct LessonItem: Identifiable, Hashable {
    let id: String
    let subject: String
    let room: String
    let start: Date
    let end: Date
    let teacher: String
    let index: String
    var isSubstituted: Bool = false
    var isCancelled: Bool = false
    var originalTeacher: String? = nil
    /// Firka-minta: a KRÉTA a fájlokat az órarendi elemre teszi
    /// (`OrarendElemek[].Csatolmanyok: [{Uid, Nev}]`), nem a házi-payloadba.
    var attachments: [AttachmentItem] = []
    /// Közvetlen kapocs a házira (`OrarendElemek[].HaziFeladatUid`) —
    /// a tárgy+nap heurisztikánál biztosabb illesztés.
    var haziFeladatUid: String? = nil
    func withAttachments(_ a: [AttachmentItem]) -> LessonItem {
        var c = self; c.attachments = a; return c
    }

    var substitutionLabel: String? {
        if isCancelled { return "Elmarad" }
        if isSubstituted { return "Helyettesítés" }
        return nil
    }
}
struct HomeworkItem: Identifiable, Hashable {
    let id: String
    let subject: String
    let title: String
    let deadline: Date
    let teacher: String
    let isDone: Bool
    /// KRÉTA-csatolmányok (PDF, kép, stb.) — a részlet-végpontból jön.
    var attachments: [AttachmentItem] = []
    /// A KRÉTA Szoveg mezője gyakran nyers HTML — ez a tagektől tisztított,
    /// egy soros előnézetekhez való változat.
    var plainTitle: String { HomeworkPlain.text(from: title) }
    func withAttachments(_ a: [AttachmentItem]) -> HomeworkItem {
        var c = self; c.attachments = a; return c
    }
}

/// KRÉTA-csatolmány (házi, dolgozat, üzenet): megjeleníthető/letölthető fájl.
struct AttachmentItem: Identifiable, Hashable {
    let id: String
    let name: String
    let size: Int?
    let mime: String?
    var ext: String {
        let e = (name as NSString).pathExtension.lowercased()
        return e.isEmpty ? (mime?.contains("pdf") == true ? "pdf" : "") : e
    }
    var isPDF: Bool { ext == "pdf" }
    var symbol: String {
        switch ext {
        case "pdf": return "doc.richtext.fill"
        case "jpg", "jpeg", "png", "heic", "webp", "gif": return "photo.fill"
        case "doc", "docx", "odt": return "doc.text.fill"
        case "xls", "xlsx", "ods": return "tablecells.fill"
        case "ppt", "pptx": return "rectangle.on.rectangle.fill"
        case "zip", "rar", "7z": return "archivebox.fill"
        case "mp4", "mov": return "film.fill"
        default: return "paperclip"
        }
    }
    var sizeText: String? {
        guard let size, size > 0 else { return nil }
        if size < 1024 { return "\(size) B" }
        if size < 1024 * 1024 { return "\(size / 1024) KB" }
        return String(format: "%.1f MB", Double(size) / 1024 / 1024)
    }
}

/// Türelmes csatolmány-kinyerés nyers KRÉTA-JSON-ből (lista-elem vagy
/// részlet-payload). A kulcsnevek végpontonként eltérnek (Csatolmanyok,
/// CsatoltFajlok, Mellekletek, Attachments…), ezért heurisztikával keres.
enum KretaAttachmentParser {
    static func attachments(from data: Data) -> [AttachmentItem] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        if let dict = json as? [String: Any] { return fromDict(dict) }
        if let arr = json as? [Any] { return arr.flatMap { ($0 as? [String: Any]).map(fromDict) ?? [] } }
        return []
    }

    /// Lista-payloadból Uid → csatolmány térkép (a lista-elemek maguk is
    /// hordozhatnak csatolmánylistát).
    static func attachmentsByUid(from data: Data) -> [String: [AttachmentItem]] {
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [:] }
        var out: [String: [AttachmentItem]] = [:]
        for el in arr {
            guard let d = el as? [String: Any] else { continue }
            let uid = string(d, keys: ["Uid", "ID", "Id", "azon", "Azonosito"])
            let atts = fromDict(d)
            if let uid, !atts.isEmpty { out[uid] = atts }
        }
        return out
    }

    /// Csatolmány-gyanús kulcs? (lista-elem vagy részlet-payload).
    /// A végpontok kulcsnevei szórnak (Csatolmanyok, CsatoltFajlok,
    /// Mellekletek, Attachments…), ezért heurisztika.
    static func keyLooksLikeAttachments(_ key: String) -> Bool {
        let lk = key.lowercased()
        // `IsCsatolasEngedelyezes` csak engedély-flag (csatolhat-e a diák
        // beadandót), nem fájllista — kizárjuk, különben minden házi
        // "csatolmányosnak" látszana a diagnosztikában.
        if lk == "iscsatolasengedelyezes" { return false }
        return lk.contains("csatol") || lk.contains("mellek") || lk.contains("attach")
            || lk.contains("fajl") || lk == "files" || lk.contains("dokument")
    }

    /// PII-mentes érték-összefoglaló a csatolmány-gyanús kulcsokról:
    /// csak típus + darabszám + belső kulcsnevek (pl.
    /// `Csatolmanyok=arr[2]{Uid,Nev}`), fájlnevek és tartalom nélkül.
    /// Diagnosztikába való — megmutatja, milyen alakban jön a fájllista.
    static func attachmentValueSummary(in d: [String: Any]) -> [String] {
        d.compactMap { (k, v) in
            guard keyLooksLikeAttachments(k) else { return nil }
            if let arr = v as? [Any] {
                if let first = arr.first(where: { $0 is [String: Any] }) as? [String: Any] {
                    return "\(k)=arr[\(arr.count)]{\(first.keys.sorted().joined(separator: ","))}"
                }
                let types = Set(arr.map { el -> String in
                    if el is String { return "str" }
                    if el is NSNumber { return "num" }
                    return "?"
                })
                return "\(k)=arr[\(arr.count)]<\(types.sorted().joined(separator: ","))>"
            }
            if let sub = v as? [String: Any] {
                return "\(k)=dict{\(sub.keys.sorted().joined(separator: ","))}"
            }
            return "\(k)=\(type(of: v))"
        }
    }

    private static func fromDict(_ d: [String: Any]) -> [AttachmentItem] {
        for (k, v) in d {
            guard keyLooksLikeAttachments(k), let arr = v as? [Any] else { continue }
            let items = arr.compactMap { ($0 as? [String: Any]).flatMap(item(from:)) }
            if !items.isEmpty { return items }
        }
        // Üzenet-részlet (ekreta-docs-v3): a `csatolmanyok` nem a gyökérben,
        // hanem a beágyazott `uzenet` objektumban lakik — oda is benézünk.
        for (_, v) in d {
            if let sub = v as? [String: Any] {
                let items = fromDict(sub)
                if !items.isEmpty { return items }
            }
        }
        return []
    }

    private static func item(from d: [String: Any]) -> AttachmentItem? {
        guard let name = string(d, keys: ["Nev", "Name", "FileName", "FajlNev", "Cim", "Targy", "OriginalName"]) else { return nil }
        return AttachmentItem(
            id: string(d, keys: ["Uid", "ID", "Id", "azon", "Azonosito", "FileId"]) ?? UUID().uuidString,
            name: name,
            size: int(d, keys: ["Meret", "Size", "MeretByte", "FileSize", "Hossz"]),
            mime: string(d, keys: ["Tipus", "MimeType", "ContentType", "FileType", "Kiterjesztes"])
        )
    }

    /// Üzenet-törzs kinyerése részlet-payloadból (több kulcsvariáns).
    static func messageBody(from data: Data) -> String? {
        guard let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        // Beágyazott uzenet-objektum is lehet.
        let scopes: [[String: Any]] = [d] + ((d["uzenet"] as? [String: Any]).map { [$0] } ?? [])
        for scope in scopes {
            if let s = string(scope, keys: ["Szoveg", "Tartalom", "Body", "Text", "Leiras", "Message", "content"]) {
                return s
            }
        }
        return nil
    }

    private static func string(_ d: [String: Any], keys: [String]) -> String? {
        for k in keys {
            if let s = d[k] as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return s }
            if let n = d[k] as? Int { return String(n) }
        }
        // Kisbetűsített kulcs-tolerancia (az üzenet-végpont `azonosito`/
        // `fajlNev` kulcsai csupa kisbetűsek, az érték számmal is jöhet).
        let lower = Dictionary(uniqueKeysWithValues: d.map { ($0.key.lowercased(), $0.value) })
        for k in keys {
            let v = lower[k.lowercased()]
            if let s = v as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return s }
            if let n = v as? Int { return String(n) }
            if let n = v as? Int64 { return String(n) }
        }
        return nil
    }

    private static func int(_ d: [String: Any], keys: [String]) -> Int? {
        for k in keys {
            if let n = d[k] as? Int { return n }
            if let n = d[k] as? Int64 { return Int(n) }
            if let s = d[k] as? String, let n = Int(s) { return n }
        }
        // Kisbetűsített kulcs-tolerancia (a stringgel szimmetrikusan).
        let lower = Dictionary(uniqueKeysWithValues: d.map { ($0.key.lowercased(), $0.value) })
        for k in keys {
            let v = lower[k.lowercased()]
            if let n = v as? Int { return n }
            if let n = v as? Int64 { return Int(n) }
            if let s = v as? String, let n = Int(s) { return n }
        }
        return nil
    }
}

/// Letöltött bájtok őrsége: a KRÉTA hibaoldala (JSON/HTML) nem fájl.
/// A QuickLook egy `.pdf` néven mentett hibaoldaltól csak üres nézetet adna
/// ("nem nyílik meg a PDF") — ezért az ilyen választ a kliens elutasítja,
/// és a következő útvonallal próbálkozik / hibát jelez.
enum KretaDownloadSniff {
    static func looksLikeFileData(_ data: Data, fileName: String) -> Bool {
        guard !data.isEmpty else { return false }
        // Vezető whitespace átugrása (a JSON-hiba gyakran tördelt).
        var i = data.startIndex
        while i < data.endIndex {
            let b = data[i]
            if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D { i = data.index(after: i) } else { break }
        }
        guard i < data.endIndex else { return false }
        switch data[i] {
        case 0x7B /* { */, 0x5B /* [ */, 0x3C /* < */:
            return false // JSON-hiba / HTML-hibaoldal — biztosan nem fájl
        default:
            break
        }
        // Ismert bináris mágiák: PDF (%PDF), ZIP (PK: docx/xlsx/pptx),
        // JPEG, PNG, GIF, RAR, 7z, OLE (doc/xls), BMP, RIFF (WebP), ftyp (MP4/MOV).
        func at(_ k: Int) -> UInt8? {
            let idx = data.index(i, offsetBy: k, limitedBy: data.endIndex)
            return idx.flatMap { $0 < data.endIndex ? data[$0] : nil }
        }
        if at(0) == 0x25 && at(1) == 0x50 && at(2) == 0x44 && at(3) == 0x46 { return true } // %PDF
        if at(0) == 0x50 && at(1) == 0x4B { return true } // PK
        if at(0) == 0xFF && at(1) == 0xD8 { return true } // JPEG
        if at(0) == 0x89 && at(1) == 0x50 && at(2) == 0x4E && at(3) == 0x47 { return true } // PNG
        if at(0) == 0x47 && at(1) == 0x49 && at(2) == 0x46 { return true } // GIF
        if at(0) == 0x52 && at(1) == 0x61 && at(2) == 0x72 { return true } // RAR
        if at(0) == 0x37 && at(1) == 0x7A { return true } // 7z
        if at(0) == 0xD0 && at(1) == 0xCF && at(2) == 0x11 && at(3) == 0xE0 { return true } // OLE
        if at(0) == 0x42 && at(1) == 0x4D { return true } // BMP
        if at(0) == 0x52 && at(1) == 0x49 && at(2) == 0x46 && at(3) == 0x46 { return true } // RIFF
        if at(4) == 0x66 && at(5) == 0x74 && at(6) == 0x79 && at(7) == 0x70 { return true } // ftyp
        // Ritka formátumokat nem dobunk el: ami nem JSON/HTML-hibaoldal, mehet.
        return true
    }
}

/// Házi–óra csatolás egyetlen szabálya, mindkét irányba:
/// CSAK az az óra kapja meg a házit, amelyik napjára a határidő esik.
/// Nincs tárgy-alapú fallback — az egyetlen házit is minden órára ráírná.
enum HomeworkMatcher {
    static func homework(for lesson: LessonItem, in homeworks: [HomeworkItem], calendar: Calendar = .current) -> HomeworkItem? {
        homeworks.first {
            SubjectMatcher.same($0.subject, lesson.subject)
            && calendar.isDate($0.deadline, inSameDayAs: lesson.start)
        }
    }
    static func lesson(for homework: HomeworkItem, in lessons: [LessonItem], calendar: Calendar = .current) -> LessonItem? {
        lessons.first {
            SubjectMatcher.same($0.subject, homework.subject)
            && calendar.isDate($0.start, inSameDayAs: homework.deadline)
        }
    }
}

/// Órarendi csatolmányok befüzése a házikba (Firka-minta): a KRÉTA a
/// fájlokat az órarendi elemre (`OrarendElemek[].Csatolmanyok`) teszi, a
/// házi-payloadban gyakran semmi sincs — ezért a Feladatok tab a
/// határidő-napi, azonos tárgyú óra fájljait is megmutatja.
/// Unió id alapján: a házi saját csatolmányai maradnak elöl, ismétlődés nincs.
enum HomeworkLessonAttachments {
    static func merged(_ homeworks: [HomeworkItem], lessons: [LessonItem], calendar: Calendar = .current) -> [HomeworkItem] {
        homeworks.map { hw in
            // 1) Biztos kapocs: az óra HaziFeladatUid-ja közvetlenül mutat
            //    a házira (a fájl a feladás hetének óráján is lehet, nem csak
            //    a határidő napján). 2) Fallback: határidő-napi, azonos tárgyú óra.
            var found: [AttachmentItem] = []
            var seen = Set(hw.attachments.map(\.id))
            for lesson in lessons {
                let linked = lesson.haziFeladatUid == hw.id
                    || (SubjectMatcher.same(lesson.subject, hw.subject)
                        && calendar.isDate(lesson.start, inSameDayAs: hw.deadline))
                guard linked else { continue }
                for att in lesson.attachments where seen.insert(att.id).inserted {
                    found.append(att)
                }
            }
            guard !found.isEmpty else { return hw }
            return hw.withAttachments(hw.attachments + found)
        }
    }
}

/// Lejárt határidő: a határidő napja már elmúlt (ma éjfélnél korábbi).
/// Az ilyen házi lekerül a főoldalról — a Feladatok tabon megmarad.
enum HomeworkExpiry {
    static func isExpired(_ h: HomeworkItem, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        h.deadline < calendar.startOfDay(for: now)
    }
}

/// Lejárt dolgozat: a napja már elmúlt (ma éjfélnél korábbi).
/// A mai dolgozat egész nap élő — csak a tegnapi és régebbi számít lejártnak,
/// az ilyen a Dolgozatok szegmensből a Készbe kerül.
enum ExamExpiry {
    static func isExpired(_ e: ExamItem, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        e.date < calendar.startOfDay(for: now)
    }
}

/// Dolgozat–óra csatolás:
/// ha a KRÉTA tudja, hányadik órára szól (OrarendiOraOraszama), CSAK az az
/// óra kapja meg — különben minden aznapi, azonos tárgyú órára ráíródna.
/// Óraszám nélküli dolgozatra marad a régi nap-alapú viselkedés.
enum ExamMatcher {
    static func exam(for lesson: LessonItem, in exams: [ExamItem], calendar: Calendar = .current) -> ExamItem? {
        let sameDay = exams.filter {
            SubjectMatcher.same($0.subject, lesson.subject)
            && calendar.isDate($0.date, inSameDayAs: lesson.start)
        }
        if let pinned = sameDay.first(where: { $0.lessonIndex != nil && Int(lesson.index) == $0.lessonIndex }) {
            return pinned
        }
        if let unpinned = sameDay.first(where: { $0.lessonIndex == nil }) {
            return unpinned
        }
        // Fallback, hogy a dolgozat sose tűnjön el némán az órarendről:
        // - ha aznapra egyetlen dolgozat van ebből a tárgyból, az biztosan ide tartozik;
        // - ha az óra sorszáma nem számozott ("-"), az óraszámos tűzés nem dönthető el,
        //   ilyenkor az aznapi elsőt mutatjuk a semmi helyett.
        // Több aznapi, eltérő óraszámú dolgozatnál marad a szigorú tűzés
        // (félrecsatolás helyett inkább ne színezzünk).
        if sameDay.count == 1 { return sameDay[0] }
        if Int(lesson.index) == nil { return sameDay.first }
        return nil
    }
}

/// KRÉTA HTML → stílusos szegmensek (félkövér/dőlt/aláhúzott/áthúzott/link/címsor).
/// Szándékosan kézi parser WebKit nélkül: az NSAttributedString HTML-importja
/// SwiftUI body-ból hívva AttributeGraph-crash-t (SIGABRT) okozott, amit
/// try? sem véd ki. Ez tiszta string-művelet, bárhonnan biztonságos.
struct HomeworkSegment {
    var text: String
    var bold = false
    var italic = false
    var underline = false
    var strike = false
    var heading = false
    var link: URL?
}
enum HomeworkRich {
    static func segments(from html: String) -> [HomeworkSegment] {
        let plainFallback: [HomeworkSegment] = {
            let t = HomeworkPlain.text(from: html)
            return t.isEmpty ? [] : [HomeworkSegment(text: t)]
        }()
        guard html.contains("<") else { return plainFallback }
        // Magányos "<" (pl. "a < b") nem tag — entitássá védjük
        let src = html.replacingOccurrences(of: "<(?![a-zA-Z/!?])", with: "&lt;", options: .regularExpression)
        guard let re = try? NSRegularExpression(pattern: "<!--.*?-->|<[^>]*>|[^<]+", options: [.dotMatchesLineSeparators]) else {
            return plainFallback
        }
        let ns = src as NSString
        let full = NSRange(location: 0, length: ns.length)
        var segs: [HomeworkSegment] = []
        var buf = ""
        var bold = 0, italic = 0, underline = 0, strike = 0, heading = 0
        var link: URL?
        var skipDepth = 0 // <style>/<script> tartalma nem szöveg
        var pendingBreaks = 0
        var bullet = false

        func bump(_ c: inout Int, _ closing: Bool) {
            if closing { c = max(0, c - 1) } else { c += 1 }
        }
        func flush() {
            if buf.isEmpty { return } // semmi nem gyűlt össze — nincs mit lezárni
            if buf.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Csak szóköz: sortörés/szöveg elején eldobjuk, szavak közt egyre tömörítjük
                if pendingBreaks > 0 || segs.isEmpty { buf = ""; bullet = false; return }
                buf = " "
            }
            var t = buf; buf = ""
            if bullet { t = "• " + t; bullet = false }
            if pendingBreaks > 0 { t = String(repeating: "\n", count: min(pendingBreaks, 2)) + t; pendingBreaks = 0 }
            segs.append(HomeworkSegment(text: t, bold: bold > 0, italic: italic > 0,
                                        underline: underline > 0, strike: strike > 0,
                                        heading: heading > 0, link: link))
        }
        func tagName(_ tok: String) -> (closing: Bool, name: String) {
            var t = String(tok.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            var closing = false
            if t.hasPrefix("/") { closing = true; t = String(t.dropFirst()).trimmingCharacters(in: .whitespaces) }
            if t.hasPrefix("!") || t.hasPrefix("?") { return (false, "") }
            let name = String(t.prefix(while: { $0.isLetter || $0.isNumber }).lowercased())
            return (closing, name)
        }
        func attr(_ tok: String, _ key: String) -> String? {
            guard let are = try? NSRegularExpression(pattern: key + "\\s*=\\s*\"([^\"]*)\"|" + key + "\\s*=\\s*'([^']*)'", options: .caseInsensitive) else { return nil }
            let nt = tok as NSString
            guard let m = are.firstMatch(in: tok, range: NSRange(location: 0, length: nt.length)) else { return nil }
            for i in 1..<m.numberOfRanges {
                let r = m.range(at: i)
                if r.location != NSNotFound { return nt.substring(with: r) }
            }
            return nil
        }

        for m in re.matches(in: src, range: full) {
            let tok = ns.substring(with: m.range)
            if tok.hasPrefix("<") {
                let (closing, name) = tagName(tok)
                switch name {
                case "style", "script", "head":
                    if closing { skipDepth = max(0, skipDepth - 1) } else { skipDepth += 1 }
                case "": break
                case "br", "hr":
                    if skipDepth == 0 { flush(); pendingBreaks = max(pendingBreaks, 1) }
                case "p", "div", "h1", "h2", "h3", "h4", "h5", "h6",
                     "blockquote", "section", "article", "header", "footer",
                     "table", "tr", "ul", "ol", "dl", "pre":
                    if skipDepth == 0 {
                        flush() // előbb kiírjuk (záráskor még az aktuális stílussal), aztán lép a számláló
                        if name.hasPrefix("h") { bump(&heading, closing) }
                        pendingBreaks = max(pendingBreaks, 2)
                    }
                case "li":
                    if skipDepth == 0, !closing {
                        flush(); pendingBreaks = max(pendingBreaks, 1); bullet = true
                    }
                case "b", "strong": if skipDepth == 0 { flush(); bump(&bold, closing) }
                case "i", "em": if skipDepth == 0 { flush(); bump(&italic, closing) }
                case "u", "ins": if skipDepth == 0 { flush(); bump(&underline, closing) }
                case "s", "strike", "del": if skipDepth == 0 { flush(); bump(&strike, closing) }
                case "a":
                    if skipDepth == 0 {
                        flush()
                        if closing { link = nil }
                        else if let h = attr(tok, "href"), let u = URL(string: h),
                                let s = u.scheme?.lowercased(), s == "http" || s == "https" { link = u }
                        else { link = nil }
                    }
                case "img":
                    if skipDepth == 0, !closing {
                        flush()
                        let a = attr(tok, "alt") ?? ""
                        buf = a.isEmpty ? "[kép]" : "[kép: \(a)]"
                        flush()
                    }
                default: break // span/font/szín: szándékosan figyelmen kívül (sötét mód!)
                }
            } else if skipDepth == 0 {
                var t = HomeworkPlain.decodeEntities(tok)
                t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                buf += t
            }
        }
        flush()
        // Szélső sortörések levágása
        if !segs.isEmpty {
            var f = segs[0]
            let tf = String(f.text.drop(while: { $0 == "\n" }))
            if tf.isEmpty { segs.removeFirst() } else { f.text = tf; segs[0] = f }
        }
        if !segs.isEmpty {
            var l = segs[segs.count - 1]
            while l.text.hasSuffix("\n") { l.text = String(l.text.dropLast()) }
            if l.text.isEmpty { segs.removeLast() } else { segs[segs.count - 1] = l }
        }
        return segs
    }
}

/// KRÉTA HTML-takarítás: blokk-tagek → sortörés, többi tag eldobva,
/// entitások dekódolva. Tiszta Foundation, UI-független.
enum HomeworkPlain {
    static func text(from html: String) -> String {
        guard html.contains("<") || html.contains("&") else {
            return normalizeWhitespace(html)
        }
        var s = html
        s = s.replacingOccurrences(
            of: "(?i)<\\s*(?:p|div|br|li|ul|ol|tr|h[1-6]|blockquote|section|article)[^>]*/?>",
            with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(
            of: "(?i)</\\s*(?:p|div|li|ul|ol|tr|h[1-6]|blockquote|section|article)[^>]*>",
            with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        s = decodeEntities(s)
        return normalizeWhitespace(s)
    }

    static func decodeEntities(_ s: String) -> String {
        let named: [String: String] = [
            "nbsp": " ", "amp": "&", "lt": "<", "gt": ">", "quot": "\"",
            "apos": "'", "hellip": "…", "ndash": "–", "mdash": "—",
            "laquo": "«", "raquo": "»", "szlig": "ß"
        ]
        guard let re = try? NSRegularExpression(pattern: "&(#x[0-9a-fA-F]+|#\\d+|[a-zA-Z]+);") else { return s }
        let ns = s as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            let body = ns.substring(with: m.range(at: 1))
            var rep: String?
            if body.hasPrefix("#x") || body.hasPrefix("#X") {
                if let v = UInt32(body.dropFirst(2), radix: 16), let sc = Unicode.Scalar(v) { rep = String(sc) }
            } else if body.hasPrefix("#") {
                if let v = UInt32(body.dropFirst()), let sc = Unicode.Scalar(v) { rep = String(sc) }
            } else {
                rep = named[body]
            }
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            out += rep ?? ns.substring(with: m.range)
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    static func normalizeWhitespace(_ s: String) -> String {
        // Előnézetekhez: üres sorok eldobva, minden tartalmi sor külön sorban
        return s.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
struct AbsenceItem: Identifiable, Hashable {
    let id: String
    let subject: String
    let date: Date
    let type: String // megjelenítendő név (pl. "Orvosi igazolás", "Hiányzás")
    /// Igazolt-e: csak akkor igaz, ha van rögzített igazolás, és az nem
    /// "igazolatlan". Hiányzó igazolás (friss, feldolgozatlan tétel) = hamis,
    /// mert a KRÉTA-ban is addig igazolatlannak számít, amíg nem igazolják.
    let isJustified: Bool
    let delay: Int?
}
struct MessageItem: Identifiable, Hashable {
    let id: String
    let sender: String
    let subject: String
    let date: Date
    let isRead: Bool
    /// Részlet-törzs (listában üres, a detail-hívás tölti).
    var body: String = ""
    var attachments: [AttachmentItem] = []
    var plainBody: String { HomeworkPlain.text(from: body) }
    func withDetail(body: String, attachments: [AttachmentItem]) -> MessageItem {
        var c = self; c.body = body; c.attachments = attachments; return c
    }
}
struct ExamItem: Identifiable, Hashable {
    let id: String
    let subject: String
    let date: Date
    let mode: String
    let description: String
    var teacher: String = ""
    var lessonIndex: Int? = nil // hányadik óra (a hivatalos app is írja: "1. óra")
    /// Mikor jelentették be (KRÉTA: BejelentesDatuma) — a hivatalos app ezt is mutatja
    var announcedDate: Date? = nil
    /// Melyik osztály/csoportnak szól (KRÉTA: OsztalyCsoport.Nev, pl. "12.HBS - Technikum")
    var groupName: String = ""
    var attachments: [AttachmentItem] = []
    func withAttachments(_ a: [AttachmentItem]) -> ExamItem {
        var c = self; c.attachments = a; return c
    }
    /// A Temaja-leírás gyakran nyers HTML — kijelzéshez a tisztított változat.
    var plainDescription: String { HomeworkPlain.text(from: description) }
}

/// KRÉTA nyers számonkérés-mód (pl. "szobeli_felelet") → szép magyar név.
/// Ismeretlen kódra snake_case-ből csinálunk olvashatót, üresre fallback.
func friendlyExamMode(_ raw: String) -> String {
    let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.isEmpty { return "Számonkérés" }
    let key = t.lowercased()
    let map: [String: String] = [
        "szobeli_felelet": "Szóbeli felelet",
        "szobeli_feleles": "Szóbeli felelet",
        "szobeli": "Szóbeli",
        "irasbeli_dolgozat": "Írásbeli dolgozat",
        "irasbeli_temazaro_dolgozat": "Írásbeli témazáró dolgozat",
        "irasbeli": "Írásbeli",
        "szobeli_temazaro_dolgozat": "Szóbeli témazáró",
        "temazaro": "Témazáró",
        "temazaro_dolgozat": "Témazáró",
        "dolgozat": "Dolgozat",
        "ropdolgozat": "Röpdolgozat",
        "irasbeli_ropdolgozat": "Írásbeli röpdolgozat",
        "felmeres": "Felmérés",
        "beszamolo": "Beszámoló",
        "gyakorlati": "Gyakorlati",
        "gyakorlati_feladat": "Gyakorlati feladat",
        "projektmunka": "Projektmunka",
        "vizsga": "Vizsga",
        "szamonkeres": "Számonkérés",
        "hazifeladat": "Házi feladat",
        "oral": "Órai munka",
        "orai_munka": "Órai munka",
    ]
    if let m = map[key] { return m }
    let words = t.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
    return words.prefix(1).uppercased() + words.dropFirst().lowercased()
}

/// KRÉTA nyers feljegyzés-típus (pl. "ElektronikusUzenet") → szép magyar név.
/// A KRÉTA a típust kód-szerűen, egybeírva adja — ezt tilos nyersen
/// kipillezni ("ElektronikusUzenet"). Ismeretlen kódra camelCase/snake_case
/// széttördeléssel csinálunk olvashatót, üresre fallback.
func friendlyNoteType(_ raw: String) -> String {
    let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.isEmpty { return "Feljegyzés" }
    let map: [String: String] = [
        "elektronikusuzenet": "Elektronikus üzenet",
        "elektronikus uzenet": "Elektronikus üzenet",
        "dicseret": "Dicséret",
        "felmentes": "Felmentés",
        "tajekoztatas": "Tájékoztatás",
        "figyelmeztetes": "Figyelmeztetés",
        "figyelmeztetés": "Figyelmeztetés",
        "megrovás": "Megrovás",
        "megrovas": "Megrovás",
    ]
    let folded = t.lowercased().folding(options: .diacriticInsensitive, locale: .current)
    if let m = map[folded] ?? map[t.lowercased()] { return m }
    // camelCase/PascalCase széttördelés: "ValamiUzenet" → "Valami Uzenet"
    var out = ""
    for (i, ch) in t.enumerated() {
        if i > 0 && ch.isUppercase {
            let prev = t[t.index(t.startIndex, offsetBy: i - 1)]
            if prev.isLowercase { out += " " }
        }
        out.append(ch)
    }
    out = out.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
    return out.prefix(1).uppercased() + out.dropFirst()
}

// MARK: - Kreta date helper — handles KRÉTA's mixed formats (with/without TZ, with/without fractional)
enum KretaDateParser {
    static func parse(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFrac.date(from: s) { return d }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        // Local datetime without TZ — KRÉTA sometimes returns "2026-09-01T08:00:00" or "2026-09-01T08:00:00.0000000"
        let dotTrimmed = s.contains(".") ? String(s.split(separator: ".").first ?? Substring(s)) : s
        let fmts = ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"]
        for fmt in fmts {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone.current
            df.dateFormat = fmt
            if let d = df.date(from: dotTrimmed) { return d }
            if let d = df.date(from: s) { return d }
        }
        return nil
    }
}

// MARK: - DTOs matching real e-KRÉTA JSON (keys are Hungarian)
struct TantargyDTO: Decodable { let Nev: String?; let Uid: String? }
struct OsztalyCsoportDTO: Decodable { let Nev: String?; let Uid: String? }
struct TipusDTO: Decodable {
    let Nev: String?
    let Kod: String?
    let Uid: String?
    /// A BejelentettSzamonkeresek Modja-objektuma Leiras kulcson hozza a
    /// szép magyar módnevet (pl. "Írásbeli témazáró dolgozat"), míg a Nev
    /// a snake_case kód (pl. "irasbeli_temazaro_dolgozat").
    let Leiras: String?
    /// Emberi módnév: Leiras élvez elsőbbséget, utána a Nev-kód barátságosítva.
    var displayName: String {
        let l = (Leiras ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !l.isEmpty { return l }
        return friendlyExamMode((Nev ?? Kod) ?? "")
    }
}

struct KretaGradeDTO: Decodable {
    let Uid: String?
    let Tantargy: TantargyDTO?
    let SzamErtek: Int?
    let SzovegesErtek: String?
    let SulySzazalekErteke: Int?
    let KeszitesDatuma: String?
    let RogzitesDatuma: String?
    let ErtekeloTanarNeve: String?
    let Tipus: TipusDTO?
    let Tema: String?
    func toItem() -> GradeItem {
        return GradeItem(
            id: Uid ?? UUID().uuidString,
            subject: Tantargy?.Nev ?? "Ismeretlen",
            value: SzamErtek ?? 0,
            valueText: SzovegesErtek ?? "\(SzamErtek ?? 0)",
            date: KretaDateParser.parse(KeszitesDatuma ?? RogzitesDatuma) ?? Date(),
            teacher: (ErtekeloTanarNeve ?? "").trimmingCharacters(in: .whitespaces),
            type: Tipus?.Nev ?? "Értékelés",
            weight: SulySzazalekErteke ?? 100,
            topic: (Tema ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

struct KretaLessonDTO: Decodable {
    let Uid: String?
    let Tantargy: TantargyDTO?
    let Oraszam: Int?
    let TanarNeve: String?
    let HelyettesTanarNeve: String?
    let KezdetIdopont: String?
    let VegIdopont: String?
    let TeremNeve: String?
    let Tema: String?
    let Allapot: TipusDTO?
    /// Melyik házihoz tartozik az óra (ekreta-docs: `HaziFeladatUid`) —
    /// a csatolmány-illesztés biztos kapcsa.
    let HaziFeladatUid: String?
    /// Elemenkénti toleráns dekódolás (házi/dolgozat-minta): egy hibás óra
    /// nem nullázza a teljes órarendet — a szigorú tömb-decode helyett.
    static func lenientDTOs(from data: Data) -> [KretaLessonDTO] {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            return (try? JSONDecoder().decode([KretaLessonDTO].self, from: data)) ?? []
        }
        let decoder = JSONDecoder()
        return raw.compactMap { element in
            guard let ed = try? JSONSerialization.data(withJSONObject: element),
                  let dto = try? decoder.decode(KretaLessonDTO.self, from: ed) else { return nil }
            return dto
        }
    }
    static func lenientItems(from data: Data) -> [LessonItem] {
        lenientDTOs(from: data).compactMap { $0.toItem() }
    }
    func toItem() -> LessonItem? {
        guard let tant = Tantargy?.Nev, !tant.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        guard let start = KretaDateParser.parse(KezdetIdopont), let end = KretaDateParser.parse(VegIdopont) else { return nil }
        let room = (TeremNeve ?? "").replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: " terem", with: "", options: .caseInsensitive)
        let allapotNev = (Allapot?.Nev ?? "").lowercased()
        let isCancelled = allapotNev.contains("elmarad")
        let hasSubstitute = (HelyettesTanarNeve != nil && !(HelyettesTanarNeve?.trimmingCharacters(in: .whitespaces).isEmpty ?? true))
        let isSubstituted = !isCancelled && (hasSubstitute || allapotNev.contains("helyettes"))
        let displayTeacher: String
        if isCancelled {
            displayTeacher = (TanarNeve ?? "").trimmingCharacters(in: .whitespaces)
        } else if hasSubstitute {
            displayTeacher = HelyettesTanarNeve!.trimmingCharacters(in: .whitespaces)
        } else {
            displayTeacher = (TanarNeve ?? "").trimmingCharacters(in: .whitespaces)
        }
        return LessonItem(
            id: Uid ?? UUID().uuidString,
            subject: tant,
            room: room.isEmpty ? "-" : room,
            start: start,
            end: end,
            teacher: displayTeacher,
            index: Oraszam.map(String.init) ?? "-",
            isSubstituted: isSubstituted,
            isCancelled: isCancelled,
            originalTeacher: hasSubstitute ? TanarNeve : nil,
            haziFeladatUid: HaziFeladatUid
        )
    }
}

struct KretaHomeworkDTO: Decodable {
    let Uid: String?
    let TantargyNeve: String?
    let Tantargy: TantargyDTO?
    let Szoveg: String?
    let HataridoDatuma: String?
    let FeladasDatuma: String?
    let RogzitesIdopontja: String?
    let FeladoTanarNeve: String?
    let RogzitoTanarNeve: String?
    let IsTanuloHaziFeladatEnabled: Bool?
    let IsMegoldva: Bool?
    /// Uid-k kinyerése a lista-válaszból (refilc: a lista elemei csak
    /// hivatkozások, a tartalom a HaziFeladatok/{uid} részletekből jön).
    /// String és szám Uid-t is elfogad, a hibás elemeket kihagyja.
    static func uids(from data: Data) -> [String] {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        var seen = Set<String>()
        var out: [String] = []
        for el in raw {
            guard let d = el as? [String: Any] else { continue }
            // Azonos kulcskészlet, mint az attachmentsByUid-ban (Uid/ID/
            // azon/Azonosito, string és szám is) — különben a csupasz
            // hivatkozások részlet-lekérése marad el némán.
            var uid: String?
            for k in ["Uid", "ID", "Id", "azon", "Azonosito"] {
                if let s = d[k] as? String, !s.isEmpty { uid = s; break }
                if let n = d[k] as? Int { uid = String(n); break }
                if let n = d[k] as? Int64 { uid = String(n); break }
            }
            if let u = uid, seen.insert(u).inserted { out.append(u) }
        }
        return out
    }
    /// Elemenkénti toleráns dekódolás: a hibás elemeket kihagyja ahelyett,
    /// hogy az egész tömb dekódolása elbukna (és üres lista lenne).
    static func lenientDTOs(from data: Data) -> [KretaHomeworkDTO] {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            return (try? JSONDecoder().decode([KretaHomeworkDTO].self, from: data)) ?? []
        }
        let decoder = JSONDecoder()
        return raw.compactMap { element in
            guard let ed = try? JSONSerialization.data(withJSONObject: element),
                  let dto = try? decoder.decode(KretaHomeworkDTO.self, from: ed) else { return nil }
            return dto
        }
    }
    static func lenientItems(from data: Data) -> [HomeworkItem] {
        lenientDTOs(from: data).map { $0.toItem() }
    }
    /// A lista-elem hordoz-e érdemi tartalmat, vagy csak hivatkozás (Uid),
    /// amihez a HaziFeladatok/{uid} részletet kell lekérni?
    var hasContent: Bool {
        let hasText = !(Szoveg ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasSubject = !(TantargyNeve ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(Tantargy?.Nev ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasText && hasSubject
    }
    func toItem() -> HomeworkItem {
        // Határidő fallback-lánc: a KRÉTA-ban a határidő nem kötelező —
        // ilyenkor a feladás dátuma az igazodási pont, nem a "most".
        let deadline = KretaDateParser.parse(HataridoDatuma)
            ?? KretaDateParser.parse(FeladasDatuma)
            ?? KretaDateParser.parse(RogzitesIdopontja)
            ?? Date()
        return HomeworkItem(
            id: Uid ?? UUID().uuidString,
            subject: (TantargyNeve?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                ?? Tantargy?.Nev ?? "Házi",
            title: (Szoveg ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            deadline: deadline,
            // Valós API-kulcs a RogzitoTanarNeve; FeladoTanarNeve csak fallback
            teacher: (FeladoTanarNeve?.isEmpty == false ? FeladoTanarNeve : RogzitoTanarNeve) ?? "",
            // IsMegoldva a szerver oldali "kész" flag; ha nincs, a régi negálás marad
            isDone: IsMegoldva ?? !(IsTanuloHaziFeladatEnabled ?? true)
        )
    }
}

struct KretaAbsenceDTO: Decodable {
    let Uid: String?
    let Tantargy: TantargyDTO?
    let Datum: String?
    let Tipus: TipusDTO?
    let IgazolasTipusa: TipusDTO?
    let KesesPercben: Int?
    func toItem() -> AbsenceItem {
        func p(_ s: String?) -> Date { KretaDateParser.parse(s) ?? Date() }
        let justification = IgazolasTipusa?.Nev?.trimmingCharacters(in: .whitespacesAndNewlines)
        // Nincs rögzített igazolás (friss tétel) → igazolatlan. A sima
        // típusnév ("Hiányzás") ezután már csak címke, nem státusz.
        let justified = justification != nil && !justification!.lowercased().contains("igazolatlan")
        return AbsenceItem(
            id: Uid ?? UUID().uuidString,
            subject: Tantargy?.Nev ?? "Hiányzás",
            date: p(Datum),
            type: justification ?? Tipus?.Nev ?? "Ismeretlen",
            isJustified: justified,
            delay: KesesPercben
        )
    }
}

/// KRÉTA-postaláda lista-elem (e-Ügyintézés, ekreta-docs-v3 "Get all messages"):
/// `{ azonosito, uzenetAzonosito, uzenetKuldesDatum, uzenetFeladoNev,
///    uzenetFeladoTitulus, uzenetTargy, hasCsatolmany, isElolvasva }`.
/// A lista a törzset nem (vagy csak csonkítva) hozza — azt a
/// `postaladaelemek/{id}` részlet adja (`uzenet.szoveg`).
struct KretaMessageDTO: Decodable {
    let azonosito: Int?
    let uzenetAzonosito: Int?
    let uzenetKuldesDatum: String?
    let uzenetFeladoNev: String?
    let uzenetTargy: String?
    let hasCsatolmany: Bool?
    let isElolvasva: Bool?

    // Régi/eltérő kulcsvariánsok fallback-je (toleráns dekódolás).
    let azon: String?
    let feladoNev: String?
    let targy: String?
    let elkuldve: String?

    enum CodingKeys: String, CodingKey {
        case azonosito, uzenetAzonosito, uzenetKuldesDatum, uzenetFeladoNev,
             uzenetTargy, hasCsatolmany, isElolvasva,
             azon, feladoNev, targy, elkuldve
    }

    /// Elemenkénti toleráns dekódolás: egy hibás elem nem nullázza a listát.
    /// Mivel minden mező opcionális, a teljesen üres (azonosító nélküli)
    /// elemeket itt dobjuk — különben minden szemétből "(nincs tárgy)" sor lenne.
    static func lenientItems(from data: Data) -> [MessageItem] {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            return (try? JSONDecoder().decode([KretaMessageDTO].self, from: data))?.filter { $0.hasIdentity }.map { $0.toItem() } ?? []
        }
        let decoder = JSONDecoder()
        return raw.compactMap { element in
            guard let ed = try? JSONSerialization.data(withJSONObject: element),
                  let dto = try? decoder.decode(KretaMessageDTO.self, from: ed),
                  dto.hasIdentity else { return nil }
            return dto.toItem()
        }
    }

    /// Valódi lista-elem-e (van azonosítója)? A KRÉTA mindig ad `azonosito`-t.
    var hasIdentity: Bool { azonosito != nil || uzenetAzonosito != nil || azon != nil }

    func toItem() -> MessageItem {
        func p(_ s: String?) -> Date { KretaDateParser.parse(s) ?? Date() }
        let id: String
        if let a = azonosito { id = String(a) }
        else if let u = uzenetAzonosito { id = String(u) }
        else { id = azon ?? UUID().uuidString }
        let s = (uzenetFeladoNev ?? feladoNev ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let t = (uzenetTargy ?? targy ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return MessageItem(
            id: id,
            sender: s.isEmpty ? "Üzenet" : s,
            subject: t.isEmpty ? "(nincs tárgy)" : t,
            date: p(uzenetKuldesDatum ?? elkuldve),
            isRead: isElolvasva ?? false
        )
    }
}

/// KRÉTA-postaláda részlet-payload (`postaladaelemek/{id}`, ekreta-docs-v3
/// "Get information about a specific message"): a törzs az `uzenet.szoveg`
/// kulcson jön, a feladó/tárgy/dátum az `uzenet.*` mezőkben ismétlődik.
enum KretaMessageDetail {
    static func parse(from data: Data) -> (body: String, sender: String?, subject: String?, date: Date?)? {
        guard let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let msg = d["uzenet"] as? [String: Any] ?? d
        func s(_ keys: String...) -> String? {
            for k in keys {
                if let v = msg[k] as? String, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return v }
                if let v = d[k] as? String, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return v }
            }
            return nil
        }
        let body = s("szoveg", "Szoveg", "Tartalom", "Body", "Text", "Leiras", "Message", "content") ?? ""
        let atts = KretaAttachmentParser.attachments(from: data)
        guard !body.isEmpty || !atts.isEmpty else { return nil }
        let sender = s("feladoNev", "FeladoNev", "feladoNeve")
        let subject = s("targy", "Targy")
        let date = KretaDateParser.parse(s("kuldesDatum", "KuldesDatum", "elkuldve") ?? "")
        return (body, sender, subject, date)
    }
}

/// Elektronikus feljegyzés (KRÉTA-wide broadcast: az iskola küldi mindenkinek).
/// Forrás: intézeti Ellenőrző API `Sajat/Feljegyzesek` — NEM az e-Ügyintézés
/// postaládája, ezért külön modell és külön fetch-járata van.
struct NoteItem: Identifiable, Hashable {
    let id: String
    let title: String
    let body: String
    let date: Date
    let teacher: String
    let typeName: String
    var plainBody: String { HomeworkPlain.text(from: body) }
    /// A pillben mindig a szép magyar típusnév jelenik meg,
    /// sosem a nyers KRÉTA-kód ("ElektronikusUzenet").
    var displayType: String { friendlyNoteType(typeName) }
}

/// Feljegyzés-DTO: a V3-as kulcsnevek verziónként szórnak (Targy/Cim,
/// Szoveg/Tartalom/Leiras, Datum/KeszitesDatuma, TanarNeve/RogzitoNeve,
/// Tipus.Nev), ezért az Exams-mintára kulcs-toleráns dekódolás.
struct KretaNoteDTO: Decodable {
    let Uid: String?
    let Targy: String?
    let Szoveg: String?
    let Datum: String?
    let TanarNeve: String?
    let Tipus: TipusDTO?

    private struct AnyKey: CodingKey {
        var stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        func s(_ keys: String...) -> String? {
            for k in keys {
                guard let key = AnyKey(stringValue: k) else { continue }
                if let v = try? c.decodeIfPresent(String.self, forKey: key),
                   !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return v }
            }
            return nil
        }
        Uid = s("Uid")
        Targy = s("Targy", "Cim", "Title", "Nev")
        Szoveg = s("Szoveg", "Tartalom", "Leiras", "SzovegesLeiras", "Megjegyzes", "Text", "Body")
        Datum = s("Datum", "Datuma", "KeszitesDatuma", "RogzitesDatuma", "LetrehozasDatuma", "Idopont")
        TanarNeve = s("TanarNeve", "RogzitoNeve", "RogzitoTanarNeve", "FeladoNeve", "KeszitoNeve")
        Tipus = try? c.decodeIfPresent(TipusDTO.self, forKey: AnyKey(stringValue: "Tipus")!)
    }

    static func lenientItems(from data: Data) -> [NoteItem] {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            return (try? JSONDecoder().decode([KretaNoteDTO].self, from: data))?.filter { $0.hasContent }.map { $0.toItem() } ?? []
        }
        let decoder = JSONDecoder()
        return raw.compactMap { element in
            guard let ed = try? JSONSerialization.data(withJSONObject: element),
                  let dto = try? decoder.decode(KretaNoteDTO.self, from: ed),
                  dto.hasContent else { return nil }
            return dto.toItem()
        }
    }

    /// Valódi feljegyzés-e (van azonosítója vagy érdemi tartalma)?
    var hasContent: Bool {
        Uid != nil || !(Targy ?? "").isEmpty || !(Szoveg ?? "").isEmpty
    }

    func toItem() -> NoteItem {
        func p(_ s: String?) -> Date { KretaDateParser.parse(s) ?? Date() }
        let title = (Targy ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let body = (Szoveg ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return NoteItem(
            id: Uid ?? UUID().uuidString,
            title: title.isEmpty ? friendlyNoteType(Tipus?.Nev ?? "") : title,
            body: body,
            date: p(Datum),
            teacher: (TanarNeve ?? "").trimmingCharacters(in: .whitespaces),
            typeName: (Tipus?.Nev ?? "").trimmingCharacters(in: .whitespaces)
        )
    }
}

struct KretaExamDTO: Decodable {
    let Uid: String?
    let TantargyNeve: String?
    let Tantargy: TantargyDTO?
    let Datum: String?
    let Modja: TipusDTO?
    /// Nyers mód string-esethez (ha a Modja nem objektum, hanem kód-szöveg)
    let ModjaRaw: String?
    let Tema: String?
    let RogzitoNeve: String?
    let Oraszam: Int?
    let BejelentesDatuma: String?
    let OsztalyCsoport: OsztalyCsoportDTO?

    // Valós KRÉTA-kulcsok (ekreta-docs-v3 szerint):
    //   Temaja (leírás!), OrarendiOraOraszama (hányadik óra),
    //   Modja: { Nev: kód, Leiras: szép név }, BejelentesDatuma, OsztalyCsoport.Nev.
    // A hivatalos app mutat leírást (pl. MEMORITER-téma) — az "Temaja"
    // kulcson jön, nem "Tema"-n, ezért a régi kód üres leírást adott.
    private struct AnyKey: CodingKey {
        var stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        func s(_ keys: String...) -> String? {
            for k in keys {
                guard let key = AnyKey(stringValue: k) else { continue }
                if let v = try? c.decodeIfPresent(String.self, forKey: key),
                   !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return v }
            }
            return nil
        }
        func i(_ keys: String...) -> Int? {
            for k in keys {
                guard let key = AnyKey(stringValue: k) else { continue }
                if let v = try? c.decodeIfPresent(Int.self, forKey: key) { return v }
                // Az óraszám néha stringként jön ("1") — azt is fogadjuk
                if let vs = try? c.decodeIfPresent(String.self, forKey: key),
                   let v = Int(vs.trimmingCharacters(in: .whitespaces)) { return v }
            }
            return nil
        }
        Uid = s("Uid")
        TantargyNeve = s("TantargyNeve")
        Tantargy = try? c.decodeIfPresent(TantargyDTO.self, forKey: AnyKey(stringValue: "Tantargy")!)
        Datum = s("Datum", "Datuma", "Idopont", "KezdetIdopont")
        Modja = try? c.decodeIfPresent(TipusDTO.self, forKey: AnyKey(stringValue: "Modja")!)
        ModjaRaw = s("Modja", "Mod", "ModNev", "SzamonkeresModja")
        Tema = s("Temaja", "Tema", "Szoveg", "Leiras", "Tematika", "Megjegyzes", "SzovegesLeiras", "FeladatLeiras")
        RogzitoNeve = s("RogzitoTanarNeve", "RogzitoNeve", "TanarNeve", "FeladoTanarNeve", "Rogzitette", "BejelentoNeve")
        Oraszam = i("OrarendiOraOraszama", "Oraszam", "OraSzam")
        BejelentesDatuma = s("BejelentesDatuma")
        OsztalyCsoport = try? c.decodeIfPresent(OsztalyCsoportDTO.self, forKey: AnyKey(stringValue: "OsztalyCsoport")!)
    }

    /// Elemenkénti toleráns dekódolás: egy hibás elem nem ránthatja magával
    /// az egész listát (a házi feladatoknál bevált minta).
    static func lenientDTOs(from data: Data) -> [KretaExamDTO] {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            return (try? JSONDecoder().decode([KretaExamDTO].self, from: data)) ?? []
        }
        let decoder = JSONDecoder()
        return raw.compactMap { element in
            guard let ed = try? JSONSerialization.data(withJSONObject: element),
                  let dto = try? decoder.decode(KretaExamDTO.self, from: ed) else { return nil }
            return dto
        }
    }

    static func lenientItems(from data: Data) -> [ExamItem] {
        // Üres/hibás elemek (se dátum, se tárgy, se leírás) nem kerülnek a listába
        lenientDTOs(from: data).filter { dto in
            !(dto.Datum ?? "").isEmpty
                || !(dto.TantargyNeve ?? "").isEmpty
                || !(dto.Tantargy?.Nev ?? "").isEmpty
                || !(dto.Tema ?? "").isEmpty
        }.map { $0.toItem() }
    }

    func toItem() -> ExamItem {
        func p(_ s: String?) -> Date { KretaDateParser.parse(s) ?? Date() }
        let mode: String
        if let m = Modja {
            mode = m.displayName
        } else {
            mode = friendlyExamMode(ModjaRaw ?? "")
        }
        return ExamItem(
            id: Uid ?? UUID().uuidString,
            subject: (TantargyNeve ?? Tantargy?.Nev ?? "Dolgozat").trimmingCharacters(in: .whitespaces),
            date: p(Datum),
            mode: mode,
            description: (Tema ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            teacher: (RogzitoNeve ?? "").trimmingCharacters(in: .whitespaces),
            lessonIndex: Oraszam,
            announcedDate: KretaDateParser.parse(BejelentesDatuma),
            groupName: (OsztalyCsoport?.Nev ?? "").trimmingCharacters(in: .whitespaces)
        )
    }
}

struct KretaSubjectAvgDTO: Decodable {
    let Tantargy: TantargyDTO?
    let TantargyNeve: String?
    // Atlag lehet null ha nincs jegy — attól még a tárgy létezik
    func subjectName() -> String? {
        if let n = Tantargy?.Nev?.trimmingCharacters(in: .whitespaces), !n.isEmpty { return n }
        if let n = TantargyNeve?.trimmingCharacters(in: .whitespaces), !n.isEmpty { return n }
        return nil
    }
}

// MARK: - Subject matching helper — demo rövid vs KRÉTA hosszú nevek
// Fontos: "Angol nyelv" és "Szakmai angol nyelv" KÜLÖN tantárgy — nem szabad összemosni.
// Ezért a canonical csak a valódi szinonimákat (Matek↔Matematika, Töri↔Történelem) oldja fel,
// a teljes tantárgyneveket (pl. "Szakmai angol nyelv", "Hálózatok I.") érintetlenül hagyja.
enum SubjectMatcher {
    static func canonical(_ s: String) -> String {
        var v = s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: .diacriticInsensitive, locale: .current)
        v = v.replacingOccurrences(of: "  ", with: " ")
        v = v.trimmingCharacters(in: .whitespaces)
        // Csak a bizonyított szinonimák — demo rövidítés vs KRÉTA teljes név
        let alias: [String: String] = [
            "matematika": "matek",
            "matek": "matek",
            "tortenelem": "tori",
            "tori": "tori",
            // Angol: demo "Angol" ↔ KRÉTA "Angol nyelv" — de "Szakmai angol nyelv" külön marad
            "angol nyelv": "angol",
            "angol": "angol",
            "nemet nyelv": "nemet",
            "nemet": "nemet",
        ]
        if let mapped = alias[v] { return mapped }
        return v
    }
    static func same(_ a: String, _ b: String) -> Bool {
        if a.lowercased() == b.lowercased() { return true }
        // folding + alias egyeztetés, de nem tartalmazás-alapú — különben "Szakmai angol nyelv" == "Angol nyelv" lenne
        return canonical(a) == canonical(b)
    }
}

// Helyi demo-backend adatkészlete (hálózat nélkül, az appba csomagolva).
// A KretaClient ebből szolgál ki, ha a user instituteCode-ja "demo" —
// a nézetek ugyanazt a fetchX-kaput hívják, mint éles módban.
enum DemoData {
    /// A 6 órás demo-sablon (tárgy, terem, tanár, óraszám, kezdő óra, perc).
    private static let lessonDefs: [(String, String, String, String, Int, Int)] = [
        ("Matek", "A1", "Kovács J.", "1", 8, 0),
        ("Angol", "B2", "Smith", "2", 9, 0),
        ("Fizika", "C4", "Varga", "3", 10, 0),
        ("Töri", "A3", "Nagy A.", "4", 11, 0),
        ("Kémia", "B1", "Kiss", "5", 12, 0),
        ("Irodalom", "C2", "Szabó K.", "6", 13, 0),
    ]

    /// A demo-sablon csempézése egy tetszőleges [from, to) tartomány
    /// MINDEN napjára — hétvégén is van tanítás (demo). Hétfőnként a 3. óra
    /// elmarad, a 4. helyettesítés — mint eddig. Ezzel a heti lapozás is a
    /// normál fetchTimetable-úton megy, nézet-oldali demo-ág nélkül.
    static func lessons(from: Date, to: Date) -> [LessonItem] {
        let cal = Calendar.current
        let keyFmt = DateFormatter()
        keyFmt.locale = Locale(identifier: "en_US_POSIX")
        keyFmt.dateFormat = "yyyyMMdd"
        var all: [LessonItem] = []
        var day = cal.startOfDay(for: from)
        while day < to {
            let wd = cal.component(.weekday, from: day)
            let isMonday = wd == 2
            let key = keyFmt.string(from: day)
            for (idx, d) in lessonDefs.enumerated() {
                let s = cal.date(byAdding: .hour, value: d.4, to: day)!.addingTimeInterval(Double(d.5 * 60))
                let e = s.addingTimeInterval(45 * 60)
                let isCancelled = isMonday && idx == 2
                let isSubstituted = isMonday && idx == 3
                let teacher = isSubstituted ? "Helyettes Tanár" : d.2
                let original: String? = isSubstituted ? d.2 : (isCancelled ? d.2 : nil)
                all.append(LessonItem(id: "lt\(idx)-\(key)", subject: d.0, room: d.1, start: s, end: e, teacher: teacher, index: d.3, isSubstituted: isSubstituted, isCancelled: isCancelled, originalTeacher: original))
            }
            guard let nxt = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = nxt
        }
        return all.sorted { $0.start < $1.start }
    }
    static func grades() -> [GradeItem] { gradesExpanded().prefix(3).map { $0 } }
    static func gradesExpanded() -> [GradeItem] {
        let now = Date()
        return [
            GradeItem(id: "d1", subject: "Matematika", value: 5, valueText: "5", date: now.addingTimeInterval(-86400*2), teacher: "Kovács J. (0.56)", type: "Témazáró", weight: 200),
            GradeItem(id: "d2", subject: "Matematika", value: 4, valueText: "4", date: now.addingTimeInterval(-86400*9), teacher: "Kovács J. (0.56)", type: "Dolgozat", weight: 100),
            GradeItem(id: "d3", subject: "Matematika", value: 3, valueText: "3", date: now.addingTimeInterval(-86400*14), teacher: "Kovács J. (0.56)", type: "Felelet", weight: 100),
            GradeItem(id: "d4", subject: "Történelem", value: 4, valueText: "4", date: now.addingTimeInterval(-86400*3), teacher: "Nagy A. (0.80)", type: "Témazáró", weight: 200),
            GradeItem(id: "d5", subject: "Történelem", value: 3, valueText: "3", date: now.addingTimeInterval(-86400*11), teacher: "Nagy A. (0.80)", type: "Esszé", weight: 100),
            GradeItem(id: "d6", subject: "Irodalom", value: 5, valueText: "5", date: now.addingTimeInterval(-86400*4), teacher: "Szabó K.", type: "Vers", weight: 100),
            GradeItem(id: "d7", subject: "Irodalom", value: 4, valueText: "4", date: now.addingTimeInterval(-86400*12), teacher: "Szabó K.", type: "Dolgozat", weight: 100),
            GradeItem(id: "d8", subject: "Angol", value: 5, valueText: "5", date: now.addingTimeInterval(-86400*5), teacher: "Smith", type: "Szóbeli", weight: 100),
            GradeItem(id: "d9", subject: "Angol", value: 4, valueText: "4", date: now.addingTimeInterval(-86400*8), teacher: "Smith", type: "Teszt", weight: 100),
            GradeItem(id: "d10", subject: "Fizika", value: 2, valueText: "2", date: now.addingTimeInterval(-86400*6), teacher: "Varga", type: "Dolgozat", weight: 200),
            GradeItem(id: "d11", subject: "Fizika", value: 3, valueText: "3", date: now.addingTimeInterval(-86400*13), teacher: "Varga", type: "Felelet", weight: 100),
            GradeItem(id: "d12", subject: "Kémia", value: 5, valueText: "5", date: now.addingTimeInterval(-86400*7), teacher: "Kiss", type: "Gyakorlat", weight: 100),
        ]
    }
    static func homeworks() -> [HomeworkItem] {
        // Tanítási napokra horgonyozva (ehhez a héthez, hétfő–péntek),
        // hogy az órarend nap-pontos csatolása mindig találjon órát.
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)
        let monday = cal.date(byAdding: .day, value: (weekday == 1 ? -6 : 2 - weekday), to: today)!
        func at(_ weekDay: Int, hour: Int = 16) -> Date { cal.date(byAdding: .day, value: weekDay, to: monday)!.addingTimeInterval(Double(hour*3600)) }
        return [
            HomeworkItem(id: "h1", subject: "Matek", title: "Gyakorló 12-15 (HF)", deadline: at(0), teacher: "Kovács", isDone: false,
                         attachments: [AttachmentItem(id: "demo-pdf-hazi", name: "Gyakorló feladatsor.pdf", size: 24576, mime: "application/pdf")]),
            HomeworkItem(id: "h2", subject: "Angol", title: "Unit 5 vocab + essay 300 szó", deadline: at(0), teacher: "Smith", isDone: false),
            HomeworkItem(id: "h3", subject: "Fizika", title: "Munkafüzet 42.o / 5 feladat", deadline: at(1), teacher: "Varga", isDone: false),
            HomeworkItem(id: "h4", subject: "Töri", title: "Esszé vázlat", deadline: at(1), teacher: "Nagy", isDone: false),
            HomeworkItem(id: "h5", subject: "Irodalom", title: "Olvasónapló 2. fejezet", deadline: at(2), teacher: "Szabó", isDone: false),
            HomeworkItem(id: "h6", subject: "Kémia", title: "Tk. 56.o feladatok", deadline: at(3), teacher: "Kiss", isDone: false),
        ]
    }
    static func absences() -> [AbsenceItem] { [
        AbsenceItem(id: "a1", subject: "Testnevelés", date: Date().addingTimeInterval(-86400*2), type: "Igazolt", isJustified: true, delay: nil),
        AbsenceItem(id: "a2", subject: "Matek", date: Date().addingTimeInterval(-86400*5), type: "Igazolatlan", isJustified: false, delay: nil),
        AbsenceItem(id: "a3", subject: "Angol", date: Date().addingTimeInterval(-86400*8), type: "Késés", isJustified: true, delay: 12),
    ]}
    static func messages() -> [MessageItem] { [
        MessageItem(id: "m1", sender: "Osztályfőnök", subject: "Szülői értekezlet pénteken 17h", date: Date().addingTimeInterval(-3600*5), isRead: false,
                    body: "Kedves Szülők és Diákok! Pénteken 17 órakor szülői értekezletet tartunk az osztályteremben. Megjelenésükre számítunk!",
                    attachments: [AttachmentItem(id: "demo-pdf-uzenet", name: "Szülői értekezlet meghívó.pdf", size: 18432, mime: "application/pdf")]),
        MessageItem(id: "m2", sender: "Igazgatóság", subject: "Tájékoztató — őszi szünet", date: Date().addingTimeInterval(-86400), isRead: true,
                    body: "Tájékoztatjuk a tanulókat, hogy az őszi szünet a kiírt rend szerint alakul. Jó pihenést kívánunk!"),
        MessageItem(id: "m3", sender: "Kovács J.", subject: "Pót ZH időpont", date: Date().addingTimeInterval(-86400*2), isRead: false,
                    body: "A pót ZH időpontja jövő hét szerda, 3. óra. A feladatsor a csatolmányban!"),
    ]}
    /// Elektronikus feljegyzések (KRÉTA-wide broadcast mindenkinek) — demo.
    static func notes() -> [NoteItem] { [
        NoteItem(id: "n1", title: "Dicséret — tanulmányi verseny", body: "Az iskola vezetése dicséretben részesíti az osztály tanulóit a megyei tanulmányi versenyen elért eredményükért.", date: Date().addingTimeInterval(-3600*8), teacher: "Igazgatóság", typeName: "Dicséret"),
        NoteItem(id: "n2", title: "Tájékoztatás — ebédbefizetés", body: "A következő havi ebédbefizetés határideje a hónap 15. napja. Kérjük a határidő betartását!", date: Date().addingTimeInterval(-86400*2), teacher: "Gazdasági iroda", typeName: "Tájékoztatás"),
        NoteItem(id: "n3", title: "Figyelmeztetés — házirend", body: "Felhívjuk a figyelmet a házirend pontos betartására az órák közötti szünetekben.", date: Date().addingTimeInterval(-86400*5), teacher: "Osztályfőnök", typeName: "Figyelmeztetés"),
    ]}
    static func exams() -> [ExamItem] {
        // Tanítási napokra horgonyozva (ehhez a héthez, hétfő–péntek),
        // hogy az órarend nap-pontos csatolása mindig találjon órát.
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)
        let monday = cal.date(byAdding: .day, value: (weekday == 1 ? -6 : 2 - weekday), to: today)!
        func at(_ weekDay: Int, hour: Int = 10) -> Date { cal.date(byAdding: .day, value: weekDay, to: monday)!.addingTimeInterval(Double(hour*3600)) }
        return [
            ExamItem(id: "e1", subject: "Kémia", date: at(0, hour: 10), mode: "Írásbeli", description: "Sav-bázis", teacher: "Kiss"),
            ExamItem(id: "e2", subject: "Matek", date: at(1, hour: 9), mode: "Témazáró", description: "Függvények", teacher: "Kovács J."),
            ExamItem(id: "e3", subject: "Fizika", date: at(2, hour: 10), mode: "Dolgozat", description: "Munka, energia", teacher: "Varga"),
            ExamItem(id: "e4", subject: "Töri", date: at(3, hour: 11), mode: "Témazáró", description: "II. vh.", teacher: "Nagy A."),
            ExamItem(id: "e5", subject: "Angol", date: at(4, hour: 9), mode: "Szóbeli", description: "Unit 5", teacher: "Smith"),
        ]
    }
    /// Today's demo timetable — 6 lessons covering 8:00–13:45, subjects aligned with DemoData homeworks/exams
    static func lessonsToday() -> [LessonItem] {
        let cal = Calendar.current; let base = cal.startOfDay(for: Date())
        var items = lessonDefs.enumerated().map { idx, d in
            let s = cal.date(byAdding: .hour, value: d.4, to: base)!.addingTimeInterval(Double(d.5*60))
            let e = s.addingTimeInterval(45*60)
            return LessonItem(id: "lt\(idx)", subject: d.0, room: d.1, start: s, end: e, teacher: d.2, index: d.3)
        }
        // Hétfőre (weekday 2) legyen 1 elmaradt + 1 helyettesítés — csak ha ma hétfő
        if cal.component(.weekday, from: base) == 2, items.count >= 4 {
            items[2] = LessonItem(id: items[2].id, subject: items[2].subject, room: items[2].room, start: items[2].start, end: items[2].end, teacher: items[2].teacher, index: items[2].index, isSubstituted: false, isCancelled: true, originalTeacher: items[2].teacher)
            items[3] = LessonItem(id: items[3].id, subject: items[3].subject, room: items[3].room, start: items[3].start, end: items[3].end, teacher: "Helyettes Tanár", index: items[3].index, isSubstituted: true, isCancelled: false, originalTeacher: items[3].teacher)
        }
        return items
    }
    static func lessonsExpanded() -> [LessonItem] {
        let cal = Calendar.current
        // Hétfő dátuma ehhez a héthez (weekday 2)
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)
        let mondayOffset = (weekday == 1 ? -6 : 2 - weekday) // hétfőig hátralévő napok
        let monday = cal.date(byAdding: .day, value: mondayOffset, to: today)!
        var all: [LessonItem] = []
        for dayOffset in 0..<5 {
            let dayBase = cal.date(byAdding: .day, value: dayOffset, to: monday)!
            let isMonday = dayOffset == 0
            for (idx, d) in lessonDefs.enumerated() {
                let s = cal.date(byAdding: .hour, value: d.4, to: dayBase)!.addingTimeInterval(Double(d.5*60))
                let e = s.addingTimeInterval(45*60)
                let isCancelled = isMonday && idx == 2
                let isSubstituted = isMonday && idx == 3
                let teacher = isSubstituted ? "Helyettes Tanár" : d.2
                let original: String? = isSubstituted ? d.2 : (isCancelled ? d.2 : nil)
                all.append(LessonItem(id: "lt\(idx)-d\(dayOffset)", subject: d.0, room: d.1, start: s, end: e, teacher: teacher, index: d.3, isSubstituted: isSubstituted, isCancelled: isCancelled, originalTeacher: original))
            }
        }
        return all
    }
}
