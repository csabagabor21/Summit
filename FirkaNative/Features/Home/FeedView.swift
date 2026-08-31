import SwiftUI

// Not used standalone now — Home uses List Sections directly.
// Kept for compatibility, delegates to native rows.
struct FeedView: View {
    var filter: Int
    var grades: [GradeItem] = []
    var homeworks: [HomeworkItem] = []
    var absences: [AbsenceItem] = []
    var messages: [MessageItem] = []
    var exams: [ExamItem] = []
    var body: some View { EmptyView() }
}
