# tribe-ios

Native SwiftUI iOS client for the [TribeEco](https://github.com/chaalpritam/tribeeco) decentralized social protocol.

The visual language is borrowed from `tribeapp.wtf`: a black rounded-pill bottom nav with a floating "+" Create sheet, white card surfaces with a 28-pt corner radius, monochrome primary actions, and quiet semantic accents (indigo for polls, amber for warnings, emerald for success, rose for unread badges).

## Status

iPhone-only, portrait-only mobile app. iPad and landscape layouts are intentionally not supported — the bottom-pill nav and single-column card stacks are designed for one-hand portrait use.

**Read-only** client wired to the existing `tribe-hub`. Every screen is functional against a real hub — feed, explore, channels, polls, events, tasks, crowdfunds, notifications, search, profile, plus a wallet *Receive* view with a QR code.

**Stubbed** until ported:

| Capability                       | Why it's stubbed                                                  |
|----------------------------------|-------------------------------------------------------------------|
| Compose tweet / reply            | Needs ed25519 signing + blake3 hashing of canonical envelope bytes (see `tribe-app/src/lib/messages.ts`). |
| Like / bookmark / retweet        | Same — every write goes through a signed envelope.                |
| Vote on poll, RSVP, claim/complete task, pledge crowdfund | Same.                                                             |
| Send tip                         | TIP_ADD envelope + on-chain transfer through the tip-registry program. |
| Direct messages                  | x25519 + NaCl box encryption + DM_KEY_REGISTER + DM_SEND envelopes. |
| Register a new TID               | Solana program calls + ER server for app-key registration.         |
| Map (city-anchored content)      | UI placeholder — channel kind = 2 (city) needs surfacing.          |

## Requirements

- Xcode 16 (iOS 17 deployment target)
- [xcodegen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`
- A running `tribe-hub` (defaults to `http://127.0.0.1:4000`; override in **Profile → Settings**)

## Running

```sh
cd tribe-ios
xcodegen generate          # creates TribeIOS.xcodeproj from Project.yml
open TribeIOS.xcodeproj
# In Xcode: pick an iPhone simulator (16 / 15 / SE / etc.) and ⌘R
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

## Why xcodegen

Hand-rolled `project.pbxproj` files are fragile and noisy in PRs. `Project.yml` is the source of truth — `xcodegen generate` produces a fresh `.xcodeproj` deterministically. The generated project is in `.gitignore` on purpose.

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

- Port the signed envelope path (ed25519 + blake3 + canonical JSON) from `tribe-app/src/lib/messages.ts` into Swift, exposed as a `MessageSigner`. Once that lands, every read screen flips to writable in a few line per surface.
- Wrap the Solana on-chain helpers (TID register, follow/unfollow, on-chain tip) using a Solana mobile / WalletConnect provider. Until that lands, the wallet stays receive-only.
- Implement DM encryption (x25519 + NaCl box) so the Chat tab can flip on.
- Map tab for city-anchored content (channel kind = 2) using MapKit.
