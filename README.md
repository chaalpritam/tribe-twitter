# tribe-ios

Native SwiftUI iOS client for the [TribeEco](https://github.com/chaalpritam/tribeeco) decentralized social protocol.

## Status

Read-only client wired to the existing tribe-hub. Browse the network from your phone — feed, explore, channels, polls, events, tasks, crowdfunds, notifications, search, plus a wallet *Receive* view with a QR code.

Write paths (publishing tweets, voting, RSVPing, claiming tasks, sending tips, encrypted DMs) are stubbed pending a Swift port of the signed-envelope helpers in `tribe-app/src/lib/messages.ts` and a Solana-mobile / WalletConnect integration for on-chain transactions.

## Requirements

- Xcode 16 (iOS 17 deployment target)
- [xcodegen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`
- A running `tribe-hub` (defaults to `http://127.0.0.1:4000`; override in Settings)

## Running

```sh
cd tribe-ios
xcodegen generate          # creates TribeIOS.xcodeproj from Project.yml
open TribeIOS.xcodeproj
# In Xcode: pick a simulator and ⌘R
```

If you're running the hub on a different machine, set the URL in **Settings → Hub URL** the first time you open the app.

## Layout

```
TribeIOS/             Xcode app target (entry point + Info.plist + assets)
Sources/
  Config.swift        Build-time defaults
  API/                URLSession-based hub client
  Models/             Codable types matching hub responses
  State/              AppState + persisted settings
  Views/
    Shell/            RootView + BottomNavBar (tribeapp.wtf-style pill nav)
    Home/             Feed + tweet card
    Explore/          User discovery
    Profile/          Profile, karma, tabs
    Notifications/    Aggregated notification feed
    Channels/         Channel list + feed
    Polls/Events/Tasks/Crowdfunds/    Activity primitives
    Search/           Cross-primitive search
    Wallet/           Balance, receive (QR), tip activity
    Settings/         Hub URL + identity stubs
    Common/           Reusable bits (cards, empty states, …)
```

## Why xcodegen

Hand-rolled `project.pbxproj` files are fragile and noisy in PRs. `Project.yml` is the source of truth — `xcodegen generate` produces a fresh `.xcodeproj` deterministically. The generated project is in `.gitignore` on purpose.

## What still needs porting from tribe-app

- ed25519 signing + blake3 hashing of canonical envelope bytes
- x25519 + nacl box encryption for direct messages
- Solana on-chain helpers (TID registration, follow/unfollow via ER server, on-chain tipping)
- Ephemeral Rollup client for instant follows
