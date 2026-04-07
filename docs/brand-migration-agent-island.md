# Agent Island Brand Migration

## Goal

Move the product brand from `Agent Island` to `Agent Island` while preserving runtime compatibility and keeping user-facing naming consistent.

## Migration Plan

### Phase 1: User-Facing Brand

- Rename app display name to `Agent Island`
- Rename bridge runtime to `agent-island-bridge`
- Rename runtime paths to:
  - `~/.agent-island`
  - `/tmp/agent-island.sock`
- Update GitHub links and release automation to:
  - `https://github.com/javen-yan/agent-island`
- Update README and public docs to use `Agent Island`

Status: in progress

### Phase 2: Runtime Compatibility

- Keep reading legacy bridge locations when present:
  - `~/.agent-island/hooks/agent-island-bridge`
- Keep legacy Python bridge in `reference/` only
- Avoid breaking existing installed environments during migration

Status: in progress

### Phase 3: Codebase Naming Cleanup

- Remove `Agent Island` from user-visible strings
- Rename brand-specific code symbols to neutral names
- Reduce `AgentIsland` wording in docs, comments, and helper names where safe
- Review whether bundle id and Xcode target names should be migrated in a separate step

Status: partially complete

### Phase 4: Visual Refresh

- Replace old crab-based brand iconography with new Agent Island identity
- Update app icon set
- Update notch header mark
- Update README/logo previews and release visuals

Status: pending design assets

## Already Migrated

- App display name is now `Agent Island`
- Rust bridge name is now `agent-island-bridge`
- Runtime install root is now `~/.agent-island`
- Runtime socket is now `/tmp/agent-island.sock`
- Menu GitHub link now points to `javen-yan/agent-island`
- Release script now points to `javen-yan/agent-island`
- Git remote now points to `https://github.com/javen-yan/agent-island.git`
- Notch activity type renamed from `.claude` to `.processing`
- `ClaudeCrabIcon` renamed to `IslandMarkIcon`
- Source file headers now use `Agent Island`
- Internal logger subsystem names now use `com.agentisland`

## Visual Assets To Replace

These are the current brand assets or brand-shaped UI pieces that still need a new Agent Island design.

### 1. App Icon Set

Path:
- `/Users/javen/Documents/Workspace/private/helper/agent-island/AgentIsland/Assets.xcassets/AppIcon.appiconset`

Files:
- `icon_16x16.png`
- `icon_32x32.png`
- `icon_32x32 1.png`
- `icon_64x64.png`
- `icon_128x128.png`
- `icon_256x256.png`
- `icon_256x256 1.png`
- `icon_512x512.png`
- `icon_512x512 1.png`
- `icon_1024x1024.png`

Need:
- new master icon and resized exports

### 2. Notch Header Brand Mark

Code:
- `/Users/javen/Documents/Workspace/private/helper/agent-island/AgentIsland/UI/Views/NotchHeaderView.swift`

Current symbol:
- `IslandMarkIcon`

Current state:
- still uses the old pixel crab drawing, only the symbol name is neutral now

Need:
- replace drawing with new Agent Island brand mark
- provide variants that still read clearly at very small sizes

Design handoff notes:
- this mark appears in the closed notch and the opened header
- current implementation is a tiny pixel-art silhouette, so the replacement should work in a similarly compact footprint
- recommended deliverables:
  - one 1x monochrome mark for code drawing replacement reference
  - one tiny raster fallback preview for validation at notch scale

### 3. Closed/Expanded Notch Brand Usage

Code:
- `/Users/javen/Documents/Workspace/private/helper/agent-island/AgentIsland/UI/Views/NotchView.swift`

Current usage:
- the header/closed-state brand mark still renders the old crab artwork via `IslandMarkIcon`

Need:
- verify new mark size, alignment, animation behavior, and permission indicator pairing

Affected surfaces:
- closed idle notch
- closed processing state
- opened chat header
- instances/monitor header

### 4. README / Marketing Preview

Paths:
- `/Users/javen/Documents/Workspace/private/helper/agent-island/README.md`

Current usage:
- README logo points to the current app icon asset

Need:
- update screenshots/logo previews after icon replacement

### 5. Design Replacement Checklist

These are the exact brand-shaped elements to redesign or visually verify:

- App icon master artwork
  - output target: all PNGs in `/Users/javen/Documents/Workspace/private/helper/agent-island/AgentIsland/Assets.xcassets/AppIcon.appiconset`
- Notch logo mark
  - source target: `IslandMarkIcon` in `/Users/javen/Documents/Workspace/private/helper/agent-island/AgentIsland/UI/Views/NotchHeaderView.swift`
- README hero logo preview
  - source target: top logo image in `/Users/javen/Documents/Workspace/private/helper/agent-island/README.md`
- Release DMG branding text
  - source target: `/Users/javen/Documents/Workspace/private/helper/agent-island/scripts/create-release.sh`

### 6. Suggested Asset Package For Design

If design work starts next, the most useful export set would be:

- 1024x1024 app icon master
- 256x256 icon preview
- 64x64 icon preview
- tiny notch mark reference at approximately 16-20 px visual size
- one screenshot mock for:
  - closed notch
  - monitor list
  - permission request card

## Remaining Naming Hotspots

These still contain old branding and should be cleaned in later passes:

- Xcode target and scheme names still use `AgentIsland`
- Bundle identifier still uses `com.celestial.AgentIsland`
- Legacy reference bridge file name remains `agent-island-state.py`
- Some runtime compatibility fallbacks still read legacy `.agent-island` paths

## Recommended Next Steps

1. Finalize visual identity for Agent Island
2. Replace app icon assets
3. Replace notch brand mark drawing
4. Re-export README/logo preview assets
5. Migrate remaining user-facing strings
6. Decide whether bundle id / target / scheme should be migrated in a dedicated compatibility pass
