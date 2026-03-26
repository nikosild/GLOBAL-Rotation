# GLOBAL Rotation | ALiTiS | v2.3

Universal rotation engine for Diablo 4 with advanced spell prioritization, channeling support, and intelligent targeting.

## Version: 2.3

---

## Changelog

### v2.3 (Latest)
**Major Features:**
- **Simultaneous Spell Casting During Channeling**: Bot now casts War Cry, Rallying Cry, Iron Skin, and other cooldowns WHILE channeling Whirlwind without interrupting the channel
- **Auto-Sync Channel Settings**: "Break for Cooldowns" automatically enables when "Channel Spell" is toggled ON and disables when toggled OFF (can be manually overridden)
- **Pause in Town**: New toggle that automatically pauses rotation when in any town (uses `PLAYER_IN_TOWN_LEVEL_AREA` attribute for universal detection)
- **Visual Range Indicators**: 
  - Global scan range circle (green) shown around player
  - Per-spell range circles (blue) for individual spells
  - Toggle in GUI: Global Settings → Overlay → "Show Global Scan Range Circle" and per-spell in Advanced Settings
- **GUI Reorganization**: "Build Profile" moved to end of Global Settings as its own main category (same level as Overlay)

**Channeling Improvements:**
- Fixed long-range channeling: Whirlwind now engages enemies at full spell range (30 yards) instead of just 6 yards
- Removed resource and cooldown checks for channeled spells to allow continuous channeling attempts
- Fixed `min_enemies` check to use spell range instead of AOE range for channeled spells
- Channel spells now trigger movement toward enemies even when cast attempts fail

**Technical Improvements:**
- Removed all debug logs added during troubleshooting (cleaner console output)
- State tracking for channel checkbox to prevent setting conflicts
- Safe town detection with fallback methods
- All range maximums increased from 50 to 30 yards for consistency

**Bug Fixes:**
- Fixed manual clicking on "Break for Cooldowns" checkbox (was being overridden every frame)
- Fixed range circle rendering for multiple spells simultaneously
- Fixed Build Profile category visibility and positioning

---

### v2.2
- Initial public release
- Barbarian default profile with Whirlwind support
- Spell prioritization system
- Movement spell support
- Batmobile integration
- Profile import/export system

---

## Features

### Core Systems
- **Universal Rotation Engine**: Works with all Diablo 4 classes
- **Advanced Spell Prioritization**: Priority-based casting with sequence and combo support
- **Channeling Support**: Full support for channeled spells (Whirlwind, Incinerate, etc.)
- **Smart Targeting**: Boss, elite, champion detection with configurable targeting modes
- **Movement Integration**: Automatic gap closing with dash/leap/charge spells
- **Range Management**: Per-spell range configuration with visual indicators

### Channeling Features (v2.3)
- Cast other spells while channeling without interrupting
- Auto-enable "Break for Cooldowns" when marking spells as channels
- Long-range engagement (up to 30 yards)
- Automatic movement toward targets while channeling
- No resource/cooldown blocking for continuous channeling

### GUI Features
- **Profile System**: Save/load multiple build configurations per class
- **Per-Spell Configuration**: Individual settings for each spell on your bar
- **Visual Range Circles**: See scan range and spell ranges in real-time
- **Pause in Town**: Automatic rotation pause when in any town
- **Debug Mode**: Optional console output for troubleshooting

### Integration
- **Batmobile Plugin**: Wall detection and pathfinding
- **Keybind Support**: Toggle rotation on/off with custom hotkey

---

## Installation

1. Place all `.lua` files in your Diablo 4 scripts folder
2. Create `profiles/` subfolder for build profiles
3. Load the plugin in your Lua loader
4. Configure spells in the GUI

---

## Quick Start

### Basic Setup
1. Enable the rotation: Check "Enable" in the main menu
2. Configure your spells: Each equipped spell appears in the "Spell Configuration" section
3. Set priorities: Lower number = higher priority (1 casts before 2)
4. Optional: Enable "Pause in Town" to stop rotation in towns

### Channeling Setup (e.g., Whirlwind)
1. Find your channel spell (e.g., Barbarian_Whirlwind)
2. Check "Channel Spell"
3. "Break for Cooldowns" automatically enables
4. Set range to 30 for long-range engagement
5. Bot will now cast buffs while spinning without stopping

### Visual Range Setup
1. Global Settings → Overlay → "Show Global Scan Range Circle" (green)
2. Per-spell → Advanced Settings → "Show Spell Range Circle" (blue)
3. Adjust ranges with sliders to see circles update in real-time

---

## Default Profiles

### Barbarian (barbarian_default.json)
- Whirlwind channeling rotation
- War Cry, Rallying Cry, Iron Skin support
- 30-yard engagement range
- Auto-buff while channeling

---

## Configuration Files

- **main.lua**: Core rotation logic
- **rotation_engine.lua**: Spell execution engine
- **spell_config.lua**: Per-spell settings management
- **gui.lua**: User interface
- **target_selector.lua**: Enemy targeting logic
- **buff_provider.lua**: Buff detection
- **spell_tracker.lua**: Cooldown tracking

---

## Support

For issues, suggestions, or contributions, please contact ALiTiS.

---

## Credits

- **Author**: ALiTiS
- **Version**: 2.3
- **Engine**: Universal Rotation System for Diablo 4
