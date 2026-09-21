import Foundation
import SwiftUI

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var selectedTab = 0
    @Published var liveState: LiveCardState = .morning
    @Published var isRefreshing = false

    // Real data
    @Published var grades: [GradeItem] = []
    @Published var lessonsToday: [LessonItem] = []
    @Published var homeworks: [HomeworkItem] = []
    @Published var absences: [AbsenceItem] = []
    @Published var messages: [MessageItem] = []
    @Published var exams: [ExamItem] = []
    @Published var error: String?

    var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        if h >= 18 { return "Jó estét" }
        if h >= 12 { return "Jó napot" }
        if h >= 4 { return "Jó reggelt" }
        return "Jó estét"
    }

    func refresh(kreta: KretaClient, user: AppUser?) async {
        // Egy adatsáv: demo usert is a KretaClient szolgálja ki helyből
        // (instituteCode "demo") — nincs külön demo-ág.
        guard let user else {
            error = "Nincs bejelentkezett felhasználó."
            updateLiveState()
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        let iss = user.instituteCode.isEmpty ? (JWT.instituteCode(from: user.accessToken) ?? "") : user.instituteCode
        if iss.isEmpty || iss == "unknown" {
            error = "Hiányzó intézményi kód — jelentkezz be újra."
            lessonsToday = []
            updateLiveState()
            return
        }

        async let g = kreta.fetchGrades(iss: iss)
        async let hw = kreta.fetchHomework(iss: iss)
        async let ab = kreta.fetchAbsences(iss: iss)
        async let ex = kreta.fetchExams(iss: iss)
        async let msg = kreta.fetchMessages()

        let hadData = !(grades.isEmpty && homeworks.isEmpty && absences.isEmpty && exams.isEmpty && messages.isEmpty && lessonsToday.isEmpty)
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        async let tt = kreta.fetchTimetable(iss: iss, from: start, to: end)
        let (gradesR, hwR, abR, exR, msgR, ttR) = await (g, hw, ab, ex, msg, tt)
        if gradesR.isEmpty && hwR.isEmpty && abR.isEmpty && exR.isEmpty && msgR.isEmpty && ttR.isEmpty {
            if hadData {
                // Totális fetch-hiba (lejárt token, offline): a legutóbbi adat
                // marad a képernyőn, nem ürül ki a főoldal — csak hibaüzenet jön.
                error = kreta.sessionExpired
                    ? "A KRÉTA-munkamenet lejárt — jelentkezz be újra."
                    : "Nem sikerült frissíteni — a legutóbbi adatokat mutatjuk."
                updateLiveState()
                return
            }
            error = "Nem érkezett adat a KRÉTÁ-tól — ellenőrizd a kapcsolatot vagy jelentkezz be újra."
            updateLiveState()
            return
        }
        self.grades = gradesR
        // Saját (kézzel felvett) tételek is a főoldalra kerülnek — ugyanazokkal
        // a lejárt-szabályokkal, mint a KRÉTA-tételek.
        let custom = CustomTasksStore.load()
        // Lejárt határidejű házi nem kerül a főoldalra (a Feladatok tabon
        // és az értesítési diffben megmarad) — demóra is ugyanez vonatkozik,
        // mint egy valós userre.
        self.homeworks = (hwR + CustomTasksStore.homeworkItems(from: custom)).filter { !HomeworkExpiry.isExpired($0) }
        self.absences = abR
        // Lejárt dolgozat a főoldalra sem kerül (a Feladatok tab Kész
        // szegmensében és az értesítési diffben megmarad).
        self.exams = (exR + CustomTasksStore.examItems(from: custom)).filter { !ExamExpiry.isExpired($0) }
        self.messages = msgR
        self.lessonsToday = ttR
        // Helyi értesítés-diff az újakról (KRÉTA push nincs, ez polling-alapú)
        NotificationManager.shared.checkAll(
            grades: gradesR, homeworks: hwR, exams: exR, absences: abR, userId: user.id
        )
        error = nil
        updateLiveState()
        return
    }

    func updateLiveState() {
        if lessonsToday.isEmpty {
            // Valódi üres: ne hazudjunk "óra közben"-t — ha nincs órarend, az empty.
            // Demo-ban sosem üres, élesben viszont API hiba miatt lehet — ilyenkor empty, nem fake duringLesson.
            let h = Calendar.current.component(.hour, from: Date())
            if h < 7 { liveState = .morning }
            else if h < 16 { liveState = .empty }
            else { liveState = .empty }
            return
        }
        let now = Date()
        if lessonsToday.contains(where: { $0.start <= now && $0.end >= now }) {
            liveState = .duringLesson
        } else if let next = lessonsToday.first(where: { $0.start > now }),
                  let prev = lessonsToday.last(where: { $0.end < now }),
                  next.start.timeIntervalSince(prev.end) > 0 {
            liveState = .duringBreak
        } else if now < lessonsToday.first!.start {
            liveState = .morning
        } else {
            liveState = .empty
        }
    }

    var nextLesson: LessonItem? {
        let now = Date()
        return lessonsToday.first(where: { $0.start > now })
    }
    var currentLesson: LessonItem? {
        let now = Date()
        return lessonsToday.first(where: { $0.start <= now && $0.end >= now })
    }
}
