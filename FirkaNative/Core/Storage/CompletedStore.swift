import Foundation

@MainActor
final class CompletedStore: ObservableObject {
    @Published private(set) var homeworkDone: Set<String> = []
    @Published private(set) var examDone: Set<String> = []

    private let hwKey = "firka.completed.homework.v1"
    private let exKey = "firka.completed.exam.v1"

    init() { load() }

    func load() {
        if let a = UserDefaults.standard.array(forKey: hwKey) as? [String] { homeworkDone = Set(a) }
        if let a = UserDefaults.standard.array(forKey: exKey) as? [String] { examDone = Set(a) }
    }
    private func persist() {
        UserDefaults.standard.set(Array(homeworkDone), forKey: hwKey)
        UserDefaults.standard.set(Array(examDone), forKey: exKey)
    }

    func isHomeworkDone(_ id: String) -> Bool { homeworkDone.contains(id) }
    func isExamDone(_ id: String) -> Bool { examDone.contains(id) }

    func toggleHomework(_ id: String) {
        if homeworkDone.contains(id) { homeworkDone.remove(id) } else { homeworkDone.insert(id) }
        persist(); objectWillChange.send()
    }
    func toggleExam(_ id: String) {
        if examDone.contains(id) { examDone.remove(id) } else { examDone.insert(id) }
        persist(); objectWillChange.send()
    }
}
