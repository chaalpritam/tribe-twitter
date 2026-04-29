# tribe-ios

Native SwiftUI iOS client for the [TribeEco](https://github.com/chaalpritam/tribeeco) decentralized social protocol.

The visual language is borrowed from `tribeapp.wtf`: a black rounded-pill bottom nav with a floating "+" Create sheet, white card surfaces with a 28-pt corner radius, monochrome primary actions, and quiet semantic accents (indigo for polls, amber for warnings, emerald for success, rose for unread badges).

## Status

iPhone-only, portrait-only mobile app. iPad and landscape layouts are intentionally not supported — the bottom-tab nav and single-column card stacks are designed for one-hand portrait use.

**Functional, end-to-end against a real hub:**

| Surface | Read | Write |
|---|---|---|
| Onboarding (Welcome → Configure Hub → Import / Create identity) | — | ✅ |
| Home feed | ✅ | Compose tweet, reply, delete |
| Tweet card | ✅ | Like, unlike, bookmark, unbookmark, reply, delete (own) |
| Explore (people) | ✅ | — |
| Search (cross-primitive) | ✅ | — |
| Tribes → Channels | ✅ | — |
| Tribes → Polls | ✅ | Vote |
| Tribes → Events | ✅ | RSVP yes / maybe / no |
| Tribes → Tasks | ✅ | Claim, complete |
| Tribes → Crowdfunds | ✅ | Pledge (off-chain envelope) |
| Activity (notifications) | ✅ | — |
| Profile | ✅ | — |
| Wallet → Receive | ✅ | QR + copy |
| Wallet → Send | — | Off-chain TIP_ADD envelope |
| Wallet → Activity | ✅ | — |
| Settings | ✅ | Switch hub, view app key, sign out |

Every write builds a signed envelope locally — BLAKE3 hashing (pure-Swift port of the reference implementation, with self-test vectors that run at launch) and ed25519 signing via Apple CryptoKit's `Curve25519`. The seed lives in the iOS Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`); UserDefaults only stores the hub URL and the public TID number.

**Still stubbed:**

| Capability | Why |
|---|---|
| Register a fresh TID on Solana | The on-chain `tid-registry` program needs a Solana mobile / WalletConnect provider on iOS. Workaround today: register on tribe-app, then import the TID + app-key via the iOS onboarding flow. |
| On-chain tip settlement | Same — `tip-registry` program calls need the wallet-adapter integration. The off-chain TIP_ADD envelope works and shows up in notifications + karma; no `tx_signature` yet. |
| On-chain crowdfund settlement | Same. |
| Direct messages | x25519 + NaCl-box encryption needs porting from tribe-app's `lib/crypto.ts`. CryptoKit has Curve25519 KeyAgreement but not the XSalsa20-Poly1305 used by tweetnacl. |
| Map (city-anchored content) | UI placeholder — channel kind = 2 (city) needs surfacing in the Tribes section. |

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
  Config.swift                       defaultHubURL + Solana cluster
  AppState.swift                     persisted hub URL + TID + shared HubClient

  API/
    HubClient.swift                  URLSession + JSONDecoder wrapper
    Endpoints.swift                  read paths matching tribe-app/src/lib/api.ts

  Models/
    Decoding.swift                   bigint / date / decimal / count helpers
    Tweet, User, Channel, Poll, Event, TaskItem, Crowdfund, Tip, Notification, Karma

  Views/
    Shell/        RootView + BottomNavBar (tribeapp.wtf-style pill nav)
    Home/         HomeFeedView + TweetCardView
    Explore/      ExploreView (user list, opens Search sheet)
    Search/       SearchView (cross-primitive)
    Notifications/  NotificationsView (sheet from Home bell)
    Channels/     TribesHubView + ChannelsView (Tribes tab parent)
    Polls/        PollsView
    Events/       EventsView (upcoming/all toggle)
    Tasks/        TasksView (status filter chips)
    Crowdfunds/   CrowdfundsView
    Profile/      ProfileView (user + tweets + karma; opens Wallet/Settings)
    Wallet/       WalletView + QRCodeView + ReceiveSheet
    Settings/     Hub URL + TID
    Common/       Card, AvatarView, PageHeader, EmptyStateView, RelativeTime, Pill, …
```

## Project file: xcodegen + committed `.xcodeproj`

`Project.yml` is the source of truth for build settings, schemes, source paths, and target config. The `.xcodeproj` is generated from it via [xcodegen](https://github.com/yonaskolb/XcodeGen) and **is committed** so a fresh clone opens directly in Xcode — no tooling install required.

When you add new Swift files, you don't need to do anything: Xcode picks them up via the source group's directory reference. When you change build settings or add a new target, edit `Project.yml` and run `xcodegen generate`. xcodegen produces deterministic GUIDs from the Project.yml input, so the resulting pbxproj diff stays tight and reviewable.

## Adding it to TribeEco as a submodule

The repo is initialized locally. To wire it into `tribeeco`:

```sh
# 1. Create the GitHub repo (e.g. chaalpritam/tribe-ios), then:
cd tribe-ios
git remote add origin git@github.com:chaalpritam/tribe-ios.git
git push -u origin master

# 2. From the TribeEco root, add as a submodule:
cd ..
git submodule add https://github.com/chaalpritam/tribe-ios.git tribe-ios
git commit -m "chore: add tribe-ios submodule"
```

## What's next

- Wrap the Solana on-chain helpers (TID register, follow/unfollow, on-chain tip) using a Solana mobile / WalletConnect provider. Until that lands, on-chain settlement is the only piece left for full feature parity with tribe-app.
- Implement DM encryption (x25519 + NaCl box) — needs an XSalsa20-Poly1305 implementation since CryptoKit ships ChaCha20-Poly1305 but not the variant tweetnacl uses.
- Map tab for city-anchored content (channel kind = 2) using MapKit.

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
