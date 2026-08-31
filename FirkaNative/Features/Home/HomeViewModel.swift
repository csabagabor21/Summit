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
        guard let user, !user.isDemo else {
            grades = DemoData.grades()
            homeworks = DemoData.homeworks()
            absences = DemoData.absences()
            messages = DemoData.messages()
            exams = DemoData.exams()
            lessonsToday = DemoData.lessonsToday()
            updateLiveState()
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        let iss = user.instituteCode.isEmpty ? (JWT.instituteCode(from: user.accessToken) ?? "") : user.instituteCode

        async let g = kreta.fetchGrades(iss: iss)
        async let hw = kreta.fetchHomework(iss: iss)
        async let ab = kreta.fetchAbsences(iss: iss)
        async let ex = kreta.fetchExams(iss: iss)
        async let msg = kreta.fetchMessages()
        // timetable for today
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        async let tt = kreta.fetchTimetable(iss: iss, from: start, to: end)

        let (gradesR, hwR, abR, exR, msgR, ttR) = await (g, hw, ab, ex, msg, tt)

        self.grades = gradesR.isEmpty && DemoData.grades().isEmpty ? [] : (gradesR.isEmpty ? [] : gradesR)
        self.homeworks = hwR
        self.absences = abR
        self.exams = exR
        self.messages = msgR
        self.lessonsToday = ttR

        // Show error if all empty (likely outside HU or token fail)
        if gradesR.isEmpty && hwR.isEmpty && abR.isEmpty && exR.isEmpty && msgR.isEmpty && ttR.isEmpty {
            // keep empty, FeedView will show empty state
        }

        updateLiveState()
    }

    func updateLiveState() {
        if lessonsToday.isEmpty {
            // fallback by hour
            let h = Calendar.current.component(.hour, from: Date())
            if h < 7 { liveState = .morning }
            else if h < 15 { liveState = .duringLesson }
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
