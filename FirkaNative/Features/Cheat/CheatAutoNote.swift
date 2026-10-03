import Foundation
import PDFKit
import SwiftUI
import UIKit

// MARK: - NoteCTAButton — egységes, kitöltött jegyzet-gomb
// Kitöltött accent-kapszula fehér szöveggel (az app primary-gomb
// stílusa), sparkles-ikonnal; munka közben pulzáló "Készül…".
struct NoteCTAButton: View {
    let title: String
    let working: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if working {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.85)
                } else {
                    Image(systemName: "sparkles")
                }
                Text(working ? "Készül…" : title)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(Capsule().fill(working ? accent.opacity(0.55) : accent))
            .shadow(color: accent.opacity(0.35), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(working)
    }
}

// MARK: - CheatSheetRef — megnyitandó lap azonosítója sheet-modifierhez
struct CheatSheetRef: Identifiable {
    var id: String
}

// MARK: - CheatAutoNote — jegyzetlap-gyártás órarendből / dolgozatból
// Az órarend-részletező és a Feladatok dolgozat-sorai ugyanígy nyitnak
// lapot: ha a dolgozathoz (examId) már van lap, az nyílik; különben új
// lap készül az órához / dolgozathoz rendelve, a házi + dolgozat
// csatolmányaiból anyagokkal, és ha van miből, az AI azonnal megírja
// belőlük a jegyzetet. Csatolmány nélkül üres lap nyílik (kézi töltés).
enum CheatAutoNote {
    /// Meglévő lap dolgozathoz — duplikáció helyett ez nyílik.
    static func existingSheetID(examId: String) -> String? {
        CheatStore.load().first { $0.examId == examId }?.id
    }

    /// Okos dolgozat-feloldás: a fájlokat a KRÉTA gyakran nem a
    /// dolgozathoz, hanem egy külön házihoz (vagy csak az órához) teszi.
    /// Ha a laphoz nincs közvetlen dolgozat, megkeressük az adott nap +
    /// tárgy dolgozatát (ExamMatcher-szabályok szerint: óraszám-tűzés,
    /// különben nap-alap) — így a jegyzet ahhoz csatolódik (examId),
    /// az ő csatolmányaival és kontextusával készül.
    /// - Parameters:
    ///   - day: a keresett nap (házi-határidő vagy az óra napja); nil
    ///     esetén nincs feloldás (téves csatolás helyett inkább semmi).
    static func resolveExam(
        lessonIndex: Int? = nil,
        day: Date?,
        subject: String,
        exams: [ExamItem],
        calendar: Calendar = .current
    ) -> ExamItem? {
        guard let day, !exams.isEmpty else { return nil }
        let sameDay = exams.filter {
            SubjectMatcher.same($0.subject, subject)
                && calendar.isDate($0.date, inSameDayAs: day)
        }
        if let li = lessonIndex,
           let pinned = sameDay.first(where: { $0.lessonIndex != nil && $0.lessonIndex == li }) {
            return pinned
        }
        if let unpinned = sameDay.first(where: { $0.lessonIndex == nil }) {
            return unpinned
        }
        if sameDay.count == 1 { return sameDay[0] }
        if lessonIndex == nil { return sameDay.first }
        return nil
    }

    /// Meglévő órai lap dolgozat nélkül (tárgy + cím egyezés) — a
    /// "Jegyzet készítése" újranyomása ne duplázzon.
    static func existingLessonSheetID(subject: String, title: String) -> String? {
        CheatStore.load().first { $0.examId == nil && $0.subject == subject && $0.title == title }?.id
    }

    /// Lap-identitás egy órához / dolgozathoz: dolgozatnál az examId,
    /// különben tárgy + cím. A címképzés itt van egy helyen, hogy a
    /// "létezik már?" keresés és a gyártás ugyanazt adja (nincs duplázás).
    static func plannedIdentity(
        exam: ExamItem?,
        homework: HomeworkItem?,
        lessonSubject: String,
        lessonTitleFallback: String
    ) -> (examId: String?, subject: String, title: String) {
        let subject = exam?.subject ?? homework?.subject ?? lessonSubject
        if let exam {
            let title = exam.mode.isEmpty ? exam.subject : "\(exam.subject) • \(exam.mode)"
            return (exam.id, subject, title)
        }
        if let homework {
            let plain = homework.plainTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = plain.isEmpty ? "\(subject) • házi" : String(plain.prefix(120))
            return (nil, subject, title)
        }
        return (nil, subject, lessonTitleFallback)
    }

    /// AI-kontextus a kiinduló feladatból: nem anyag, hanem súlyozás —
    /// a generált jegyzet a házira / dolgozatra / órára készüljön, ne
    /// csak úgy általában "jó jegyzet" legyen az anyagokból.
    static func taskContext(
        exam: ExamItem?,
        homework: HomeworkItem?,
        lessonSubject: String? = nil,
        lessonTeacher: String? = nil,
        lessonDate: Date? = nil
    ) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "hu_HU")
        f.dateFormat = "MMM d."
        var lines: [String] = []
        if let exam {
            var t = "Dolgozat: \(exam.subject) – \(exam.mode)"
            if !exam.plainDescription.isEmpty { t += ". Leírás: \(exam.plainDescription)" }
            if !exam.teacher.isEmpty { t += ". Tanár: \(exam.teacher)" }
            t += ". Dátum: \(f.string(from: exam.date))"
            lines.append(t)
        }
        if let homework {
            var t = "Házi feladat: \(homework.subject)"
            let plain = homework.plainTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !plain.isEmpty { t += ". Feladat: \(plain)" }
            if !homework.teacher.isEmpty { t += ". Tanár: \(homework.teacher)" }
            t += ". Határidő: \(f.string(from: homework.deadline))"
            lines.append(t)
        }
        if let lessonSubject, !lessonSubject.isEmpty {
            var t = "Óra: \(lessonSubject)"
            if let lt = lessonTeacher, !lt.isEmpty { t += ". Tanár: \(lt)" }
            if let ld = lessonDate { t += ". Dátum: \(f.string(from: ld))" }
            lines.append(t)
        }
        return lines.joined(separator: "\n")
    }

    /// Meglévő lap órához / dolgozathoz (ugyanaz az identitás, mint
    /// gyártáskor) — duplikáció helyett ez nyílik. Közvetlen dolgozat
    /// nélkül az okos feloldás is fut: az aznapi dolgozathoz kötött lap
    /// is megtalálható.
    static func existingSheetID(
        exam: ExamItem?,
        homework: HomeworkItem?,
        lessonSubject: String,
        lessonTitleFallback: String,
        exams: [ExamItem] = [],
        lessonIndex: Int? = nil,
        lessonDate: Date? = nil
    ) -> String? {
        let ex = exam ?? resolveExam(
            lessonIndex: lessonIndex,
            day: homework?.deadline ?? lessonDate,
            subject: homework?.subject ?? lessonSubject,
            exams: exams)
        let id = plannedIdentity(
            exam: ex, homework: homework,
            lessonSubject: lessonSubject, lessonTitleFallback: lessonTitleFallback)
        if let examId = id.examId { return existingSheetID(examId: examId) }
        return existingLessonSheetID(subject: id.subject, title: id.title)
    }

    /// Teljes folyamat: lap-keresés vagy gyártás + csatolmányok +
    /// AI-jegyzet. Mindig ad lap-ID-t (AI-hiba esetén is nyílik a lap,
    /// benne az anyagokkal — az AI a lapról újrafuttatható).
    /// - Returns: (lap-ID, AI-hibaüzenet vagy nil)
    /// Intézet-kód a részlet-lekéréshez (a downloadAttachment mintája).
    /// A kliens MainActor-izolt, ezért a property-olvasás is await-es.
    private static func iss(kreta: KretaClient) async -> String {
        let code = await kreta.instituteCode
        let token = await kreta.accessToken
        return JWT.validInstituteCode(code)
            ?? JWT.validInstituteCode(JWT.instituteCode(from: token ?? "")) ?? ""
    }

    static func makeSheet(
        exam: ExamItem?,
        homework: HomeworkItem?,
        lessonSubject: String,
        lessonTitleFallback: String,
        lessonDate: Date?,
        lessonTeacher: String? = nil,
        weekLessons: [LessonItem] = [],
        exams: [ExamItem] = [],
        lessonIndex: Int? = nil,
        kreta: KretaClient
    ) async -> (id: String, aiError: String?) {
        // Okos feloldás: közvetlen dolgozat nélkül az aznapi, azonos
        // tárgyú dolgozathoz csatolunk (a fájlok gyakran máshol vannak).
        let exam = exam ?? resolveExam(
            lessonIndex: lessonIndex,
            day: homework?.deadline ?? lessonDate,
            subject: homework?.subject ?? lessonSubject,
            exams: exams)
        let id = plannedIdentity(
            exam: exam, homework: homework,
            lessonSubject: lessonSubject, lessonTitleFallback: lessonTitleFallback)
        if let examId = id.examId, let old = existingSheetID(examId: examId) {
            return (old, nil)
        }
        if id.examId == nil,
           let old = existingLessonSheetID(subject: id.subject, title: id.title) {
            return (old, nil)
        }
        let subject = id.subject
        let title = id.title
        let examId = id.examId
        let date: Date?
        if let exam {
            date = exam.date
        } else if let homework {
            date = homework.deadline
        } else {
            date = lessonDate
        }
        if exam == nil, let old = existingLessonSheetID(subject: subject, title: title) {
            return (old, nil)
        }
        // Csatolmány-feloldás: a hívó listái gyakran csupaszok (a KRÉTA a
        // fájlokat az órarendi elemre teszi) — órai merge + részlet-fetch
        // nélkül a gyártás üres lappal végezne, az AI sosem kapna anyagot.
        var hw = homework
        if var h = hw {
            if !weekLessons.isEmpty {
                h = HomeworkLessonAttachments.merged([h], lessons: weekLessons).first ?? h
            }
            if h.attachments.isEmpty {
                let code = await iss(kreta: kreta)
                if !code.isEmpty {
                    h = await kreta.fetchHomeworkDetails([h], iss: code).first ?? h
                }
            }
            hw = h
        }
        // Csatolmányok: dolgozat + házi (ID-duplázás nélkül, max 6 fájl).
        var seen = Set<String>()
        var atts: [AttachmentItem] = []
        for a in (exam?.attachments ?? []) + (hw?.attachments ?? []) {
            if seen.insert(a.id).inserted { atts.append(a) }
            if atts.count >= 6 { break }
        }
        var sheet = CheatSheet(examId: examId, subject: subject, title: title, date: date)
        for att in atts {
            guard let res = await kreta.downloadAttachment(att),
                  let made = makeMaterial(fileName: res.fileName, data: res.data) else { continue }
            sheet.materials.append(made.material)
            CheatStore.saveFullPayload(
                id: made.material.id,
                text: made.text, pdf: made.pdf, image: made.image
            )
            if sheet.materials.count >= CheatStore.maxMaterialsPerSheet { break }
        }
        CheatStore.upsert(sheet)
        guard !sheet.materials.isEmpty else { return (sheet.id, nil) }
        do {
            let context = taskContext(
                exam: exam, homework: homework,
                lessonSubject: lessonSubject,
                lessonTeacher: lessonTeacher, lessonDate: lessonDate)
            let topics = try await MetaAIClient.generateTopics(
                subject: subject, title: title, materials: sheet.materials,
                context: context)
            if var fresh = CheatStore.load().first(where: { $0.id == sheet.id }) {
                fresh.topics = topics
                CheatStore.upsert(fresh)
            }
            return (sheet.id, nil)
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return (sheet.id, msg)
        }
    }

    // MARK: - Csatolmány → anyag

    /// Letöltött fájl → lap-anyag + lemez-tári payload. Szkennelt (szöveg
    /// nélküli) pdf is anyag marad — az AI az oldalak képét kapja meg.
    /// Támogatatlan / üres fájlra nil.
    static func makeMaterial(fileName: String, data: Data)
        -> (material: CheatMaterial, text: String?, pdf: Data?, image: Data?)?
    {
        guard !data.isEmpty else { return nil }
        let ext = (fileName as NSString).pathExtension.lowercased()
        if ext == "pdf" {
            let text = pdfText(from: data)
            let m = CheatMaterial(
                name: fileName,
                text: String(text.prefix(CheatStore.maxMaterialChars)),
                kind: "pdf"
            )
            return (m, text.isEmpty ? nil : text, data, nil)
        }
        if ["png", "jpg", "jpeg", "heic", "webp", "gif"].contains(ext),
           let ui = UIImage(data: data),
           let jpg = normalizedJPEG(ui) {
            let m = CheatMaterial(name: fileName, text: "", kind: "image")
            return (m, nil, nil, jpg)
        }
        if let s = String(data: data, encoding: .utf8), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let m = CheatMaterial(name: fileName, text: s)
            return (m, s, nil, nil)
        }
        if let s = String(data: data, encoding: .isoLatin2), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let m = CheatMaterial(name: fileName, text: s)
            return (m, s, nil, nil)
        }
        return nil
    }

    /// PDF szövegkinyerés oldalanként (a generálás teljes szövege).
    static func pdfText(from data: Data) -> String {
        guard let doc = PDFDocument(data: data) else { return "" }
        var out = ""
        for i in 0..<doc.pageCount {
            if let s = doc.page(at: i)?.string { out += s + "\n" }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Fénykép-normalizálás (az importtal azonos: max 2048px, JPEG).
    static func normalizedJPEG(_ ui: UIImage, maxSide: CGFloat = 2048) -> Data? {
        let s = max(ui.size.width, ui.size.height)
        let img: UIImage
        if s > maxSide, s > 0 {
            let k = maxSide / s
            let ns = CGSize(width: ui.size.width * k, height: ui.size.height * k)
            let r = UIGraphicsImageRenderer(size: ns)
            img = r.image { _ in ui.draw(in: CGRect(origin: .zero, size: ns)) }
        } else {
            img = ui
        }
        return img.jpegData(compressionQuality: 0.85)
    }
}
