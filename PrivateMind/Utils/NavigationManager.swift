import SwiftUI

@MainActor
class NavigationManager: ObservableObject {
    static let shared = NavigationManager()
    
    @Published var shouldStartNewNote = false
    
    private init() {}
}

