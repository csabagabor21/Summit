import Foundation

enum HardcodedTimetable {
    // Standard bell times for 7 periods
    private static let bell: [(sh:Int, sm:Int, eh:Int, em:Int)] = [
        (8,0,8,45),
        (8,55,9,40),
        (9,55,10,40),
        (10,50,11,35),
        (11,45,12,30),
        (12,40,13,25),
        (13,35,14,20),
    ]

    struct Def { let subject:String; let teacher:String; let room:String }

    static func lessons() -> [LessonItem] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)
        let mondayOffset = (weekday == 1 ? -6 : 2 - weekday)
        let monday = cal.date(byAdding: .day, value: mondayOffset, to: today)!

        let weekDefs: [[Def]] = [
            // Hétfő 7 óra
            [
                Def(subject: "Matematika", teacher: "Hegedűsné Laky Orsolya", room: "A2"),
                Def(subject: "Irodalom", teacher: "Csuka Emőke", room: "D3"),
                Def(subject: "Hálózatok I.", teacher: "Góóz László", room: "Kollégium gépterem"),
                Def(subject: "Testnevelés", teacher: "Vargáné Hidvéghy Édua", room: "Urányi-terem"),
                Def(subject: "Testnevelés", teacher: "Vargáné Hidvéghy Édua", room: "Urányi-terem"),
                Def(subject: "Történelem", teacher: "Kovács Edina", room: "D4"),
                Def(subject: "IKT projektmunka II.", teacher: "Góóz László", room: "A4"),
            ],
            // Kedd
            [
                Def(subject: "Irodalom", teacher: "Csuka Emőke", room: "D3"),
                Def(subject: "Irodalom", teacher: "Csuka Emőke", room: "D3"),
                Def(subject: "Testnevelés", teacher: "Vargáné Hidvéghy Édua", room: "A8"),
                Def(subject: "Szerverek és felhőszolgáltatások", teacher: "Csizmadia Bence", room: "A7"),
                Def(subject: "Szerverek és felhőszolgáltatások", teacher: "Csizmadia Bence", room: "A7"),
                Def(subject: "Matematika", teacher: "Hegedűsné Laky Orsolya", room: "A2"),
                Def(subject: "Angol nyelv", teacher: "Dr. Endrédiné Győrfi Tünde", room: "C6"),
            ],
            // Szerda
            [
                Def(subject: "Történelem", teacher: "Kovács Edina", room: "D4"),
                Def(subject: "Hálózatok I.", teacher: "Góóz László", room: "A3-DKA"),
                Def(subject: "Matematika", teacher: "Hegedűsné Laky Orsolya", room: "A2"),
                Def(subject: "Adatbázis-kezelés I.", teacher: "Balogh-Angyal Zsuzsanna", room: "A7"),
                Def(subject: "Angol nyelv", teacher: "Dr. Endrédiné Győrfi Tünde", room: "C6"),
                Def(subject: "IKT projektmunka II.", teacher: "Góóz László", room: "A10"),
                Def(subject: "Szerverek és felhőszolgáltatások", teacher: "Csizmadia Bence", room: "A7"),
            ],
            // Csütörtök
            [
                Def(subject: "Történelem", teacher: "Kovács Edina", room: "D4"),
                Def(subject: "Matematika", teacher: "Hegedűsné Laky Orsolya", room: "A2"),
                Def(subject: "Matematika", teacher: "Hegedűsné Laky Orsolya", room: "A2"),
                Def(subject: "Állampolgári ismeretek", teacher: "Makóné Buzás Eleonóra", room: "D4"),
                Def(subject: "Angol nyelv", teacher: "Dr. Endrédiné Győrfi Tünde", room: "C6"),
                Def(subject: "Magyar nyelv", teacher: "Csuka Emőke", room: "D3"),
                Def(subject: "Osztályfőnöki", teacher: "Vargáné Hidvéghy Édua", room: "A1"),
            ],
            // Péntek - 6 óra, 7. nincs
            [
                Def(subject: "IKT projektmunka II.", teacher: "Góóz László", room: "A5"),
                Def(subject: "Adatbázis-kezelés I.", teacher: "Balogh-Angyal Zsuzsanna", room: "Kollégium gépterem"),
                Def(subject: "Szakmai angol nyelv", teacher: "Dr. Endrédiné Győrfi Tünde", room: "C6"),
                Def(subject: "Szakmai angol nyelv", teacher: "Dr. Endrédiné Győrfi Tünde", room: "C6"),
                Def(subject: "Hálózatok I.", teacher: "Góóz László", room: "A4"),
                Def(subject: "Hálózatok I.", teacher: "Góóz László", room: "A4"),
            ],
        ]

        var out: [LessonItem] = []
        for dayOffset in 0..<weekDefs.count {
            let dayBase = cal.date(byAdding: .day, value: dayOffset, to: monday)!
            let defs = weekDefs[dayOffset]
            for (idx, d) in defs.enumerated() {
                let b = bell[idx]
                let s = cal.date(bySettingHour: b.sh, minute: b.sm, second: 0, of: dayBase)!
                let e = cal.date(bySettingHour: b.eh, minute: b.em, second: 0, of: dayBase)!
                let period = idx + 1
                out.append(LessonItem(
                    id: "hard-\(dayOffset)-\(period)",
                    subject: d.subject,
                    room: d.room,
                    start: s,
                    end: e,
                    teacher: d.teacher,
                    index: "\(period)"
                ))
            }
        }
        return out
    }
}
