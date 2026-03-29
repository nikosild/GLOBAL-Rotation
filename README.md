# GLOBAL Rotation | ALiTiS

Universal rotation engine for Diablo 4. Works with all classes — no class-specific configuration required out of the box.

## Version: 3.0

---

## What It Does

GLOBAL Rotation automates your spell rotation in Diablo 4. It reads your equipped skills, applies your configured priorities, and casts spells automatically based on targets, cooldowns, buffs, and combat conditions — all while you stay in control of movement.

---

## Features

### Rotation Engine
- Casts spells automatically based on configurable priority order
- Supports all spell types: instant, channeled, movement, self-cast
- Per-spell cooldown tracking with charge support
- Skips spells that are on cooldown, unaffordable, or blocked by conditions

### Spell Conditions (per spell)
- **Priority**: Lower number fires first (1 = highest priority)
- **Target Mode**: Priority (boss > elite > closest), Closest, Lowest HP, Highest HP, Cleave Center
- **Spell Type**: Auto, Melee, or Ranged — affects movement behavior before casting
- **Range**: Cast range and AoE check radius per spell
- **Min Enemies**: Only cast when enough enemies are nearby
- **Boss Only / Elite Only / Hard Only**: Restrict casting to specific enemy types
- **Skip Small Packs**: Skip spell if pack size is below a configurable threshold
- **Require Buff**: Only cast when a specific player buff is active (with stack requirement)
- **Use on Cooldown**: Cast only when a specific buff is NOT active (proc/reapply mode)
- **HP Condition**: Cast above or below a health percentage threshold
- **Resource Condition**: Cast above or below a resource percentage threshold
- **Self Cast**: Cast on yourself regardless of enemy presence
- **Is Movement (Gap Closer)**: Marks spell as a movement skill for auto-engage
- **Is Movement (On Danger)**: Fires movement spell when stepping into a danger zone
- **Is Channel**: Enables channeling mode — maintains cast while moving and casting other spells simultaneously
- **Break for Cooldowns**: While channeling, pauses to cast off-cooldown non-channel spells
- **Is Evade**: Marks spell as an evade for danger zone reaction
- **Show Range Circle**: Draws a blue circle on screen showing this spell's range

### Sequence Formula
Chain spells into an ordered sequence. Steps fire in order with a configurable window. If a step is on cooldown, choose how to handle it: Pause (cast freely), Wait (hold everything), Skip (next step), or Reset (restart sequence).

### Combo Chain
After a spell fires, temporarily boost another spell's priority for a configurable window. Useful for proc-based rotations.

### LAG Casting (Channel Spells)
- Full channeled spell support (Whirlwind, Incinerate, etc.)
- Casts other spells (buffs, cooldowns) while channeling without interrupting the channel
- Auto-engages enemies at configured range
- Automatically walks toward targets while channeling

### Evade System
Two independent evade modes — only one can be active at a time:
- **Classic Evade**: Fires evade automatically on a cooldown. Supports danger zone detection and auto-engage (dash toward target). Configurable cooldown, minimum range, and engage distance. Located inside Equipped Spells menu
- **Evade Replacement**: For classes whose Evade is replaced by a class-specific ability. Sends a real Space keypress via `magic.py`. Configurable cooldown, minimum enemy count, and scan range. Launches `magic.py` automatically when enabled

### Butcher Mode
Automatically activates when the Butcher buff is detected on the player. Settings panel is hidden when Butcher Mode is disabled. Supports six independent actions:
- **Hell Charge** (Key 1) — hardcoded 0.5s cooldown, always fires
- **Culling** (Key 2) — hardcoded 0.65s cooldown, always fires
- **Hail of Hooks** (Key 3) — hardcoded 0.8s cooldown, always fires
- **Furnace Blast** (Key 4) — hardcoded 0.95s cooldown, always fires
- **Carve** (Left Click) — hardcoded 0.1s cooldown, configurable min enemies (0 or 1, scan range hardcoded 12)
- **Molten Slam** (Right Click) — configurable cooldown (1–2s, integer steps) and scan range (5–6, integer steps), requires 1 nearby enemy

Python launches automatically when Butcher Mode is enabled and stops when both Butcher Mode and Evade Replacement are disabled. Optional keybind to toggle Butcher KeyMode on/off during gameplay.

### Targeting
- Scans for enemies within a configurable global range
- Prioritizes bosses, elites, and champions
- Filters dead, hidden, invulnerable, and town NPCs
- Configurable per-spell target selection mode

### Batmobile Integration
- Optional wall and obstacle detection
- Forced pathfinding when stuck behind geometry
- Fallback navigation toggle

### Overlay
- On-screen display showing spell readiness, cooldowns, and enemy count
- Spells displayed in skill bar order: keys 1–4 first, Left Click and Right Click last
- Each spell shows priority (`[Pr = N]`), custom or detected name, and status:
  - `(Ready)` — green, spell is ready to cast
  - `(Cooldown)` — yellow, spell is on cooldown
  - `(N/A)` — red, spell is not ready or unaffordable
- Configurable position, font size, and line spacing
- Optional active buff list display
- Global scan range circle (green) drawn around the player
- Per-spell range circles (blue)

### Profile System
- Save and load full configurations per class and build name
- Up to 12 named presets: Default, Burst, Farm, Boss, Safe, Speed, AoE, Single Target, Leveling, Endgame, Custom A, Custom B
- Auto-loads the matching profile when switching characters
- Auto-saves current settings when switching classes

### Pause in Town
Automatically pauses the rotation when in any town. Resumes when you leave.

### Keybind
Toggle the rotation on and off with a configurable hotkey.

### Debug Mode
Optional console output showing each cast attempt for troubleshooting.

### Skill Rename
Skills detected on the bar may display internal or abbreviated names. The rename system lets you assign correct display names that appear in both the Equipped Spells menu and the overlay. Names are stored in `custom_names.txt` in the script root folder — auto-generated on every bar scan with skills listed in order (keys 1–4 first, Left Click and Right Click last). Edit the name after `=`, save, and press F5 to reload.

---

## Skill Rename Setup

Some skills display internal or incorrect names in the menu and overlay. Use `custom_names.txt` to fix them — no GUI input needed.

### How It Works

1. Press **F5** to load the plugin — `custom_names.txt` is auto-generated in your script folder
2. Open `custom_names.txt` in Notepad — it lists all detected skills in order with their current names
3. Edit the name after `=` on any line
4. Save the file and press **F5** — names update immediately in the menu and overlay

### File Format

```
1) Old name: Punish (2097465)=Punish
2) Old name: Blessed Shield (2082021)=Blessed Shield
```

Change `Punish` to whatever you want — for example `=Holy Strike`. The number in parentheses is the spell ID and must stay unchanged.

---

## Installation

1. Place all files in your Diablo 4 scripts folder
2. Create a `profiles/` subfolder for build profiles
3. Load the plugin in your Lua loader

---

## Quick Start

1. Enable the rotation with the **Enable** checkbox
2. Open **Equipped Spells** — each skill on your bar appears here
3. Set **Priority** for each spell (1 = highest, fires first)
4. Set **Range** to match the spell's in-game range
5. Configure any conditions you need (boss only, buff requirement, etc.)
6. Enable **Pause in Town** to automatically stop in safe zones
7. Use **Build Profile → Export** to save your setup
8. Open **custom_names.txt** in Notepad to rename skills that show incorrect names in the menu and overlay

---

## Files

- **main.lua** — Core logic, profile management, update loop
- **rotation_engine.lua** — Spell execution, targeting, evade, channeling, Butcher mode
- **spell_config.lua** — Per-spell settings and GUI rendering
- **gui.lua** — User interface elements and layout
- **target_selector.lua** — Enemy detection and target selection
- **buff_provider.lua** — Player buff detection and listing
- **spell_tracker.lua** — Cooldown and charge tracking
- **profile_io.lua** — JSON profile save/load
- **custom_names.txt** — Custom skill name mappings (auto-generated, edit to rename skills)

---

## Support

For issues or suggestions, contact ALiTiS.

---

## Credits

- **Author**: ALiTiS
- **Engine**: Universal Rotation System for Diablo 4

---

## Changelog

### v3.0
- ⭐ **Butcher Mode**: Full automatic rotation system for Butcher form. Activates when Butcher is detected. Six configurable actions (Hell Charge, Culling, Hail of Hooks, Furnace Blast, Carve, Molten Slam). Keys 1-4 have hardcoded staggered cooldowns (0.5/0.65/0.8/0.95s). Carve has hardcoded 0.1s cooldown with configurable min enemies. Molten Slam has configurable cooldown (1-2s) and scan range (5-6), requires 1 nearby enemy
- **Butcher KeyMode Toggle**: Optional keybind to toggle Butcher key automation on/off during gameplay
- **Butcher Mode Auto-Launch**: Python helper (magic.py) launches automatically when Butcher Mode or Evade Replacement is enabled, stops when both are disabled
- **Evade System Overhaul**: Two distinct evade modes — Classic Evade and Evade Replacement. Mutual exclusion enforced automatically (enabling one disables the other). Independent cooldown timers for each mode
- ⭐ **Evade Replacement**: Advanced evade mode supporting class-specific form-based evade replacements. Configurable cooldown, minimum enemy count, and scan range. Sends real Space keypress via magic.py
- **Evade Settings GUI**: Restructured with clear instructions. Classic Evade and Evade Replacement presented as mutually exclusive options. Evade Settings moved inside Equipped Spells category
- **GUI Reorganization**: Butcher Mode Settings hidden when Butcher Mode is disabled. Evade Settings now inside Equipped Spells as first item
- **Display Order**: Equipped Spells menu and overlay now show skills in skill bar order — keys 1–4 first, Left Click and Right Click last
- **Overlay Labels**: Priority shown as `[Pr = N]` prefix on each spell line
- ⭐ **Skill Rename System**: Custom skill names via `custom_names.txt`. File auto-generates with current skill list on every bar scan. Edit names after `=`, save, press F5. Names appear in both the menu tree headers and the overlay. Format: `N) Old name: SkillName (SpellID)=CustomName`

## Butcher Mode Setup (First Time)
Butcher Mode requires a small Python helper that runs alongside the plugin and sends keypresses and mouse clicks to the game. Follow these steps once and you're done.
When you enable Butcher Mode, "python" launches automatically in the background. You do not need to start it manually.

### Step 1 — Install Python (one time only)
Download Python from the official website (You only need to do this once):
https://www.python.org/ftp/python/pymanager/python-manager-26.0.msix

### Step 2 — Place the files
Make sure all plugin files are in your scripts folder, including `magic.py`.
The file must be in the same folder as `main.lua`.

### Step 3 — Load the plugin
Open your Diablo IV bot loader and press **F5** (or load the script). The plugin will appear in the menu.

### Step 4 — Enable Butcher Mode
In the plugin menu:
1. Check **Butcher Mode** to enable it
2. The **Butcher Mode Settings** panel will appear below
3. Enable the actions you want (Hell Charge, Culling, Hail of Hooks, Furnace Blast, Carve, Molten Slam)
4. Adjust Molten Slam cooldown and scan range to your preference

### Step 5 — Enable Clear Mode
In your bot loader, activate **Clear Mode** (orbwalker mode 3). The rotation engine will now be active.

### Step 6 — Transform into the Butcher and have fun
Enter combat and transform into the Butcher.
The plugin detects BUTCHER automatically and starts firing your configured keys and clicks. 
When you leave Butcher form, it stops automatically.

---

## Evade Replacement Setup (First Time)
Evade Replacement requires the same Python helper as Butcher Mode.
If you already set up Butcher Mode, Python is already installed — Skip to Step 2.
Evade Replacement is designed for classes whose Evade key is replaced by a class-specific ability (e.g. Spiritborn, Druid forms, etc.).

### Step 1 — Install Python (one time only, skip if already done)
Download Python from the official website:
https://www.python.org/ftp/python/pymanager/python-manager-26.0.msix

### Step 2 — Place the files
Make sure `magic.py` is in the same folder as `main.lua`.

### Step 3 — Load the plugin
Press **F5** in your bot loader to load the plugin.

### Step 4 — Configure Evade Replacement
In the plugin menu:
1. Open **Equipped Spells → Evade Settings**
2. Enable **Evade Replacement** (do NOT enable Classic Evade at the same time — they are mutually exclusive)
3. Set **Cooldown** — how often the Space key fires automatically
4. Set **Min Enemies Nearby** — set to 0 to always fire on cooldown, or higher to only fire when enemies are present
5. If Min Enemies > 0, set **Enemy Scan Range** accordingly

### Step 5 — Enable Clear Mode and play
Activate **Clear Mode** in your bot loader. 
"Python" launches automatically when **Evade Replacement** is toggled ON, and stops when it is toggled OFF. No manual steps needed.
Evade Replacement will now fire Space automatically based on your configured cooldown and enemy conditions.

---

### v2.3
- **Simultaneous Spell Casting During Channeling**: Casts War Cry, Rallying Cry, Iron Skin, and other cooldowns while channeling Whirlwind without interrupting the channel
- **Auto-Sync Channel Settings**: "Break for Cooldowns" automatically enables when "Channel Spell" is toggled ON and disables when toggled OFF
- **Pause in Town**: Automatically pauses rotation when in any town using universal detection
- **Visual Range Indicators**: Global scan range circle (green) and per-spell range circles (blue) drawn on screen
- **GUI Reorganization**: Build Profile moved to end of Global Settings
- Fixed long-range channeling — Whirlwind now engages at full configured range
- Fixed min_enemies check for channeled spells
- Fixed "Break for Cooldowns" checkbox being overridden every frame
- Fixed range circle rendering for multiple spells simultaneously
- Removed all debug console spam from production build

### v2.2
- Initial release
- Barbarian default profile with Whirlwind support
- Spell prioritization system
- Movement spell support
- Batmobile integration
- Profile import/export system
