import Foundation
import SwiftUI

@MainActor
final class RootViewModel: ObservableObject {
    @Published var isLoggedIn = false
}
