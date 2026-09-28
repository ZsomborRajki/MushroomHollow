# Mushroom Hollow

Flyff-inspired iOS action RPG on the forest floor under one giant tree. Apple-only (iOS 27+, iPhone + iPad, landscape).
Offline first; online (authoritative Swift server) later.

## Architecture rule (do not break)

- `Packages/GameCore` is the authoritative simulation: pure Swift, **no RealityKit/SwiftUI/UIKit/simd imports** (Foundation only), so it can run on a Linux server later. Deterministic: fixed 20 Hz tick, `SeededRandom` only, iterate entities in sorted-ID order.
- The app never mutates game state directly. It sends `PlayerCommand`s through a `WorldHost` and renders `WorldSnapshot`s. `LocalWorldHost` runs the sim in-process; a future `RemoteWorldHost` will talk to the server.
- RealityKit is presentation only (models, interpolation, effects). `WorldMap` is shared, so the rendered world and the collision world always match.
- Input devices (GameController, keyboard, touch) are merged into `InputFrame` (analog + discrete `InputAction`s) in `InputHub`; gameplay never reads devices.
- The sim reports what happened as `WorldEvent`s (damage, deaths, level ups...); the client turns them into effects, damage numbers, and haptics. Private player data (XP, MP, cooldowns) travels as `WorldSnapshot.viewer`.
- Tuning and content live in GameCore: `Stats.swift` (mob stats, XP curve, player growth), `Skills.swift`, `Items.swift` (incl. `WeaponType`: sword/axe for anyone, maul/bow/wand/staff per class; each sets attack speed, reach, two-handedness; shields add block chance; `Gear` = item + upgrade level), `Sets.swift` (4-piece armor sets with 2/3/4-piece bonuses: Dewleaf at level 5, one class set at 15, Thistledown at 20), `Upgrades.swift` (+1…+10 at the blacksmith: Amber Shards from mobs + caps, rising failure risk, Ward Charms protect), `Loot.swift`, `Quests.swift`, `NPCs.swift`, `WorldMap.swift` (zones, spawns, NPC placement). Client-only looks (icons, colors, messages) are in `Game/SkillPresentation.swift` and `Game/ItemPresentation.swift`.
- The world: an inner ring of zones between the roots (levels 1–15, Great Bough boss) and an outer ring of six flat hunting grounds on a trail at radius 108 (levels 14–30). Each hunting ground holds two species, each in its own half (`pair` in `WorldMap`). Mob abilities are traits in `MobAI.swift` (`hidesWhenHurt`, `charges`, `trail`, `cloud`, `splitsInto`), so a new mob just picks them; hazards (`slime`, `web`, `embers`, clouds) are tuned per `HazardKind`. Every mob drops its own material; each zone's mobs drop the next tier of common gear.
- NPC interactions (shop, quests, upgrades at Shiitake) are sim commands validated by distance, so they'll work unchanged online.
- Saves: the sim exposes `PlayerProfile` (Codable); the app stores it with SwiftData in `Persistence/SaveStore.swift` (autosave every 20 s, on key events, and when backgrounded). New profile fields must be optional (or decode with defaults) so older saves still load.
- Time of day comes from the sim tick (`WorldSnapshot.timeOfDay`), so online players will share one sky. `Rendering/Atmosphere.swift` turns it into lighting, sky shader parameters, and `ColorGradeEffect` (RealityKit post-process + `Shaders/PostProcess.metal`).
- World boss logic is in `GameCore/WorldBoss.swift` (spawn once per night via `nightIndex`, scripted `BossBrain` moves, `TelegraphSnapshot`s for the client). Everyone in `BossBrain.damagers` gets XP/loot/quest credit.
- Game Center (`Services/GameCenter.swift`): achievement IDs `org.mushroomhollow.achievement.{first_flight, chose_a_path, level_10, level_30, owl_slayer}` must exist in App Store Connect. Entitlement in `Config/MushroomHollow.entitlements`.
- Audio is synthesized at launch (`Audio/SoundSynth.swift` → WAV `Data` → `AudioFileResource(from:)`); `SoundBank` plays combat sounds spatially from entities.

## Layout

- `MushroomHollow/` app target (Xcode synchronized folder: new files are picked up automatically)
  - `App/` SwiftUI entry and `GameView` (RealityView + overlays)
  - `Game/` `GameSession` (per-frame glue, panels, event → feedback), `OrbitCamera`
  - `Rendering/` `WorldRenderer`, `WorldBuilder` (static world), `ActorModels` (mob/NPC primitives; the newer critters are in `CritterModels`, all with big anime eyes via `addCuteEyes`), `PlayerRig` (the chibi player "Sprout": joint hierarchy, procedural walk/cast/cheer animation, a per-weapon-type attack: sword/axe/maul/wand swing combos with trails, bow draw/release, staff thrust+twirl, shield block; gear on joints), `WeaponModels` (weapon and shield meshes), `FacePainter` (anime face painted with CoreGraphics into a head texture, one material per expression), `Placeholders` (palette, meshes incl. lathe/torus/uvSphere, materials)
  - `Shaders/` Metal: `CustomMaterial` shaders (grass sway/color, day/night sky) and the post-process compute kernel
  - `Audio/` sound synthesis and playback
  - `Input/` (`InputHub`: gameplay vs menu button mapping), `HUD/` (HUD, `ActionBar`, `Panels` for bag / NPC dialogs), `Persistence/`
- `Packages/GameCore/` simulation + Swift Testing tests
- `Config/Info.plist` holds only keys that have no build setting (GameController keys); everything else is `INFOPLIST_KEY_*`.

Conventions: yaw 0 faces +Z and yaw `a` faces (sin a, cos a); models face +Z. The app target uses default MainActor isolation and `MemberImportVisibility`, so import every module you use.

## Commands

- Sim tests: `cd Packages/GameCore && swift test`
- App build: `xcodebuild -project MushroomHollow.xcodeproj -scheme MushroomHollow -destination 'generic/platform=iOS Simulator' build`
- Simulator controls (hardware keyboard): WASD move, Q/E or arrows camera, Space/F attack, Tab next target, Esc clear, 1/2/3 skills.
- Keyboard extras: 1–5 skills, 6/7 potions, I bag, G fly/land, R/C climb/descend; in menus arrows/WASD navigate, Space/Enter confirm, Esc back, Q/E switch shop tab (at the forge: toggle Ward Charm).
- Controller: left stick move, right stick camera, A attack/talk/respawn, X/Y/B skills, RT+X/RT+Y class skills, LB/RB cycle target, LT clear target, d-pad up/down zoom, d-pad left/right potions, Menu bag, L3 fly/land (RT/LT climb/descend while flying). In panels: d-pad/stick navigate, A confirm, B back, LB/RB shop tabs.
- Debug launch arguments (DEBUG builds only; all but `-resetSave` use a throwaway in-memory save): `-autofight`, `-demo` (geared level 10 character with a Dandelion Seed, upgraded gear, Dewleaf pieces, and amber), `-level N`, `-class guardian|thornshot|sporecaster|dewkeeper` (level 18, wielding the class weapon), `-weapon sword|axe|maul|bow|wand|staff` (plus a buckler for one-handers), `-attackloop` (attack thin air on repeat, blocking every 5th; pair with `-portrait <degrees>`), `-time 0...1` (0 midnight, 0.5 noon), `-spawn village|glade|maze|barkfall|fen|meadow|creek|thicket|rise|briars|grove`, `-panel bag|morel|shop|smith`, `-fly`, `-owl` (summon the world boss and stand in its arena), `-portrait [degrees]` (camera close up in front of the player, optionally orbited; view only), `-resetSave`. Example: `xcrun simctl launch <udid> org.mushroomhollow.MushroomHollow -demo -panel shop`.

## Roadmap

0. Foundation: world, movement, camera, input ✅
1. Combat slice: targeting, auto-attack, HP/MP, XP/levels, 3 skills, mob AI (passive/aggressive, leash), respawns, HUD ✅
2. Content: mob abilities (snail hide, slug slime, beetle charge, spore clouds + split), loot/inventory/equipment, shop + quest NPCs, 4-quest chain, SwiftData saves ✅
3. World & polish: mob separation, day/night (sim clock → sun/moon, sky, Metal post-process grade + depth fog, fireflies), synthesized spatial audio + ambience, controller rumble, classes at 15 (level cap 30), buffs, ranged combat, flying, zone banners ✅
4. Owl world boss: nightly spawn in the Great Bough, swoop / wing gust / summon+enrage phases with ground telegraphs, shared participant rewards, quest, boss bar + battle theme, Game Center achievements ✅
4.5. Bigger world: outer ring (6 zones, levels 14–30), 17 new mobs, level 13–30 gear tier, Thistledown set, 6-quest chain ✅
5. Online: Linux server running GameCore, Sign in with Apple / Game Center
