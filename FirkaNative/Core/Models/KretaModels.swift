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
}
struct LessonItem: Identifiable, Hashable {
    let id: String
    let subject: String
    let room: String
    let start: Date
    let end: Date
    let teacher: String
    let index: String
}
struct HomeworkItem: Identifiable, Hashable {
    let id: String
    let subject: String
    let title: String
    let deadline: Date
    let teacher: String
    let isDone: Bool
}
struct AbsenceItem: Identifiable, Hashable {
    let id: String
    let subject: String
    let date: Date
    let type: String // Igazolt / Igazolatlan
    let delay: Int?
}
struct MessageItem: Identifiable, Hashable {
    let id: String
    let sender: String
    let subject: String
    let date: Date
    let isRead: Bool
}
struct ExamItem: Identifiable, Hashable {
    let id: String
    let subject: String
    let date: Date
    let mode: String
    let description: String
}

// MARK: - DTOs matching real e-KRÉTA JSON (keys are Hungarian)
struct TantargyDTO: Decodable { let Nev: String?; let Uid: String? }
struct TipusDTO: Decodable { let Nev: String? }

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
        let df = ISO8601DateFormatter(); df.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let df2 = ISO8601DateFormatter()
        func parse(_ s: String?) -> Date {
            guard let s else { return Date() }
            return df.date(from: s) ?? df2.date(from: s) ?? Date()
        }
        return GradeItem(
            id: Uid ?? UUID().uuidString,
            subject: Tantargy?.Nev ?? "Ismeretlen",
            value: SzamErtek ?? 0,
            valueText: SzovegesErtek ?? "\(SzamErtek ?? 0)",
            date: parse(KeszitesDatuma ?? RogzitesDatuma),
            teacher: (ErtekeloTanarNeve ?? "").trimmingCharacters(in: .whitespaces),
            type: Tipus?.Nev ?? "Értékelés",
            weight: SulySzazalekErteke ?? 100
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
    func toItem() -> LessonItem? {
        guard let tant = Tantargy?.Nev else { return nil }
        let df = ISO8601DateFormatter(); df.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let df2 = ISO8601DateFormatter()
        func p(_ s: String?) -> Date { guard let s else { return Date() }; return df.date(from: s) ?? df2.date(from: s) ?? Date() }
        let room = (TeremNeve ?? "").replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: " terem", with: "", options: .caseInsensitive)
        return LessonItem(
            id: Uid ?? UUID().uuidString,
            subject: tant,
            room: room.isEmpty ? "-" : room,
            start: p(KezdetIdopont),
            end: p(VegIdopont),
            teacher: (HelyettesTanarNeve ?? TanarNeve ?? "").trimmingCharacters(in: .whitespaces),
            index: Oraszam.map(String.init) ?? "-"
        )
    }
}

struct KretaHomeworkDTO: Decodable {
    let Uid: String?
    let TantargyNeve: String?
    let Szoveg: String?
    let HataridoDatuma: String?
    let FeladoTanarNeve: String?
    let IsTanuloHaziFeladatEnabled: Bool?
    func toItem() -> HomeworkItem {
        let df = ISO8601DateFormatter(); let df2 = ISO8601DateFormatter(); df2.formatOptions = [.withFullDate]
        func p(_ s: String?) -> Date { guard let s else { return Date() }; return df.date(from: s) ?? df2.date(from: s) ?? Date() }
        return HomeworkItem(
            id: Uid ?? UUID().uuidString,
            subject: TantargyNeve ?? "Házi",
            title: (Szoveg ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            deadline: p(HataridoDatuma),
            teacher: FeladoTanarNeve ?? "",
            isDone: !(IsTanuloHaziFeladatEnabled ?? true)
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
        let df = ISO8601DateFormatter()
        func p(_ s: String?) -> Date { guard let s, let d = df.date(from: s) else { return Date() }; return d }
        return AbsenceItem(
            id: Uid ?? UUID().uuidString,
            subject: Tantargy?.Nev ?? "Hiányzás",
            date: p(Datum),
            type: IgazolasTipusa?.Nev ?? Tipus?.Nev ?? "Ismeretlen",
            delay: KesesPercben
        )
    }
}

struct KretaMessageDTO: Decodable {
    let azon: String?
    let uzenet: UzenetDTO?
    let feladoNev: String?
    let targy: String?
    let elkuldve: String?

    // eugyintezes uses different wrapper; be lenient
    struct UzenetDTO: Decodable { let targy: String?; let feladoNev: String?; let elkuldve: String? }

    // fallback keys
    let sender: String?
    let subject: String?
    let date: String?

    enum CodingKeys: String, CodingKey { case azon, uzenet, feladoNev, targy, elkuldve, sender, subject, date }

    func toItem() -> MessageItem {
        let df = ISO8601DateFormatter()
        func p(_ s: String?) -> Date { guard let s, let d = df.date(from: s) else { return Date() }; return d }
        let s = feladoNev ?? uzenet?.feladoNev ?? sender ?? "Üzenet"
        let t = targy ?? uzenet?.targy ?? subject ?? "(nincs tárgy)"
        let d = elkuldve ?? uzenet?.elkuldve ?? date
        return MessageItem(id: azon ?? UUID().uuidString, sender: s, subject: t, date: p(d), isRead: false)
    }
}

struct KretaExamDTO: Decodable {
    let Uid: String?
    let TantargyNeve: String?
    let Tantargy: TantargyDTO?
    let Datum: String?
    let Modja: TipusDTO?
    let Tema: String?
    func toItem() -> ExamItem {
        let df = ISO8601DateFormatter()
        func p(_ s: String?) -> Date { guard let s, let d = df.date(from: s) else { return Date() }; return d }
        return ExamItem(
            id: Uid ?? UUID().uuidString,
            subject: TantargyNeve ?? Tantargy?.Nev ?? "Dolgozat",
            date: p(Datum),
            mode: Modja?.Nev ?? "Számonkérés",
            description: Tema ?? ""
        )
    }
}

// Keep DemoData only for true demo user or preview — enriched
enum DemoData {
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
        // deadlines aligned to demo lessons (same-day) so LiveCard attachedInfo is verifiable
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func at(_ dayOffset: Int, hour: Int = 23) -> Date { cal.date(byAdding: .day, value: dayOffset, to: today)!.addingTimeInterval(Double(hour*3600)) }
        return [
            HomeworkItem(id: "h1", subject: "Matek", title: "Gyakorló 12-15 (HF)", deadline: at(0, hour: 16), teacher: "Kovács", isDone: false),
            HomeworkItem(id: "h2", subject: "Angol", title: "Unit 5 vocab + essay 300 szó", deadline: at(0, hour: 16), teacher: "Smith", isDone: false),
            HomeworkItem(id: "h3", subject: "Fizika", title: "Munkafüzet 42.o / 5 feladat", deadline: at(1, hour: 16), teacher: "Varga", isDone: false),
            HomeworkItem(id: "h4", subject: "Töri", title: "Esszé vázlat", deadline: at(1, hour: 16), teacher: "Nagy", isDone: false),
            HomeworkItem(id: "h5", subject: "Irodalom", title: "Olvasónapló 2. fejezet", deadline: at(2, hour: 16), teacher: "Szabó", isDone: false),
            HomeworkItem(id: "h6", subject: "Kémia", title: "Tk. 56.o feladatok", deadline: at(3, hour: 16), teacher: "Kiss", isDone: false),
        ]
    }
    static func absences() -> [AbsenceItem] { [
        AbsenceItem(id: "a1", subject: "Testnevelés", date: Date().addingTimeInterval(-86400*2), type: "Igazolt", delay: nil),
        AbsenceItem(id: "a2", subject: "Matek", date: Date().addingTimeInterval(-86400*5), type: "Igazolatlan", delay: nil),
        AbsenceItem(id: "a3", subject: "Angol", date: Date().addingTimeInterval(-86400*8), type: "Késés", delay: 12),
    ]}
    static func messages() -> [MessageItem] { [
        MessageItem(id: "m1", sender: "Osztályfőnök", subject: "Szülői értekezlet pénteken 17h", date: Date().addingTimeInterval(-3600*5), isRead: false),
        MessageItem(id: "m2", sender: "Igazgatóság", subject: "Tájékoztató — őszi szünet", date: Date().addingTimeInterval(-86400), isRead: true),
        MessageItem(id: "m3", sender: "Kovács J.", subject: "Pót ZH időpont", date: Date().addingTimeInterval(-86400*2), isRead: false),
    ]}
    static func exams() -> [ExamItem] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func at(_ dayOffset: Int, hour: Int = 10) -> Date { cal.date(byAdding: .day, value: dayOffset, to: today)!.addingTimeInterval(Double(hour*3600)) }
        return [
            ExamItem(id: "e1", subject: "Kémia", date: at(0, hour: 10), mode: "Írásbeli", description: "Sav-bázis"),
            ExamItem(id: "e2", subject: "Matek", date: at(1, hour: 9), mode: "Témazáró", description: "Függvények"),
            ExamItem(id: "e3", subject: "Fizika", date: at(2, hour: 10), mode: "Dolgozat", description: "Munka, energia"),
            ExamItem(id: "e4", subject: "Töri", date: at(4, hour: 11), mode: "Témazáró", description: "II. vh."),
            ExamItem(id: "e5", subject: "Angol", date: at(5, hour: 9), mode: "Szóbeli", description: "Unit 5"),
        ]
    }
    /// Today's demo timetable — 6 lessons covering 8:00–13:45, subjects aligned with DemoData homeworks/exams
    static func lessonsToday() -> [LessonItem] {
        let cal = Calendar.current; let base = cal.startOfDay(for: Date())
        let defs: [(String,String,String,String,Int,Int)] = [
            ("Matek","103","Kovács J.","1",8,0),
            ("Angol","204","Smith","2",9,0),
            ("Fizika","105","Varga","3",10,0),
            ("Töri","102","Nagy A.","4",11,0),
            ("Kémia","107","Kiss","5",12,0),
            ("Irodalom","101","Szabó K.","6",13,0),
        ]
        return defs.enumerated().map { idx, d in
            let s = cal.date(byAdding: .hour, value: d.4, to: base)!.addingTimeInterval(Double(d.5*60))
            let e = s.addingTimeInterval(45*60)
            return LessonItem(id: "lt\(idx)", subject: d.0, room: d.1, start: s, end: e, teacher: d.2, index: d.3)
        }
    }
    static func lessonsExpanded() -> [LessonItem] {
        // Keep for Timetable preview: repeat lessonsToday for a full-week mock
        let today = lessonsToday()
        let cal = Calendar.current
        // expand to Mon-Fri by shifting days
        var all: [LessonItem] = []
        for dayOffset in 0..<5 {
            for l in today {
                let s = cal.date(byAdding: .day, value: dayOffset, to: l.start)!
                let e = cal.date(byAdding: .day, value: dayOffset, to: l.end)!
                all.append(LessonItem(id: "\(l.id)-d\(dayOffset)", subject: l.subject, room: l.room, start: s, end: e, teacher: l.teacher, index: l.index))
            }
        }
        return all
    }
}
