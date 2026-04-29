import Foundation

/// Build-time defaults for the iOS app. The hub URL can be overridden
/// at runtime from the Settings tab — useful when developing against
/// a hub running on a peer's laptop / Tailscale IP.
enum Config {
    static let defaultHubURL: URL = URL(string: "http://127.0.0.1:4000")!

    /// Solana cluster used for explorer deep-links and on-chain reads.
    /// Defaults to devnet to match the rest of the demo stack.
    static let solanaCluster = "devnet"
}
