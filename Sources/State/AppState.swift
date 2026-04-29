import Foundation
import SwiftUI

/// Top-level app state. Holds the connected TID, hub base URL, and a
/// shared API client. Persisted across launches via UserDefaults so the
/// user doesn't have to re-enter their TID every time.
@MainActor
final class AppState: ObservableObject {
    @Published var hubBaseURL: URL {
        didSet {
            UserDefaults.standard.set(hubBaseURL.absoluteString, forKey: Keys.hubURL)
            api = HubClient(baseURL: hubBaseURL)
        }
    }

    @Published var myTID: String? {
        didSet {
            if let tid = myTID {
                UserDefaults.standard.set(tid, forKey: Keys.tid)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.tid)
            }
        }
    }

    @Published var myUsername: String?
    @Published var walletAddress: String?

    private(set) var api: HubClient

    init() {
        let storedURL = UserDefaults.standard.string(forKey: Keys.hubURL)
            .flatMap(URL.init(string:)) ?? Config.defaultHubURL
        self.hubBaseURL = storedURL
        self.myTID = UserDefaults.standard.string(forKey: Keys.tid)
        self.api = HubClient(baseURL: storedURL)
    }

    private enum Keys {
        static let hubURL = "tribe.hubBaseURL"
        static let tid = "tribe.tid"
    }
}
