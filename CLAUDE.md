# Minigames

iPad-first app (also runs on Mac via Mac Catalyst) built with SwiftUI + SpriteKit.

## Project structure

```
Minigames.xcodeproj/        — Xcode project (no workspace needed)
Minigames/
  MinigamesApp.swift        — @main entry point
  ContentView.swift         — root navigation list of minigames
  Platformer/
    PlatformerView.swift    — SwiftUI scene wrapper + on-screen controls
    PlatformerScene.swift   — SpriteKit physics world
  Assets.xcassets/
    Drawing.imageset/       — player texture (Drawing.png)
```

## Targets & platform

- iOS 17.0+ (iPad primary, iPhone secondary)
- Mac Catalyst (`SUPPORTS_MACCATALYST = YES`)
- Bundle ID: `com.minigames.app`

## Adding a new minigame

1. Create a new folder under `Minigames/` (e.g. `Minigames/Breakout/`)
2. Add a SwiftUI `View` as the entry point
3. Add a `NavigationLink` to that view in `ContentView.swift`
4. Add the new `.swift` files to the `Sources` build phase in `project.pbxproj`

## Controls convention

Games should support both:
- **Touch** — on-screen controls via `DragGesture(minimumDistance: 0)`
- **Keyboard** — via SwiftUI `.onKeyPress(keys:phases:)` (requires `.focusable()` + `@FocusState`)

## Build

```
xcodebuild -project Minigames.xcodeproj \
  -scheme Minigames \
  -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4)' \
  build
```
