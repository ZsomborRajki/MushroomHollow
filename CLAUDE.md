# Mushroom Hollow

Flyff-inspired iOS action RPG on the forest floor under one giant tree. Apple-only (iOS 27+, iPhone + iPad, landscape).
Offline first; online (authoritative Swift server) later.

## Architecture rule (do not break)

- `Packages/GameCore` is the authoritative simulation: pure Swift, **no RealityKit/SwiftUI/UIKit/simd imports** (Foundation only), so it can run on a Linux server later. Deterministic: fixed 20 Hz tick, `SeededRandom` only, iterate entities in sorted-ID order.
- The app never mutates game state directly. It sends `PlayerCommand`s through a `WorldHost` and renders `WorldSnapshot`s. `LocalWorldHost` runs the sim in-process; a future `RemoteWorldHost` will talk to the server.
- RealityKit is presentation only (models, interpolation, effects). `WorldMap` is shared, so the rendered world and the collision world always match.
- Input devices (GameController, keyboard, touch) are merged into `InputFrame` in `InputHub`; gameplay never reads devices.

## Layout

- `MushroomHollow/` app target (Xcode synchronized folder: new files are picked up automatically)
  - `App/` SwiftUI entry and `GameView` (RealityView + overlays)
  - `Game/` `GameSession` (per-frame glue), `OrbitCamera`
  - `Rendering/` `WorldRenderer`, `WorldBuilder` (static world), `ActorModels` (placeholder primitives), `Placeholders` (palette, meshes, materials)
  - `Shaders/` Metal `CustomMaterial` shaders (grass sway/color, sky gradient)
  - `Input/`, `HUD/`
- `Packages/GameCore/` simulation + Swift Testing tests
- `Config/Info.plist` holds only keys that have no build setting (GameController keys); everything else is `INFOPLIST_KEY_*`.

Conventions: yaw 0 faces +Z and yaw `a` faces (sin a, cos a); models face +Z. The app target uses default MainActor isolation and `MemberImportVisibility`, so import every module you use.

## Commands

- Sim tests: `cd Packages/GameCore && swift test`
- App build: `xcodebuild -project MushroomHollow.xcodeproj -scheme MushroomHollow -destination 'generic/platform=iOS Simulator' build`
- Simulator controls: WASD to move, Q/E or arrow keys for the camera (hardware keyboard), or touch.

## Roadmap

0. Foundation: world, movement, camera, input ✅
1. Combat slice: targeting, auto-attack, HP, XP/levels, snails, HUD
2. Content: all mob AIs, skills, loot/inventory, village NPCs/shop/quests, SwiftData saves
3. World & polish: zones, day/night, effects, audio, haptics, class change, flying
4. Owl world boss
5. Online: Linux server running GameCore, Sign in with Apple / Game Center
