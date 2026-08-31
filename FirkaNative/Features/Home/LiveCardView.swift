import SwiftUI
enum LiveCardState { case empty, morning, duringLesson, duringBreak, summary }
struct LiveCardView: View {
    var state: LiveCardState; var nextLesson: LessonItem?; var currentLesson: LessonItem?
    var body: some View { EmptyView() } // Replaced by LiveCardRow in HomeView List
}
