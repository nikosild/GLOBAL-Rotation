# GLOBAL Rotation

**A universal, fully configurable, class-agnostic spell rotation plugin for Diablo IV.**

This plugin reads your skill bar automatically, exposes every spell through a detailed in-game configuration menu, and fires them in the correct order every frame — handling priorities, cooldowns, charges, targeting, buff conditions, resource conditions, health conditions, combo chains, cast sequences, channel spells, gap closers, and the Hardcore Evade skill, all without writing a single line of code.

---

## Table of Contents

1. [What It Does](#1-what-it-does)
2. [File Structure](#2-file-structure)
3. [Getting Started](#3-getting-started)
4. [Menu Layout](#4-menu-layout)
5. [Global Settings](#5-global-settings)
6. [Build Profile System](#6-build-profile-system)
7. [Overlay (HUD)](#7-overlay-hud)
8. [Debug Mode](#8-debug-mode)
9. [Evade Settings](#9-evade-settings)
10. [Equipped Spells and Other Known Spells](#10-equipped-spells-and-other-known-spells)
11. [Per-Spell Basic Settings](#11-per-spell-basic-settings)
12. [Target Modes](#12-target-modes)
13. [Advanced Settings — per spell](#13-advanced-settings--per-spell)
14. [Combo Chain](#14-combo-chain)
15. [Sequence Formula](#15-sequence-formula)
16. [Profile Files and Class Switching](#16-profile-files-and-class-switching)
17. [Supported Classes](#17-supported-classes)
18. [Practical Tips and Examples](#18-practical-tips-and-examples)

---

## 1. What It Does

Most rotation plugins are written for one specific class and hardcode every spell ID. This plugin is different. It reads your skill bar at runtime and builds the spell list dynamically — you never need to touch a configuration file or know your spell IDs. Swap your build, change your skills, switch class — the plugin detects everything automatically and loads the right settings.

Every spell gets its own configuration panel inside the in-game menu. You decide the priority order, what conditions must be met before it fires, what targeting mode to use, whether it is a channel or a gap closer, whether it should trigger as part of a precise sequence, and much more.

The engine runs every frame and decides what to cast based on your configuration. It tracks its own cooldowns, manages charges, checks buffs and resources, enforces cast sequences, and handles the Hardcore Evade skill independently from the skill bar.

---

## 2. File Structure

```
global_rotation_alitis/
├── main.lua              — Entry point, update loop, overlay renderer, profile I/O
├── gui.lua               — All GUI elements and render logic
└── core/
    ├── spell_config.lua  — Per-spell UI elements, data access, and profile apply
    ├── rotation_engine.lua — Cast loop, priority engine, evade, sequences, combos
    ├── target_selector.lua — Enemy scanning, filtering, and target picking
    ├── spell_tracker.lua — Cooldown and charge state tracking
    ├── buff_provider.lua — Live buff list helpers for buff condition dropdowns
    └── profile_io.lua    — JSON serialization and file read/write
```

Saved profile files appear alongside the scripts, named `global_rotation_<class>_<buildname>.json`.

---

## 3. Getting Started

1. Copy the `global_rotation_alitis` folder into your plugins directory.
2. Load the plugin in-game through the plugin manager.
3. Open the plugin menu and expand **GLOBAL Rotation | ALiTiS**.
4. Tick **Enable** at the top.
5. Open **Equipped Spells** — every spell on your current skill bar appears as a collapsible entry.
6. Expand each spell and configure it (see sections 11–15 below).
7. The rotation runs automatically every frame from that point on.

There is nothing to install, no external files to edit, and no spell IDs to look up. The plugin reads everything from the game.

---

## 4. Menu Layout

The top-level menu is organized as follows:

```
GLOBAL Rotation | ALiTiS | v2.0
├── Enable
├── Use Keybind  /  Toggle Key
├── Global Settings
│   ├── Scan Range
│   ├── Animation Delay
│   ├── Build Profile
│   │   ├── Build Name (dropdown)
│   │   ├── Import Build Profile
│   │   └── Export Build Profile
│   ├── Overlay  (toggle)
│   │   └── Display Overlay Settings
│   │       ├── Overlay X / Y
│   │       ├── Font Size
│   │       ├── Line Gap
│   │       └── Show Active Buff List
│   └── Debug Mode
├── Evade Settings
│   ├── Enable Evade
│   ├── Cooldown (s)
│   ├── Fire on Danger Zone
│   ├── Auto Engage
│   │   └── Engage Distance
│   ├── Sequence Formula (subfolder)
│   └── Combo Chain (subfolder)
├── Equipped Spells
│   └── [Each spell on your bar]
│       ├── Enable / Priority / Spell Type / Target / Range / AOE Radius
│       ├── Min Enemies / Skip Small Packs / Use on Elite-Champion-Boss Only
│       └── Advanced Settings
│           ├── Use on Cooldown
│           ├── Require Buff
│           ├── Self Cast
│           ├── HP Condition
│           ├── Resource Condition
│           ├── Channel Spell
│           ├── Movement Spell (Gap Closer)
│           ├── Movement Spell (On Danger)
│           ├── Combo Chain
│           └── Sequence Formula
└── Other Known Spells
    └── [Spells seen previously but not currently on bar]
```

---

## 5. Global Settings

These settings apply to the whole rotation, not to any individual spell.

### Enable

The master on/off switch. When unchecked, the plugin does nothing. You can also control this with a keybind instead of the checkbox.

### Use Keybind / Toggle Key

When **Use Keybind** is enabled, the rotation only runs while the assigned key is in an active state. Use this to quickly suspend the rotation mid-fight without opening the menu. Set the key using the **Toggle Key** picker that appears below.

### Scan Range

How far from the player (in game units) to search for enemies. Enemies outside this radius are not considered by the engine. Default is 16.

Increase this for ranged builds that need to pick up enemies from a distance. Decrease it if you want the rotation to focus only on enemies that are already close.

### Animation Delay (s)

A small pause (in seconds) injected after every successful cast. This gives the game client time to register the animation and prevent casts from being sent faster than the game can process them. Default is 0.05 seconds. Increasing this can help on high-latency connections.

---

## 6. Build Profile System

Each class supports multiple named builds saved as separate JSON files. This lets you maintain completely independent configurations for, say, a bossing build and a farming build, and switch between them in seconds.

The **Build Profile** folder lives inside Global Settings and contains three options:

### Build Name

A dropdown with 12 preset names: Default, Burst, Farm, Boss, Safe, Speed, AoE, Single Target, Leveling, Endgame, Custom A, Custom B.

The selected name determines the filename used when saving or loading. Each name is a separate file. Changing the Build Name does not immediately load or save anything — it only changes which file the next Import or Export will act on.

### Import Build Profile

Loads the JSON file that matches the current class and selected Build Name. All spell settings, global settings, and overlay settings stored in that file are applied immediately, overwriting whatever is currently configured.

If no file exists for the selected build name, the plugin falls back to the old single-file format (without a build name in the filename) for backward compatibility.

### Export Build Profile

Saves all current settings — global options, overlay, and every configured spell — to a JSON file named `global_rotation_<class>_<buildname>.json`. The file is written to the plugin folder.

**Workflow example:** Configure your sorcerer for bossing. Set Build Name to `Boss`. Click Export. Then configure it for farming. Set Build Name to `Farm`. Click Export. Now you have two separate files. To swap builds: change Build Name to the one you want and click Import.

---

## 7. Overlay (HUD)

The overlay is a lightweight on-screen display that renders every frame on top of the game. It shows the state of your rotation at a glance.

### Overlay (toggle)

Shows or hides the HUD entirely. When disabled, nothing is rendered.

### Display Overlay Settings

Appears as a subfolder when the Overlay toggle is on.

| Setting | What it does |
|---|---|
| **Overlay X** | Horizontal pixel position of the top-left corner of the overlay. |
| **Overlay Y** | Vertical pixel position of the top-left corner of the overlay. |
| **Font Size** | Size of the overlay text. Range: 12 to 19. Default: 14. |
| **Line Gap** | Extra pixels added between each line. Range: 0 to 5. Default: 0. Increase for a more spacious look. |
| **Show Active Buff List** | When enabled, adds a section below the spell list showing all buffs currently active on your character, with stack counts and remaining durations. |

### What the Overlay Shows

```
[ GLOBAL Rotation | ALiTiS ]
Resource: 74%
6 spells | 3 enemies
[1] Fireball       (RDY)   ← green
[2] Meteor         (CD)    ← yellow
[3] Flame Shield   (RDY)   ← green
[4] Teleport       (N/A)   ← red
...
[ Active Buffs ]
Burning Instinct (2)  4.3s
...
```

- **Resource %** — your current primary resource as a percentage. Only shown if the game API returns a valid value.
- **Spell count / Enemy count** — how many spells are enabled and how many enemies are within scan range.
- **Spell list** — up to 6 enabled spells sorted by priority. Each line shows the priority number, the spell name, the charge count if the spell has multiple charges, and the current status:
  - `(RDY)` in green — ready to cast right now
  - `(CD)` in yellow — on cooldown
  - `(N/A)` in red — not castable (not ready or not affordable)

---

## 8. Debug Mode

When **Debug Mode** is enabled, every successful cast prints a line to the console showing the spell name, ID, priority, and (for targeted spells) the target mode used. For evade casts it prints whether it was a danger-zone fire or an auto-engage dash.

Use this while setting up your rotation to confirm that spells are firing in the order you expect. It is also useful for finding spell IDs — when you manually cast a spell in-game, its ID will appear in the console if Debug Mode is active.

Turn this off during normal gameplay to keep the console clean.

---

## 9. Evade Settings

Evade is the universal movement ability available to all Hardcore players. It does not appear on the skill bar like normal spells, so it has its own dedicated configuration section.

The spell ID **337031** is hardcoded — no lookup or manual entry is needed.

### Enable Evade

The master toggle for all evade automation. When off, the plugin never touches Evade regardless of other settings.

### Cooldown (s)

The minimum time (in seconds) between Evade casts. This prevents the plugin from spamming the ability. Default is 1.0 second. Adjust based on how frequently your character recharges Evade.

### Fire on Danger Zone

When enabled, the plugin detects when the player steps into a marked danger area — a ground AoE indicator, a boss attack zone, or any area flagged by the evade system — and immediately fires Evade. This check runs before the normal rotation every frame, so it is never blocked by a spell cast or a GCD.

This is the most important setting for Hardcore survival. Enable it and set an appropriate cooldown to ensure Evade is always available when you need it.

### Auto Engage

When enabled, if Evade is off cooldown and the player is not currently in a danger zone, the plugin uses Evade to dash toward the nearest valid target. This effectively replaces manual movement by dashing you into range before each combat sequence.

**Important:** Auto Engage will not fire if the player is in a danger zone — danger zone avoidance always takes priority. If you want Evade to be used only for survival and never for engaging, leave Auto Engage off.

### Engage Distance

Only visible when Auto Engage is on. This is how many units short of the target the dash will stop. A value of 2.5 (default) places you slightly in front of the target rather than on top of it, which is generally ideal for melee. Set to 0 to dash directly onto the target.

### Sequence Formula (subfolder)

Evade can be placed as a numbered step inside a cast sequence. This is useful when a skill has a mechanic that procs when cast immediately after a dodge. See the Sequence Formula section for full details on how sequences work.

Inside this subfolder you can enable sequencing for Evade, assign it a step number, set the window duration, choose the On Cooldown behavior, and assign it to a named sequence shared with your bar spells.

### Combo Chain (subfolder)

After Evade fires — whether from a danger zone trigger or an auto-engage dash — it can temporarily boost the priority of another spell. This is useful for chaining Evade into a skill that benefits from being cast immediately after a dodge.

Inside this subfolder you can enable the combo chain, choose which bar spell to boost, set the boost window duration, and set the boost amount.

---

## 10. Equipped Spells and Other Known Spells

### Equipped Spells

This section lists every spell currently on your skill bar. Each spell appears as a collapsible entry labeled with the spell name. Expand it to access all configuration options for that spell.

The list is refreshed every 2 seconds. If you swap a skill, the new one appears automatically on the next scan.

### Other Known Spells

This section lists spells that were seen on your bar in a previous session or earlier in the current session, but are not currently equipped. Their settings are preserved so you do not lose your configuration when you temporarily swap a skill.

You can still configure spells in this section. If you re-equip a spell from here, it moves back into Equipped Spells and its saved settings are immediately active.

---

## 11. Per-Spell Basic Settings

These settings are shown directly under each spell, outside the Advanced Settings folder.

### Enable

Include this spell in the rotation. When unchecked, the spell is completely skipped — it will not be cast, tracked, or considered for sequences or combos. Use this to temporarily disable a spell without losing its configuration.

### Priority (1 = highest)

The cast order. The rotation sorts all enabled spells by priority every frame and tries them in order from lowest number to highest. Priority 1 fires before priority 2, which fires before priority 3, and so on.

If two spells have the same priority, they are tried in the order they appear on the bar.

Set your highest-damage cooldown to priority 1. Set filler abilities or builders to higher numbers. Defensive or utility spells can be placed anywhere depending on how urgently you want them to fire.

### Spell Type

Controls how the engine handles positioning for this spell.

- **Auto** — the default. The engine casts at target position without any special movement logic.
- **Melee** — the engine will move the character toward the target if they are out of the spell's range before attempting to cast. Use this for melee attacks or short-range abilities.
- **Ranged** — like Auto, but explicitly marks the spell as ranged. No movement is triggered.

### Target Mode / Target Selection

Determines which enemy is chosen as the target. See section 12 for full details on all available modes.

### Spell Range / Engage Range

The maximum distance at which this spell will be used. If no valid enemy is within this range, the spell is skipped this frame.

When Spell Type is set to Melee, this field is labeled **Engage Range** and defines the distance at which the engine stops moving and attempts the cast.

### AOE Check Radius

The radius used for several other checks: Min Enemies, Skip Small Packs, and the Cleave Center target mode. It does not affect spell range itself — it is only used for counting nearby enemies.

### Min Enemies Near You

The minimum number of enemies that must be within the AOE check radius before the spell is allowed to fire. Set to 0 to always cast regardless of enemy count. Use higher values for AoE spells that are only efficient against groups.

Example: set Min Enemies to 3 on a Meteor spell so it only casts when at least 3 enemies are nearby.

### Skip Small Packs

When enabled, this spell is skipped unless a sufficient number of enemies are grouped within the AOE check radius. This is different from Min Enemies — it is specifically about group density and is intended to prevent spending strong AoE spells on thinly spread enemies or isolated targets when you are moving toward a larger group.

When Skip Small Packs is enabled, a second slider appears:

**Min Pack Size** — the minimum number of enemies required within the AOE radius for the group to be considered worth attacking. Default is 3. Range is 2 to 15.

### Use on Elite / Champion / Boss Only

When enabled, this spell is completely skipped against normal enemies. It only fires when the current target pool includes at least one elite, champion, or boss. Use this for major damage cooldowns, powerful debuffs, or anything you want to save for high-value targets and not waste on trash mobs.

---

## 12. Target Modes

The target mode controls which enemy the spell is aimed at. This is set per spell using the **Target Selection** dropdown.

### Priority

The default mode. The engine picks enemies in this order of preference: Boss → Elite → Champion → Closest. Always targets the highest-value enemy available within range. Use this for most spells.

### Closest

Always targets the nearest enemy within range. Useful for quickly clearing nearby threats or for melee spells where you want to hit whatever is immediately in front of you.

### Lowest HP

Targets the enemy with the least health remaining. Use this for execute-range finishers or spells that want to secure kills.

### Highest HP

Targets the enemy with the most health remaining. Useful for damage-over-time spells or debuffs where you want to prioritize enemies that will survive long enough to make the effect worthwhile.

### Cleave Center

Finds the enemy that has the most other enemies within the AOE check radius around it. This is the ideal center point for ground-targeted AoE spells like Meteor, Blizzard, or Corpse Explosion. Instead of just hitting the closest enemy, it places the spell where it hits the most targets at once.

---

## 13. Advanced Settings — per spell

Every spell has an **Advanced Settings** subfolder. Click it to expand the following options.

### Use on Cooldown

This setting reverses the usual buff logic for this spell. Instead of waiting for a buff to be present before casting, the spell is cast whenever the selected buff is **not** active.

This is designed for spells that generate or maintain a buff on the player. Enable it, then pick the buff from the Require Buff dropdown. The engine will cast this spell the moment that buff expires, keeping it permanently active without any manual tracking.

### Require Buff

When enabled, this spell only fires if a specific buff is currently active on the player. A dropdown lists all buffs currently on your character in real time. Select the one you want to require.

If you saved a buff selection but that buff is not currently active, it appears in the list as `(missing)` so your configuration is not lost.

**Min Stacks** — an additional slider that sets the minimum number of stacks the buff must have before the spell is allowed. Default is 1.

### Self Cast

When enabled, this spell is cast on the player's own position with no enemy target required. Target Mode and all enemy filters are completely ignored.

Use this for:
- Buff spells that are applied to yourself
- AoE spells that are centered on the player
- Movement abilities that do not require a target direction
- Any defensive skill that should fire regardless of whether enemies are present

### HP Condition

When enabled, this spell only fires when the player's health is above or below a percentage threshold.

- **Below %** — fires when HP is low. Use for emergency heals, shields, or panic cooldowns.
- **Above %** — fires when HP is healthy. Use for aggressive cooldowns you only want active when you are not in danger of dying.

**HP Threshold %** sets the percentage value. For example, HP Condition = Below %, Threshold = 40% means the spell only fires when you are below 40% health.

### Resource Condition

When enabled, this spell only fires when your primary resource (mana, fury, energy, spirit, etc.) is above or below a percentage threshold.

- **Below %** — fires when resource is low. Use for builders or generators that you want to use when running empty.
- **Above %** — fires when resource is high. Use for spenders that you only want to fire when you have enough resource built up.

**Threshold %** sets the percentage. The check is skipped gracefully if the game API returns zero for the resource (which happens with some classes such as Rogue energy in certain states).

### Channel Spell

Mark this spell as a channeled ability — one that the engine holds down continuously while conditions are met, rather than casting once and moving on.

When Channel Spell is enabled:
- The engine starts the channel on the current target and keeps it active every frame.
- If the target moves, the engine updates the channel target position automatically.
- If conditions are no longer met (buff expires, HP condition fails, etc.) the engine stops the channel.

**Break for Cooldowns** — a sub-option that appears when Channel Spell is on. When enabled, the engine pauses the channel if a higher-priority spell with a shorter cooldown becomes ready, casts it, then resumes the channel automatically. This prevents important cooldowns from being locked out while you are channeling.

Examples of channel spells: Whirlwind (Barbarian), Incinerate (Sorcerer), Rapid Fire (Rogue).

### Movement Spell (Gap Closer)

Mark this spell as a gap-closing ability — a dash, teleport, or leap that repositions the character toward the target.

When enabled:
- This spell is removed from the normal priority rotation.
- Instead, the engine uses it automatically when a melee-type spell has a valid target but the player is out of that spell's range.
- The engine moves toward the target using this spell before attempting the melee cast.

Examples: Teleport (Sorcerer), Leap (Barbarian), Dash (Rogue).

### Movement Spell (On Danger)

Mark this spell as a danger-zone escape ability. This is for bar spells that can be used as a defensive dodge — not the universal Evade, but a skill-bar ability with similar movement behavior.

When enabled:
- This spell fires automatically the moment the player is detected inside a danger zone (a ground AoE indicator, boss attack marker, etc.).
- It bypasses the normal rotation entirely and fires before any priority evaluation.

The universal Evade skill (not on bar) is handled separately in the **Evade Settings** section with more options. Use this flag for bar skills only.

---

## 14. Combo Chain

The Combo Chain system lets one spell temporarily boost another spell's priority immediately after it fires. This creates combo windows — short periods where the next spell in a sequence gets elevated priority.

### How It Works

After spell A fires successfully, the engine temporarily reduces spell B's effective priority by the **Priority Boost** amount for the duration of the **Combo Window**. A lower priority number means it fires sooner.

For example: spell A has Combo Chain enabled, targeting spell B (base priority 6) with a boost of 4 and a window of 2 seconds. For the next 2 seconds after A fires, spell B has effective priority 2 instead of 6, meaning it will fire next unless something with priority 1 is ready.

If a stronger boost is already active on spell B (from a different source), the weaker one is ignored — the stronger boost always wins.

### Settings

| Setting | Description |
|---|---|
| **Combo Chain** | Enable or disable the combo chain for this spell. |
| **Chain to Spell** | The spell that gets the priority boost. Includes all bar spells plus Evade. |
| **Combo Window (s)** | How many seconds the boost lasts after this spell fires. |
| **Priority Boost** | How much to subtract from the target spell's base priority during the window. |

### Use Cases

- After casting a debuff, boost the big damage spell that benefits from the debuff.
- After Evade, boost a skill that procs an effect when cast after a dodge.
- After a builder, boost a spender to fire immediately.

---

## 15. Sequence Formula

The Sequence Formula system enforces strict cast order across multiple spells. It is the most powerful feature for classes that have combos where order matters — opener rotations, buff proc chains, multi-step burst windows.

### Concept

Assign the same **Sequence Name** to a group of spells, and give each one a unique **Step** number. The engine then enforces that step 1 fires first, step 2 only fires after step 1 has landed, step 3 only after step 2, and so on.

Step 1 is always available and competes normally in the priority system. Steps 2 and beyond are suppressed until their turn arrives.

When the final step fires, the sequence resets and starts again from step 1.

### Settings

| Setting | Description |
|---|---|
| **Sequence Formula** | Enable sequencing for this spell. |
| **Step** | The position of this spell in the sequence. Step 1 fires freely. Steps 2+ fire only after the previous step has landed. |
| **Window (s)** | How many seconds the engine waits for the next step before resetting the whole sequence back to step 1. Default: 2s. If you land step 1 but do not land step 2 within this time, the sequence resets. |
| **Sequence Name** | The shared name that groups spells into one sequence. All spells with the same name and consecutive step numbers form a group. Pick from existing names or choose a preset from the list. |
| **On Cooldown** | What to do if the expected step is ready by sequence but the spell itself is still on cooldown. |

### On Cooldown Behaviors

This is a critical setting for sequences. When the due step is on cooldown, the engine has four options:

| Option | What Happens |
|---|---|
| **Pause (cast others freely)** | The sequence lock is released for this frame. Other spells outside the sequence cast normally. The sequence window timer keeps running. When the step comes off cooldown and the window has not expired, it fires and the sequence continues. Good for situations where other spells should fill gaps. |
| **Wait (hold all)** | Nothing fires at all until the due step is off cooldown. The rotation is held completely. Use this only for strict step-by-step combos where inserting any other spell would ruin the timing. |
| **Skip (advance)** | The due step is skipped immediately and the sequence moves to the next step. Use when a step being on cooldown means the window for that combo has passed and you want to get to the next step. |
| **Reset (restart)** | The sequence aborts and restarts from step 1. Use when the combo is only worth doing if every step lands — if one step is on cooldown, the whole thing is meaningless and you want to start fresh. |

### Evade in Sequences

Evade can also participate in sequences. Its Sequence Formula settings are in the **Evade Settings** section under the Sequence Formula subfolder. This lets you create combos like: Evade (step 1, dash forward) → Skill A (step 2, fires with its proc buff) → Skill B (step 3, finisher).

### Example

A Sorcerer opener: Teleport into range (step 1) → Ice Blades (step 2) → Frozen Orb (step 3) → Ice Spike execute (step 4). All four spells share the sequence name `Opener`. The engine fires them in order, with a 2-second window between each step.

---

## 16. Profile Files and Class Switching

### Automatic Class Detection

The plugin reads your character class every frame. When you first load, it automatically imports the profile for your current class and current Build Name. When you switch to a different character of a different class, it exports the current settings first, then imports the profile for the new class.

### File Naming

Profile files are stored in the plugin folder alongside the Lua scripts. They are named:

```
global_rotation_<class>_<buildname>.json
```

Examples:
```
global_rotation_sorcerer_default.json
global_rotation_sorcerer_boss.json
global_rotation_barbarian_farm.json
global_rotation_rogue_speed.json
```

### Backward Compatibility

If a file with the current build name does not exist, the plugin automatically looks for the old single-file format without a build name: `global_rotation_<class>.json`. This ensures settings from a previous version of the plugin are not lost.

### Manual Export and Import

Use the buttons inside the **Build Profile** folder in Global Settings to save and load profiles manually at any time. Import first loads the file that matches your current class and selected build name. Export writes all current settings to that same file.

---

## 17. Supported Classes

The plugin detects the following classes automatically:

| Class ID | Class Name |
|---|---|
| 0 | Sorcerer |
| 1 | Barbarian |
| 2 | Druid |
| 3 | Rogue |
| 6 | Necromancer |
| 9 | Paladin |

Any other class detected at runtime is saved under `global_rotation_class_<id>_<buildname>.json`.

---

## 18. Practical Tips and Examples

### Priority Setup

Think of priority like a sorted to-do list that the engine works through top to bottom every frame. Set your most valuable cooldown to priority 1, your second most important to priority 2, and so on. Filler spells or builders that you always want active but do not care when exactly they fire can sit at priority 8, 9, or 10.

If two spells have the same priority number, the engine tries them in bar order. This is usually fine for spells of equal importance.

### Combining Min Enemies with Skip Small Packs

Use these together to make an AoE spell smart:

- **Min Enemies = 1** means the spell will always fire if there is at least one enemy.
- **Skip Small Packs + Min Pack Size = 4** means the spell only fires when 4 or more enemies are grouped within the AOE radius.

Skip Small Packs is a harder filter — it completely prevents the cast when the group is too small, even if Min Enemies would pass. Use Min Enemies for soft gates and Skip Small Packs for stricter efficiency requirements.

### Evade for Hardcore Survival

Enable **Fire on Danger Zone** and set the cooldown to 0.5–1.0 seconds. The engine will fire Evade the instant you step into any marked danger area. Combined with **Auto Engage** (dash toward targets when not in danger), Evade becomes both your survival tool and your engagement tool — you are always moving efficiently.

### Use on Cooldown for Permanent Buffs

If you have a skill that applies a buff to yourself and you want that buff always active: enable **Use on Cooldown** in Advanced Settings, then select that buff in the Require Buff dropdown. The engine will fire the spell the moment the buff drops off. You never need to track buff duration manually.

### Combo Chain for Proc Mechanics

Many Diablo IV skills proc extra effects when cast after a specific action. Use Combo Chain to automate this:

1. On the triggering spell (the one that creates the proc condition), enable Combo Chain.
2. Set Chain to Spell to the spell that benefits from the proc.
3. Set a Combo Window of 1.5–2.0 seconds.
4. Set a Priority Boost of 4–5 so the proc spell jumps to near the front of the queue.

The engine will fire the proc spell immediately after the trigger, every time.

### Sequence Formula for Openers

A typical opener sequence might be:
- Gap closer / Teleport — Step 1, Sequence Name: `Opener`
- Primary debuff — Step 2, same name
- Big damage cooldown — Step 3, same name
- Spender / finisher — Step 4, same name

All four spells get Sequence Formula enabled and share the name `Opener`. The engine fires them in order. On Cooldown behavior is usually **Pause** for the opener so other spells can still fill gaps if a step is briefly on cooldown.

### Named Builds for Multiple Specs

Create one profile for each playstyle you use regularly. For example:

- **Boss** build: high single-target cooldowns at priority 1–3, AoE spells disabled or deprioritized, Use on Elite/Champion/Boss Only enabled on major cooldowns.
- **Farm** build: AoE spells at priority 1–2, Skip Small Packs set to 4, gap closer aggressive, cooldowns used freely.
- **Safe** build: defensive skills higher priority, HP Condition thresholds conservative, Evade cooldown short.

Switch between them with two clicks: change Build Name, click Import. Everything updates instantly.

---

*GLOBAL Rotation — ALiTiS — v2.0*
