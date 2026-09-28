import GameKit
import UIKit

/// Game Center sign-in and achievements. Achievement IDs must also be created in
/// App Store Connect (Features → Game Center) before they can be earned.
final class GameCenter {
    enum Achievement: String, CaseIterable {
        case firstFlight = "org.mushroomhollow.achievement.first_flight"
        case choseAPath = "org.mushroomhollow.achievement.chose_a_path"
        case level10 = "org.mushroomhollow.achievement.level_10"
        case level30 = "org.mushroomhollow.achievement.level_30"
        case owlSlayer = "org.mushroomhollow.achievement.owl_slayer"
    }

    private var reported: Set<Achievement> = []

    var isAuthenticated: Bool { GKLocalPlayer.local.isAuthenticated }

    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { viewController, _ in
            guard let viewController else { return }
            MainActor.assumeIsolated {
                Self.topViewController?.present(viewController, animated: true)
            }
        }
    }

    func report(_ achievement: Achievement) {
        guard isAuthenticated, !reported.contains(achievement) else { return }
        reported.insert(achievement)
        let progress = GKAchievement(identifier: achievement.rawValue)
        progress.percentComplete = 100
        progress.showsCompletionBanner = true
        GKAchievement.report([progress]) { _ in }
    }

    /// The Game Center badge; shown while menus are open so it never covers the fight.
    func showAccessPoint(_ visible: Bool) {
        guard isAuthenticated else { return }
        GKAccessPoint.shared.location = .topLeading
        GKAccessPoint.shared.isActive = visible
    }

    private static var topViewController: UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
