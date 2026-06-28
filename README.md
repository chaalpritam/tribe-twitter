# tribe-ios

Native SwiftUI iOS client for the [TribeEco](https://github.com/chaalpritam/tribeeco) decentralized social protocol.

The visual language is borrowed from `tribeapp.wtf`: a black rounded-pill bottom nav with a floating "+" Create sheet, white card surfaces with a 28-pt corner radius, monochrome primary actions, and quiet semantic accents (indigo for polls, amber for warnings, emerald for success, rose for unread badges).

## Screenshots

<table>
  <tr>
    <td><img src="cover/IMG_1760.PNG" width="180"/></td>
    <td><img src="cover/IMG_1761.PNG" width="180"/></td>
    <td><img src="cover/IMG_1762.PNG" width="180"/></td>
    <td><img src="cover/IMG_1763.PNG" width="180"/></td>
    <td><img src="cover/IMG_1764.PNG" width="180"/></td>
  </tr>
  <tr>
    <td><img src="cover/IMG_1765.PNG" width="180"/></td>
    <td><img src="cover/IMG_1766.PNG" width="180"/></td>
    <td><img src="cover/IMG_1767.PNG" width="180"/></td>
    <td><img src="cover/IMG_1768.PNG" width="180"/></td>
    <td><img src="cover/IMG_1769.PNG" width="180"/></td>
  </tr>
  <tr>
    <td><img src="cover/IMG_1770.PNG" width="180"/></td>
    <td><img src="cover/IMG_1771.PNG" width="180"/></td>
    <td><img src="cover/IMG_1772.PNG" width="180"/></td>
    <td><img src="cover/IMG_1773.PNG" width="180"/></td>
    <td><img src="cover/IMG_1774.PNG" width="180"/></td>
  </tr>
  <tr>
    <td><img src="cover/IMG_1775.PNG" width="180"/></td>
    <td><img src="cover/IMG_1776.PNG" width="180"/></td>
    <td><img src="cover/IMG_1777.PNG" width="180"/></td>
    <td><img src="cover/IMG_1778.PNG" width="180"/></td>
    <td><img src="cover/IMG_1779.PNG" width="180"/></td>
  </tr>
  <tr>
    <td><img src="cover/IMG_1780.PNG" width="180"/></td>
    <td><img src="cover/IMG_1781.PNG" width="180"/></td>
    <td><img src="cover/IMG_1783.PNG" width="180"/></td>
    <td><img src="cover/IMG_1784.PNG" width="180"/></td>
    <td><img src="cover/IMG_1785.PNG" width="180"/></td>
  </tr>
</table>

## Status

iPhone-only, portrait-only mobile app. iPad and landscape layouts are intentionally not supported — the bottom-tab nav and single-column card stacks are designed for one-hand portrait use.

**Functional, end-to-end against a real hub:**

| Surface | Read | Write |
|---|---|---|
| Onboarding (Welcome → Configure Hub → Import / Create identity) | — | ✅ |
| Home feed | ✅ | Compose tweet, reply, delete |
| Tweet card | ✅ | Like, unlike, bookmark, unbookmark, reply, delete (own) |
| Tweet detail (replies thread) | ✅ | — |
| Explore (people) | ✅ | Live follow status (read-only — see below) |
| Search (cross-primitive) | ✅ | — |
| Tribes → Channels | ✅ | Create channel (interest / city), open channel feed |
| Tribes → Map | ✅ | — (city channels + located events on MapKit) |
| Tribes → Polls | ✅ | Create poll, vote |
| Tribes → Events | ✅ | Create event, RSVP yes / maybe / no |
| Tribes → Tasks | ✅ | Create task, claim, complete |
| Tribes → Crowdfunds | ✅ | Create crowdfund, pledge (off-chain envelope) |
| Activity (notifications, sheet from Home bell) | ✅ | — |
| Messages (1:1 DMs, NaCl-box encrypted) | ✅ | DM_KEY_REGISTER, DM_SEND |
| Profile | ✅ | Edit profile (displayName / bio / pfpUrl / location / url) |
| Wallet → Receive | ✅ | QR + copy |
| Wallet → Send | — | Off-chain TIP_ADD envelope |
| Wallet → Activity | ✅ | — |
| Settings | ✅ | Switch hub, switch ER server, view app key, sign out |

Every write builds a signed envelope locally — BLAKE3 hashing (pure-Swift port of the reference implementation, with self-test vectors that run at launch) and ed25519 signing via Apple CryptoKit's `Curve25519`. The seed lives in the iOS Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`); UserDefaults only stores the hub URL, the ER server URL, and the public TID number.

DMs use a separate x25519 keypair (also in the Keychain) plus a pure-Swift port of `nacl.box` (Salsa20 core, XSalsa20 stream, Poly1305 MAC) so ciphertext written here is byte-compatible with what tweetnacl produces in tribe-app. `NaClBox.selfTest()` round-trips at launch.

**Still stubbed:**

| Capability | Why |
|---|---|
| Register a fresh TID on Solana | The on-chain `tid-registry` program needs a Solana mobile / WalletConnect provider on iOS. Workaround today: register on tribe-app, then import the TID + app-key via the iOS onboarding flow. |
| Follow / unfollow writes | The ER sequencer's `/v1/follow` requires a signature from the user's Solana custody key, which the iOS app doesn't hold. Read-only follow state still surfaces from the ER server (Follow / Following / Pending labels). The button on tap explains the limitation and points the user at tribe-app on web. |
| On-chain tip settlement | `tip-registry` program calls need the wallet-adapter integration. The off-chain TIP_ADD envelope works and shows up in notifications + karma; no `tx_signature` yet. |
| On-chain crowdfund settlement | Same. |

## Requirements

- Xcode 16 (iOS 17 deployment target)
- A running `tribe-hub` (defaults to `http://127.0.0.1:4000`; override in **Profile → Settings**)
- Optional: [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) — only needed if you edit `Project.yml`

## Running

```sh
cd tribe-ios
open TribeIOS.xcodeproj
# In Xcode: pick an iPhone simulator (16 / 15 / SE / etc.) and ⌘R
```

The Xcode project is committed for convenience, so a fresh clone opens directly without any tooling. If you need to add files, change build settings, or fold in another target, edit `Project.yml` and re-run:

```sh
xcodegen generate
```

If Xcode opens but doesn't show iPhone simulators in the destination menu, your active developer directory is probably set to Command Line Tools instead of Xcode itself. Fix it with:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

If the hub is on a different machine, open the app, tap the gear in the Profile tab, and set the hub URL. The app persists this in `UserDefaults`, so you don't need to set it again.

To wire the app to your TID, paste it into the same Settings sheet. The notifications badge, profile, and wallet activity are gated on this.

## Layout

```
TribeIOS/                            Xcode app target
  TribeIOSApp.swift                  @main entry
  Info.plist                         App Transport Security off so http://hub-ip works in dev
  Assets.xcassets                    AccentColor (black) + AppIcon

Sources/
  Config.swift                       defaultHubURL + defaultERURL + Solana cluster
  State/
    AppState.swift                   persisted hub URL + TID + shared HubClient + ERClient + DMKey
    InteractionCache.swift           session-scoped like / bookmark sets

  API/
    HubClient.swift                  URLSession + JSONDecoder wrapper
    Endpoints.swift                  read paths matching tribe-app/src/lib/api.ts
    Publish.swift                    every signed-envelope write path
    InteractionReads.swift           per-user "have I liked / bookmarked X" helpers
    ERClient.swift                   ephemeral-rollup follow status reads

  Crypto/
    AppKey.swift                     ed25519 signing key (CryptoKit Curve25519)
    Blake3.swift                     pure-Swift Blake3 port + self-test
    DMKey.swift                      x25519 DM keypair (Keychain-backed)
    NaClBox.swift                    Salsa20 + Poly1305 + nacl.box / box.open + self-test
    Keychain.swift                   wrapper around SecItem
    MessageSigner.swift              builds the canonical envelope JSON

  Models/
    Decoding.swift                   bigint / date / decimal / count helpers
    Tweet, User, Channel, Poll, Event, TaskItem, Crowdfund, Tip, Notification, Karma, DM

  Views/
    Shell/        RootView + BottomNavBar (tribeapp.wtf-style pill nav)
    Home/         HomeFeedView + TweetCardView + TweetDetailView
    Explore/      ExploreView (user list with FollowButton)
    Search/       SearchView (cross-primitive)
    Notifications/  NotificationsView (sheet from Home bell)
    Channels/     TribesHubView + ChannelsView + ChannelFeedView + ChannelMapView + CreateChannelSheet
    Polls/        PollsView + CreatePollSheet
    Events/       EventsView + CreateEventSheet
    Tasks/        TasksView + CreateTaskSheet
    Crowdfunds/   CrowdfundsView + CreateCrowdfundSheet
    Messages/     MessagesView + DMThreadView + NewDMSheet
    Profile/      ProfileView + ProfileEditorView (opens Wallet/Settings)
    Wallet/       WalletView + QRCodeView + ReceiveSheet
    Settings/     Hub URL + ER URL + TID
    Onboarding/   Welcome → Configure Hub → Pair / Import / Create identity
    Common/       Card, AvatarView, FollowButton, EmptyStateView, RelativeTime, Pill, Slug, …
```

## Project file: xcodegen + committed `.xcodeproj`

`Project.yml` is the source of truth for build settings, schemes, source paths, and target config. The `.xcodeproj` is generated from it via [xcodegen](https://github.com/yonaskolb/XcodeGen) and **is committed** so a fresh clone opens directly in Xcode — no tooling install required.

When you add new Swift files, you don't need to do anything: Xcode picks them up via the source group's directory reference. When you change build settings or add a new target, edit `Project.yml` and run `xcodegen generate`. xcodegen produces deterministic GUIDs from the Project.yml input, so the resulting pbxproj diff stays tight and reviewable.

## Where this fits

`tribe-ios` is part of the [TribeEco](https://github.com/chaalpritam/TribeEco) monorepo as a submodule. Clone the monorepo with `--recurse-submodules` to get everything.

| Repo | Role |
|---|---|
| [tribe-protocol](../tribe-protocol) | Solana programs — identity, app keys, social graph, registries |
| [tribe-sdk](../tribe-sdk) | TypeScript SDK shared by web clients |
| [tribe-hub](../tribe-hub) | Decentralized hub — message storage, indexing, gossip |
| [tribe-er-server](../tribe-er-server) | Ephemeral Rollup sequencer — instant follows |
| [tribe-app](../tribe-app) | Next.js reference client |
| [tribeapp.wtf](../tribeapp.wtf) | Consumer-facing web app + landing page |

## What's next

- Wrap the Solana on-chain helpers (TID register, follow/unfollow, on-chain tip) using a Solana mobile / WalletConnect provider. Until that lands, on-chain settlement is the only piece left for full feature parity with tribe-app.
- Group DMs (DM_GROUP_CREATE / DM_GROUP_SEND). The 1:1 path is wired up; group fan-out encryption follows the same pattern (encrypt the same plaintext once per recipient with their x25519 pubkey).
- Native iOS share sheet → quick-compose tweet from any other app.

## Crypto

The signed-envelope path matches `tribe-app/src/lib/messages.ts`:

```
data    = { type, tid, timestamp, network: 2, body }
dataB64 = base64( JSON-canonical(data) )
hash    = base64( blake3(dataB64-bytes) )      // 32 bytes
signature = base64( ed25519_sign(hash, app_key) ) // 64 bytes
signer  = base64( ed25519_public_key )            // 32 bytes
```

- `Sources/Crypto/Blake3.swift` is a port of the BLAKE3 reference implementation. `Blake3.selfTest()` runs against three official vectors (empty input, `0x00`, and the 1023-byte sequence that exercises the chunk boundary) on every launch.
- `Sources/Crypto/AppKey.swift` wraps `Curve25519.Signing.PrivateKey`. The 32-byte raw seed is the canonical representation everywhere.
- `Sources/Crypto/Keychain.swift` stores the seed under `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- `Sources/Crypto/MessageSigner.swift` builds the envelope. `JSONSerialization` with `[.sortedKeys, .withoutEscapingSlashes]` produces canonical bytes for `dataB64` so the hash is reproducible.

## Related Repos

| Repo | Description |
|------|-------------|
| [tribe-protocol](../tribe-protocol) | Solana programs (Anchor) — 12 programs: tid-registry, app-key-registry, username-registry, social-graph w/ ER delegation, hub-registry, tip-registry, crowdfund-registry, task-registry, channel-registry, karma-registry, poll-registry, event-registry |
| [tribe-sdk](../tribe-sdk) | TypeScript SDK — DirectSolana and EphemeralRollup providers; clients for identity, tweets, DMs, profiles, channels, bookmarks, polls, events, tasks, crowdfunds, tips, search |
| [tribe-hub](../tribe-hub) | Decentralized hub — signed-message storage + Solana indexer + gossip peer sync; REST + WebSocket APIs |
| [tribe-er-server](../tribe-er-server) | Ephemeral Rollup sequencer — instant follows, batched L1 settlement every 10s |
| [tribe-app](../tribe-app) | Next.js frontend — protocol-first reference client with multi-node failover |
| [tribeapp.wtf](../tribeapp.wtf) | Consumer-facing web app + landing page at tribeapp.wtf — hyperlocal social built entirely on the protocol |
| [tribe-ios](../tribe-ios) | Native SwiftUI iOS client (Twitter-shaped) — full read/write against hub + ER, NaCl-box DMs, BLAKE3 + ed25519 signing via Apple CryptoKit |
| [tribe-insta](../tribe-insta) | Native SwiftUI iOS client (Instagram-shaped) — photo grid, stories, reels; same hub + envelope format as tribe-ios. Scaffolding stage — see `tribe-insta/PLAN.md` |
| [tribe-core-swift](../tribe-core-swift) | Shared Swift package consumed by tribe-ios + tribe-insta — crypto (BLAKE3, NaCl box, ed25519 signing, BIP39, SolanaHD), backup file format, envelope signer. See `tribe-core-swift/MIGRATION.md` |
| [homebrew-tap](../homebrew-tap) | Homebrew formulas: `brew install tribe` (hub + ER) and `brew install tribe-app` (demo UI) |
