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
        let useDemo = user == nil || user!.isDemo
        if useDemo {
            grades = DemoData.grades()
            homeworks = DemoData.homeworks()
            absences = DemoData.absences()
            messages = DemoData.messages()
            exams = DemoData.exams()
            lessonsToday = DemoData.lessonsToday()
            error = nil
            updateLiveState()
            return
        }
        // Ha be van kapcsolva a fix órarend, Home Now panelje is azt mutassa (paritás Timetable-lal)
        let useHardcoded = UserDefaults.standard.bool(forKey: "timetable.useHardcoded")
        isRefreshing = true
        defer { isRefreshing = false }

        let iss = user!.instituteCode.isEmpty ? (JWT.instituteCode(from: user!.accessToken) ?? "") : user!.instituteCode
        if iss.isEmpty {
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

        let start: Date
        let end: Date
        let ttResult: [LessonItem]
        if useHardcoded {
            // Fix heti rendből a mai nap
            let all = HardcodedTimetable.lessons()
            let todayWeekday = Calendar.current.component(.weekday, from: Date())
            ttResult = all.filter { Calendar.current.component(.weekday, from: $0.start) == todayWeekday }.sorted { $0.start < $1.start }
            start = Date(); end = Date() // dummy, nem használt
            // hw/ex-et így is lekérjük KRÉTÁ-ból, de ttResult már megvan
            let (gradesR, hwR, abR, exR, msgR) = await (g, hw, ab, ex, msg)
            self.grades = gradesR
            self.homeworks = hwR
            self.absences = abR
            self.exams = exR
            self.messages = msgR
            self.lessonsToday = ttResult
            error = nil
            // ha minden üres, az nem hiba ha fix órarend van — legalább órarend van
            updateLiveState()
            return
        } else {
            start = Calendar.current.startOfDay(for: Date())
            end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
            async let tt = kreta.fetchTimetable(iss: iss, from: start, to: end)
            let (gradesR, hwR, abR, exR, msgR, ttR) = await (g, hw, ab, ex, msg, tt)
            self.grades = gradesR
            self.homeworks = hwR
            self.absences = abR
            self.exams = exR
            self.messages = msgR
            self.lessonsToday = ttR
            if gradesR.isEmpty && hwR.isEmpty && abR.isEmpty && exR.isEmpty && msgR.isEmpty && ttR.isEmpty {
                error = "Nem érkezett adat a KRÉTÁ-tól — ellenőrizd a kapcsolatot vagy jelentkezz be újra."
            } else {
                error = nil
            }
            updateLiveState()
            return
        }
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
        if let cur = lessonsToday.first(where: { $0.start <= now && $0.end >= now }) {
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
