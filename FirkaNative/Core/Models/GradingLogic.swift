import Foundation

// Per-subject rounding thresholds, stored in UserDefaults by subject name
// Threshold = fractional part at which average rounds up (0.56 means 3.56 -> 4)
enum GradingLogic {
    static let defaultThreshold: Double = 0.50
    private static let key = "firka.roundingThresholds.v1"

    static func loadThresholds() -> [String: Double] {
        (UserDefaults.standard.dictionary(forKey: key) as? [String: Double]) ?? [:]
    }
    static func save(_ dict: [String: Double]) {
        UserDefaults.standard.set(dict, forKey: key)
    }
    static func threshold(for subject: String) -> Double {
        loadThresholds()[subject] ?? defaultThreshold
    }
    static func setThreshold(_ t: Double, for subject: String) {
        var d = loadThresholds(); d[subject] = t; save(d)
    }

    // Weighted average: sum(value * weight) / sum(weight)
    // Weight is SulySzazalek (100 = 1x, 200 = 2x). Normalize to /100.
    // 0-s jegy nem számít (nem kerül átlagba és grafikonra sem)
    static func weightedAverage(_ grades: [GradeItem]) -> Double {
        let valid = grades.filter { $0.value != 0 }
        guard !valid.isEmpty else { return 0 }
        let sum = valid.reduce(0.0) { $0 + Double($1.value) * Double($1.weight) / 100.0 }
        let w = valid.reduce(0.0) { $0 + Double($1.weight) / 100.0 }
        guard w > 0 else { return 0 }
        return sum / w
    }

    static func roundedGrade(raw: Double, threshold: Double) -> Int {
        let frac = raw - floor(raw)
        // tiny epsilon to avoid floating errors
        if frac + 1e-9 >= threshold { return Int(ceil(raw)) }
        return Int(floor(raw))
    }

    static func roundedForSubject(_ grades: [GradeItem], subject: String) -> Int {
        let raw = weightedAverage(grades)
        return roundedGrade(raw: raw, threshold: threshold(for: subject))
    }

    // Overall normál = nyers átlagok átlaga
    static func overallAverage(grouped: [String: [GradeItem]]) -> Double {
        guard !grouped.isEmpty else { return 0 }
        let subjectAvgs = grouped.values.map { weightedAverage($0) }
        return subjectAvgs.reduce(0, +) / Double(subjectAvgs.count)
    }
    // Overall kerekített = kerekített jegyek átlaga (tantárgyi kerekítés után)
    static func overallRoundedAverage(grouped: [String: [GradeItem]]) -> Double {
        guard !grouped.isEmpty else { return 0 }
        let roundedPerSubject = grouped.map { (subject, grades) in
            Double(roundedForSubject(grades, subject: subject))
        }
        return roundedPerSubject.reduce(0, +) / Double(roundedPerSubject.count)
    }

    // Target planner: how many grades of `desiredValue` needed to reach target rounded grade?
    // We compute minimal k where new rounded >= targetRounded.
    static func neededGrades(current: [GradeItem], subject: String, targetRounded: Int) -> (count: Int, values: [Int], achievable: Bool) {
        let thr = threshold(for: subject)
        let curW = current.reduce(0.0) { $0 + Double($1.weight)/100.0 }
        let curSum = current.reduce(0.0) { $0 + Double($1.value)*Double($1.weight)/100.0 }
        // Try with 5s first, then 4s etc, brute force up to 20 extra grades
        for k in 1...20 {
            // Best case: all 5s
            let newRaw = (curSum + Double(5 * k)) / (curW + Double(k))
            if roundedGrade(raw: newRaw, threshold: thr) >= targetRounded {
                return (k, Array(repeating: 5, count: k), true)
            }
        }
        // Try mixed: if target is 4, maybe 4s are enough
        for k in 1...20 {
            for val in [4,5] {
                let newRaw = (curSum + Double(val * k)) / (curW + Double(k))
                if roundedGrade(raw: newRaw, threshold: thr) >= targetRounded {
                    return (k, Array(repeating: val, count: k), true)
                }
            }
        }
        return (0, [], false)
    }

    // For display: suggest simplest path (prefer 5s, then 4s)
    static func suggestionText(current: [GradeItem], subject: String, target: Int) -> String {
        let (cnt, vals, ok) = neededGrades(current: current, subject: subject, targetRounded: target)
        if !ok { return "Már \(target) felett vagy vagy nem elérhető 20 jegyen belül." }
        if cnt == 0 { return "Már megvan a \(target)-as átlag." }
        if vals.allSatisfy({ $0==5 }) { return "Szerezz \(cnt) db 5-öst és meglesz a \(target)-as." }
        return "Szerezz \(cnt) db \(vals.first ?? 5)-öst és meglesz a \(target)-as."
    }
}
