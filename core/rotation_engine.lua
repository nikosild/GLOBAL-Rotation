local spell_config    = require 'core.spell_config'
local spell_tracker   = require 'core.spell_tracker'
local target_selector = require 'core.target_selector'
local buff_provider   = require 'core.buff_provider'

local rotation_engine = {}

local GLOBAL_GCD  = 0.05
local _gcd_until  = 0.0
local _scan_range = 12.0
local _move_until = 0.0

------------------------------------------------------------
-- Batmobile integration check
------------------------------------------------------------
local _batmobile_available = false
local _batmobile_checked = false
local _last_batmobile_setting = nil

local function check_batmobile()
    if _batmobile_checked then return _batmobile_available end
    _batmobile_checked = true
    
    if BatmobilePlugin then
        _batmobile_available = true
    end
    
    return _batmobile_available
end

local function print_batmobile_status(use_batmobile)
    if _last_batmobile_setting == use_batmobile then return end
    _last_batmobile_setting = use_batmobile
    
    if not _batmobile_available then
        if use_batmobile then
            console.print('[GLOBAL Rotation] Batmobile integration: NOT FOUND (basic pathfinding only)')
        end
    else
        if use_batmobile then
            console.print('[GLOBAL Rotation] Batmobile integration: ENABLED')
        else
            console.print('[GLOBAL Rotation] Batmobile integration: DISABLED')
        end
    end
end

------------------------------------------------------------
-- Stuck detection system for walls/obstacles
------------------------------------------------------------
local _stuck_check = {
    last_pos = nil,
    last_target = nil,
    stuck_time = 0,
    last_check = 0,
}

local function update_stuck_detection(player_pos, current_target)
    local now = get_time_since_inject()
    
    -- Only check every 0.5 seconds
    if now - _stuck_check.last_check < 0.5 then return false end
    _stuck_check.last_check = now
    
    -- Check if we have a target and position
    if not current_target or not player_pos then
        _stuck_check.stuck_time = 0
        _stuck_check.last_pos = nil
        _stuck_check.last_target = nil
        return false
    end
    
    -- Check if player position has changed
    local is_stuck = false
    if _stuck_check.last_pos then
        local dist_moved = target_selector.dist2(player_pos, _stuck_check.last_pos)
        -- If we moved less than 0.5 units in 0.5 seconds, we're stuck
        if dist_moved < 0.25 then
            _stuck_check.stuck_time = _stuck_check.stuck_time + 0.5
            is_stuck = _stuck_check.stuck_time >= 1.5 -- Stuck for 1.5+ seconds
        else
            _stuck_check.stuck_time = 0
        end
    end
    
    _stuck_check.last_pos = player_pos
    _stuck_check.last_target = current_target
    
    return is_stuck
end

local function handle_stuck_navigation(target, player_pos, settings)
    if not target or not player_pos then return false end
    
    local tpos = nil
    pcall(function() tpos = target:get_position() end)
    if not tpos then return false end
    
    check_batmobile() -- Ensure Batmobile status is checked
    
    -- Force Batmobile pathfinding when stuck (only if enabled)
    if _batmobile_available and settings.use_batmobile then
        console.print('[GLOBAL Rotation] Stuck detected (1.5s) - forcing Batmobile navigation')
        pcall(function() 
            BatmobilePlugin.set_target('global_rotation', tpos, true)
            BatmobilePlugin.update('global_rotation')
            BatmobilePlugin.move('global_rotation')
        end)
        _stuck_check.stuck_time = 0 -- Reset stuck timer
        _move_until = get_time_since_inject() + 0.5
        return true
    end
    
    return false
end

------------------------------------------------------------
-- AOE threshold
------------------------------------------------------------
local AOE_THRESHOLD = 3

function rotation_engine.set_aoe_threshold(n) AOE_THRESHOLD = n or 3 end
function rotation_engine.get_aoe_threshold()  return AOE_THRESHOLD    end

------------------------------------------------------------
-- Combo chain state
-- combo_boosts[spell_id] = { boost = N, expires = time }
--
-- Improvement over original:
--   * boost is now a SUBTRACTION from base priority (foreign approach):
--     effective_priority = base_priority - boost  (clamped to >= 1)
--     This is more predictable than overwriting with an absolute value.
--   * Only overwrites an existing active boost if the new boost is stronger,
--     so a weaker combo can never cancel a stronger one that's still running.
------------------------------------------------------------
local combo_boosts = {}

local function apply_combo_boost(cfg)
    if not cfg.combo_enabled then return end
    local target_id = cfg.combo_spell_id
    if not target_id or target_id <= 0 then return end

    local boost    = tonumber(cfg.combo_boost)   or 3
    local duration = tonumber(cfg.combo_window)  or 2.0
    local expires  = get_time_since_inject() + duration

    local existing = combo_boosts[target_id]
    if not existing
        or existing.expires < get_time_since_inject()
        or boost > (existing.boost or 0)
    then
        combo_boosts[target_id] = { boost = boost, expires = expires }
    end
end

local function get_combo_priority(spell_id, base_priority)
    local now   = get_time_since_inject()
    local boost = combo_boosts[spell_id]
    if not boost then return nil end
    if now > boost.expires then
        combo_boosts[spell_id] = nil
        return nil
    end
    -- Subtract from base priority; clamp so it never goes below 1
    local boosted = base_priority - boost.boost
    if boosted < 1 then boosted = 1 end
    return boosted
end

------------------------------------------------------------
-- SEQUENCE FORMULA STATE MACHINE
--
-- A "sequence" is a group of spells that share a seq_name
-- and must fire in ascending seq_step order.
--
-- State table (one entry per sequence name):
--   _seq_state[name] = {
--     expected_step  = int,         -- next step we're waiting for
--     window_expires = number|nil,  -- deadline to land expected_step
--   }
--
-- Per-tick logic:
--   1. Build seq_meta: seq_name -> { max_step, spells[] }
--      spells[] entries include the spell's cd_behavior setting.
--   2. Expire any sequence whose window has lapsed -> reset to step 1.
--   3. For every sequence with expected_step > 1 (i.e. mid-sequence),
--      check whether the due spell is currently on cooldown:
--
--        cd_behavior 0  Pause & cast freely:
--          Release the lock this tick — other spells compete normally.
--          The window timer keeps running. When the step comes off CD
--          (and the window hasn't expired) it will be promoted again.
--
--        cd_behavior 1  Wait (hold):
--          Suppress everything — nothing fires until the step is ready.
--          (Same as old behaviour.)
--
--        cd_behavior 2  Skip & advance:
--          Immediately advance expected_step past this step.
--          The skipped spell is treated as if it fired, using its window.
--
--        cd_behavior 3  Reset:
--          Abort — reset sequence to step 1.
--
--   4. After resolving CD behaviour, build filtered_list:
--        - Spells not in any sequence: always included.
--        - Spells whose step == expected_step: included, priority = 0.
--        - Spells at step 1 when sequence hasn't started: included normally.
--        - All other sequence spells: suppressed.
------------------------------------------------------------

local _seq_state = {}
-- _seq_state[name] = { expected_step = int, window_expires = float|nil }

local function _seq_reset(name)
    _seq_state[name] = { expected_step = 1, window_expires = nil }
end

local function _seq_get(name)
    local s = _seq_state[name]
    if not s then _seq_reset(name); return _seq_state[name] end
    -- Expire check
    if s.window_expires and get_time_since_inject() > s.window_expires then
        _seq_reset(name)
        return _seq_state[name]
    end
    return s
end

-- Called after a sequence step fires successfully
local function _seq_advance(name, fired_step, window_seconds)
    local s = _seq_state[name]
    if not s then return end
    if fired_step ~= s.expected_step then return end  -- stale signal, ignore
    s.expected_step  = fired_step + 1
    s.window_expires = get_time_since_inject() + (window_seconds or 3.0)
end

-- Build a per-tick lookup:
--   seq_meta[name] = {
--     max_step = int,
--     by_step  = { [step] = { spell_id, cd_behavior, seq_window } }
--   }
local function _build_seq_meta(spell_list)
    local meta = {}
    for _, entry in ipairs(spell_list) do
        local cfg = entry.cfg
        if cfg.seq_enabled and cfg.seq_name and cfg.seq_name ~= '' then
            local n = cfg.seq_name
            if not meta[n] then meta[n] = { max_step = 0, by_step = {} } end
            local step = cfg.seq_step or 1
            if step > meta[n].max_step then meta[n].max_step = step end
            meta[n].by_step[step] = {
                spell_id    = entry.spell_id,
                cd_behavior = cfg.seq_cd_behavior or 0,
                seq_window  = cfg.seq_window or 3.0,
            }
        end
    end
    return meta
end

------------------------------------------------------------
-- Buff check
------------------------------------------------------------
local function _player_has_buff(required_hash, min_stacks)
    if not required_hash or required_hash == 0 then return true end
    min_stacks = min_stacks or 1

    local player = get_local_player()
    if not player or type(player.get_buffs) ~= 'function' then return false end

    local buffs = player:get_buffs()
    if type(buffs) ~= 'table' then return false end

    for _, b in ipairs(buffs) do
        if b then
            local h = nil
            if type(b.get_name_hash) == 'function' then
                h = b:get_name_hash()
            elseif type(b.name_hash) == 'function' then
                h = b:name_hash()
            elseif type(b.name_hash) == 'number' then
                h = b.name_hash
            end

            if h == required_hash then
                local stacks = 0
                if type(b.get_stacks) == 'function' then stacks = b:get_stacks()
                elseif type(b.stacks) == 'number'   then stacks = b.stacks end
                return stacks >= min_stacks
            end
        end
    end
    return false
end

------------------------------------------------------------
-- Health condition check
------------------------------------------------------------
local function _check_hp_condition(cfg)
    if not cfg.use_hp_condition then return true end
    local lp = get_local_player()
    if not lp then return false end

    local cur = pcall(function() return lp:get_current_health() end) and lp:get_current_health() or 0
    local max = pcall(function() return lp:get_max_health() end)     and lp:get_max_health() or 1
    if max <= 0 then return true end

    local pct       = (cur / max) * 100
    local threshold = cfg.hp_threshold or 50

    if cfg.hp_mode == 0 then return pct < threshold
    else                     return pct >= threshold end
end

------------------------------------------------------------
-- Resource condition check (foreign implementation)
------------------------------------------------------------
local function _get_resource_pct()
    local lp = get_local_player()
    if not lp then return nil end

    local cur, max_r
    if type(lp.get_primary_resource_current) == 'function' then
        local ok, v = pcall(lp.get_primary_resource_current, lp)
        if ok and type(v) == 'number' then cur = v end
    end
    if type(lp.get_primary_resource_max) == 'function' then
        local ok, v = pcall(lp.get_primary_resource_max, lp)
        if ok and type(v) == 'number' then max_r = v end
    end
    -- If either is 0/nil we can't compute a reliable percentage — skip gracefully
    if not cur or not max_r or max_r <= 0 then return nil end
    if cur <= 0 then return nil end  -- Rogue energy / unreported resource
    return (cur / max_r) * 100.0
end

local function _check_res_condition(cfg)
    if not cfg.use_res_condition then return true end

    local pct = _get_resource_pct()
    if pct == nil then return true end  -- API unreliable, skip check gracefully

    local threshold = tonumber(cfg.res_threshold) or 50
    local mode      = tonumber(cfg.res_mode) or 1  -- 0=Below, 1=Above

    if mode == 0 then
        return pct < threshold   -- cast when resource is low
    else
        return pct >= threshold  -- cast when resource is high
    end
end

------------------------------------------------------------
-- Can player act?
------------------------------------------------------------
local function can_act()
    local lp = get_local_player()
    if not lp then return false end
    if lp:is_dead() then return false end

    if orbwalker and type(orbwalker.get_orb_mode) == 'function' then
        local mode = orbwalker.get_orb_mode()
        if mode ~= 3 then return false end
    end

    local pos = lp:get_position()
    if evade and evade.is_dangerous_position and evade.is_dangerous_position(pos) then
        return false
    end

    local active  = lp:get_active_spell_id()
    local blocked = { [186139]=true, [197833]=true, [211568]=true }
    if active and blocked[active] then return false end

    local ok, mount_val = pcall(function()
        return lp:get_attribute(attributes.CURRENT_MOUNT)
    end)
    if ok and mount_val and mount_val < 0 then return false end

    return true
end

------------------------------------------------------------
-- Try casting a spell
------------------------------------------------------------
local function try_cast(spell_id, target, player_pos, anim_delay)
    anim_delay = anim_delay or 0.05

    if not utility.is_spell_ready(spell_id) then return false end
    if not utility.is_spell_affordable(spell_id) then return false end

    local target_pos = target and target:get_position() or player_pos

    local ok = cast_spell.position(spell_id, target_pos, anim_delay)
    if ok then return true end

    if target then
        ok = cast_spell.target(target, spell_id, anim_delay)
        if ok then return true end
    end

    ok = cast_spell.self(spell_id, anim_delay)
    return ok or false
end

------------------------------------------------------------
-- Movement spell
------------------------------------------------------------
local function try_movement_spell(equipped_ids, target, player_pos, settings)
    if not target then 
        return false 
    end
    
    local now = get_time_since_inject()
    if now < _move_until then 
        return false 
    end

    local tpos = nil
    pcall(function() tpos = target:get_position() end)
    if not tpos then 
        return false 
    end

    -- Calculate distance to target
    local dist_sq = target_selector.dist2(player_pos, tpos)
    local distance = math.sqrt(dist_sq)
    

    -- ──────────────────────────────────────────────────────────────────────
    -- WALL / OBSTACLE DETECTION
    -- Check if target is reachable directly or if we need to use Batmobile
    -- ──────────────────────────────────────────────────────────────────────
    check_batmobile() -- Ensure Batmobile status is checked
    
    local can_reach = true
    if utility and type(utility.is_point_walkeable) == 'function' then
        -- Check if we can walk directly to the target
        local ok, result = pcall(function() return utility.is_point_walkeable(tpos) end)
        can_reach = ok and result or false
    end
    
    -- If we can't reach the target directly (wall/obstacle), use Batmobile first
    if not can_reach and _batmobile_available and settings.use_batmobile then
        pcall(function() 
            BatmobilePlugin.set_target('global_rotation', tpos, true)
            BatmobilePlugin.update('global_rotation')
            BatmobilePlugin.move('global_rotation')
        end)
        _move_until = now + 0.35
        return true
    end

    local movement_spell_found = false
    for _, spell_id in ipairs(equipped_ids) do
        if spell_id and spell_id > 1 then
            local cfg = spell_config.get(spell_id)
            if cfg.enabled and cfg.is_movement then
                movement_spell_found = true
                
                -- Check minimum range: skip if target is too close
                local min_range = cfg.min_range or 0.0
                if distance < min_range then
                    goto next_movement_spell
                end
                
                if utility.is_spell_ready(spell_id) and utility.is_spell_affordable(spell_id) then
                    if spell_tracker.is_off_cooldown(spell_id, cfg.cooldown, cfg.charges) then
                        -- Only try to cast movement spell if target is reachable
                        -- Otherwise let Batmobile handle it
                        if can_reach then
                            local ok = cast_spell.position(spell_id, tpos, settings.anim_delay or 0.05)
                            if ok then
                                spell_tracker.record_cast(spell_id, cfg.charges)
                                _move_until = now + 0.5
                                return true
                            else
                            end
                        else
                        end
                    else
                    end
                else
                end
                ::next_movement_spell::
            end
        end
    end

    -- Fallback to Batmobile for navigation (handles walls/obstacles automatically)
    -- This is controlled by a separate setting from wall/stuck detection
    if _batmobile_available and settings.use_batmobile and settings.enable_batmobile_fallback then
        pcall(function() 
            BatmobilePlugin.set_target('global_rotation', tpos, true)
            BatmobilePlugin.update('global_rotation')
            BatmobilePlugin.move('global_rotation')
        end)
        _move_until = now + 0.35
        return true
    end

    return false
end

------------------------------------------------------------
-- Channel spell state
------------------------------------------------------------
local _active_channel = nil

local function stop_channel()
    if not _active_channel then return end
    pcall(function() cast_spell.remove_channel_spell(_active_channel.spell_id) end)
    _active_channel = nil
end

local function is_channeling()
    if not _active_channel then return false end
    local ok, active = pcall(function()
        return cast_spell.is_channel_spell_active(_active_channel.spell_id)
    end)
    if ok and active then return true end
    _active_channel = nil
    return false
end

------------------------------------------------------------
-- Evade / movement skill handler
-- Spell ID 337031 is the Hardcore universal Evade — hardcoded, no bar slot needed.
-- Fires in two modes:
--   1. Danger: triggers when player is in an evade zone / AoE indicator.
--   2. Auto-engage: dashes toward the closest valid target when available.
-- Per-skill is_evade flag on bar spells also triggers on danger (source 3).
-- All sources run BEFORE the normal rotation.
------------------------------------------------------------
local EVADE_SPELL_ID = 337031

local function _try_evade_spell(equipped_ids, player_pos, anim_delay, settings, targets)
    local es = settings and settings.evade
    if not es or not es.enabled then
        -- Still check per-skill is_evade even if global evade is disabled
        goto check_bar_spells
    end

    do
        local in_danger = evade and type(evade.is_dangerous_position) == 'function'
                          and evade.is_dangerous_position(player_pos)

        local ready = utility.is_spell_ready(EVADE_SPELL_ID)
                      and utility.is_spell_affordable(EVADE_SPELL_ID)
                      and spell_tracker.is_off_cooldown(EVADE_SPELL_ID, es.cooldown or 1.0, 1)

        -- Mode 1: Fire on danger zone
        if es.on_danger and in_danger and ready then
            local ok = cast_spell.self(EVADE_SPELL_ID, anim_delay or 0.05)
            if not ok then
                ok = cast_spell.position(EVADE_SPELL_ID, player_pos, anim_delay or 0.05)
            end
            if ok then
                spell_tracker.record_cast(EVADE_SPELL_ID, 1)
                return true
            end
        end

        -- Mode 2: Auto-engage — dash toward target when not in danger and not reserved
        if es.auto_engage and not in_danger and ready then
            local target = targets and (targets.closest_boss or targets.closest_elite
                           or targets.closest_champ or targets.closest)
            if target then
                local tpos = nil
                pcall(function() tpos = target:get_position() end)
                if tpos then
                    -- Check minimum range: skip if target is too close
                    local min_range = es.min_range or 0.0
                    if min_range > 0 then
                        local dist_sq = target_selector.dist2(player_pos, tpos)
                        local distance = math.sqrt(dist_sq)
                        if distance < min_range then
                            goto skip_evade_engage
                        end
                    end
                    
                    -- Cast toward a point slightly short of the target
                    local cast_pos = tpos
                    local dist = es.engage_distance or 2.5
                    if dist > 0 and tpos.get_extended then
                        local ok2, mp = pcall(function()
                            return tpos:get_extended(player_pos, -dist)
                        end)
                        if ok2 and mp then cast_pos = mp end
                    end
                    local ok = cast_spell.position(EVADE_SPELL_ID, cast_pos, anim_delay or 0.05)
                    if ok then
                        spell_tracker.record_cast(EVADE_SPELL_ID, 1)
                        return true
                    end
                    ::skip_evade_engage::
                end
            end
        end
    end

    ::check_bar_spells::
    -- Source 3: per-skill Movement (On Danger) spells from the bar
    local in_danger = evade and type(evade.is_dangerous_position) == 'function'
                      and evade.is_dangerous_position(player_pos)
    if not in_danger then return false end

    for _, spell_id in ipairs(equipped_ids) do
        if spell_id and spell_id > 1 then
            local cfg = spell_config.get(spell_id)
            if cfg.enabled and cfg.is_evade then
                if utility.is_spell_ready(spell_id) and utility.is_spell_affordable(spell_id) then
                    if spell_tracker.is_off_cooldown(spell_id, cfg.cooldown, cfg.charges) then
                        local ok = cast_spell.self(spell_id, anim_delay or 0.05)
                        if not ok then
                            ok = cast_spell.position(spell_id, player_pos, anim_delay or 0.05)
                        end
                        if ok then
                            spell_tracker.record_cast(spell_id, cfg.charges)
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

------------------------------------------------------------
-- Main tick
------------------------------------------------------------
function rotation_engine.tick(equipped_ids, settings)
    -- Print batmobile status when setting changes
    check_batmobile()
    print_batmobile_status(settings.use_batmobile)
    
    if not can_act() then
        stop_channel()
        return false
    end

    local lp         = get_local_player()
    local player_pos = lp:get_position()
    local range      = settings.scan_range or _scan_range

    local targets = target_selector.get_targets(player_pos, range)
    
    -- ──────────────────────────────────────────────────────────────────────
    -- STUCK DETECTION: Check if bot is stuck targeting enemies behind walls
    -- ──────────────────────────────────────────────────────────────────────
    if targets.is_valid and targets.closest then
        local is_stuck = update_stuck_detection(player_pos, targets.closest)
        if is_stuck then
            -- Bot is stuck (not moving while having a target) - force pathfinding
            if handle_stuck_navigation(targets.closest, player_pos, settings) then
                return true
            end
        end
    else
        -- No targets, reset stuck detection
        update_stuck_detection(nil, nil)
    end

    -- Evade / movement spells fire first, before anything else
    if _try_evade_spell(equipped_ids, player_pos, settings.anim_delay, settings, targets) then
        return true
    end

    -- Only stop channel if no enemies; self_cast spells can still proceed below
    if not targets.is_valid or (targets.enemy_count or 0) <= 0 then
        stop_channel()
        -- Don't return yet — self_cast spells don't need enemies
    end

    -- ── Channel maintenance — only when enemies are present ──────────
    if targets.is_valid and (targets.enemy_count or 0) > 0 and is_channeling() then
        local ch  = _active_channel
        local cfg = ch.cfg

        local should_stop = false
        if cfg.require_buff and not _player_has_buff(cfg.buff_hash, cfg.buff_stacks) then should_stop = true end
        if not should_stop and not _check_hp_condition(cfg)  then should_stop = true end
        if not should_stop and not _check_res_condition(cfg) then should_stop = true end
        if not should_stop and not utility.is_spell_affordable(ch.spell_id) then should_stop = true end

        if should_stop then
            stop_channel()
        else
            if cfg.channel_break_for_cds then
                for _, spell_id in ipairs(equipped_ids) do
                    if spell_id and spell_id > 1 and spell_id ~= ch.spell_id then
                        local other_cfg = spell_config.get(spell_id)
                        if other_cfg.enabled and not other_cfg.is_channel and not other_cfg.is_movement then
                            if spell_tracker.is_off_cooldown(spell_id, other_cfg.cooldown, other_cfg.charges)
                                and utility.is_spell_ready(spell_id)
                                and utility.is_spell_affordable(spell_id) then

                                local other_ok = true
                                if other_cfg.boss_only  and not targets.has_boss  then other_ok = false end
                                if other_ok and other_cfg.elite_only and not targets.has_elite
                                    and not targets.has_boss and not targets.has_champion then other_ok = false end
                                if other_ok and other_cfg.require_buff and not _player_has_buff(other_cfg.buff_hash, other_cfg.buff_stacks) then other_ok = false end
                                if other_ok and not _check_hp_condition(other_cfg)  then other_ok = false end
                                if other_ok and not _check_res_condition(other_cfg) then other_ok = false end

                                if other_ok then
                                    local spell_range  = other_cfg.range or range
                                    local other_target = target_selector.pick_target(targets, other_cfg, player_pos, spell_range)
                                    if other_target then
                                        -- Cast the spell WITHOUT stopping the channel
                                        if try_cast(spell_id, other_target, player_pos, settings.anim_delay or 0.05) then
                                            spell_tracker.record_cast(spell_id, other_cfg.charges)
                                            _gcd_until = get_time_since_inject() + GLOBAL_GCD
                                            apply_combo_boost(other_cfg)
                                            -- Don't return - keep channeling!
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end

            local target = target_selector.pick_target(targets, cfg, player_pos, cfg.range or range)
            if target then
                local tpos = nil
                pcall(function() tpos = target:get_position() end)
                if tpos then
                    pcall(function()
                        cast_spell.update_channel_spell_position(ch.spell_id, tpos)
                    end)
                end
            end
            return true
        end
    end

    if get_time_since_inject() < _gcd_until then return false end

    -- ── Build candidate spell list ────────────────────────────────────
    local spell_list = {}
    for _, spell_id in ipairs(equipped_ids) do
        if spell_id and spell_id > 1 then
            local cfg = spell_config.get(spell_id)
            if cfg.enabled and not cfg.is_movement and not cfg.is_evade then
                local base_priority = cfg.priority or 5
                local eff_priority  = get_combo_priority(spell_id, base_priority) or base_priority

                table.insert(spell_list, {
                    spell_id     = spell_id,
                    cfg          = cfg,
                    name         = get_name_for_spell(spell_id) or tostring(spell_id),
                    eff_priority = eff_priority,
                })
                
            else
                -- Spell is movement or evade, skip
            end
        end
    end

    -- ── SEQUENCE FORMULA: resolve CD behaviour, then filter ───────────
    local seq_meta = _build_seq_meta(spell_list)

    -- Step 1: tick window expiry for all sequences that have spells on bar
    for name, _ in pairs(seq_meta) do
        _seq_get(name)  -- side-effect: resets if window expired
    end

    -- Step 2: for each sequence that is mid-progress (expected_step > 1),
    -- check whether the due step is on cooldown and apply cd_behavior.
    -- We only do this when the sequence is actively waiting (step > 1),
    -- because step 1 always competes freely with normal priority.
    local seq_paused = {}   -- [name] = true  →  release lock this tick (Pause mode)

    for name, state in pairs(_seq_state) do
        local meta = seq_meta[name]
        if not meta then goto next_seq end                    -- no spells on bar
        if state.expected_step <= 1 then goto next_seq end   -- not yet started

        local step_info = meta.by_step[state.expected_step]
        if not step_info then goto next_seq end               -- step not found (gap)

        local due_id  = step_info.spell_id
        local on_cd   = not spell_tracker.is_off_cooldown(
                            due_id,
                            spell_config.get(due_id).cooldown,
                            spell_config.get(due_id).charges)
                        or not utility.is_spell_ready(due_id)

        if on_cd then
            local behavior = step_info.cd_behavior  -- 0=Pause 1=Wait 2=Skip 3=Reset

            if behavior == 0 then
                -- Pause & cast freely: unlock this tick, keep state intact
                seq_paused[name] = true

            elseif behavior == 1 then
                -- Wait (hold): do nothing — the due step stays suppressed,
                -- other spells are also suppressed by the filter below.
                -- (no action needed; filtering handles it)

            elseif behavior == 2 then
                -- Skip: advance expected_step right now, reusing the window
                local skipped_step = state.expected_step
                if skipped_step >= meta.max_step then
                    _seq_reset(name)   -- skipping the last step = done
                else
                    state.expected_step = skipped_step + 1
                    -- keep window_expires as-is so we don't get extra time
                end

            elseif behavior == 3 then
                -- Reset: abort the whole sequence
                _seq_reset(name)
            end
        end

        ::next_seq::
    end

    -- Step 3: build filtered list
    local filtered_list = {}
    for _, entry in ipairs(spell_list) do
        local cfg = entry.cfg

        if not cfg.seq_enabled or not cfg.seq_name or cfg.seq_name == '' then
            -- Not part of any sequence — include normally
            filtered_list[#filtered_list + 1] = entry
        else
            local name    = cfg.seq_name
            local state   = _seq_get(name)
            local my_step = cfg.seq_step or 1

            if seq_paused[name] then
                -- Sequence is paused (cd_behavior=0, due step on CD).
                -- All spells in this sequence participate freely this tick,
                -- EXCEPT the due step itself (it still can't cast — it's on CD).
                -- Other steps are suppressed as usual to avoid sequence chaos;
                -- only non-sequence spells and the paused sequence's members
                -- that are NOT the stuck step may fire.
                -- Simplest safe rule: release ALL members this tick as normal
                -- priority competitors. The due step will fail its CD check
                -- in the cast loop anyway, so it won't fire.
                filtered_list[#filtered_list + 1] = entry

            elseif my_step == state.expected_step then
                -- This is the currently due step — highest priority
                entry.eff_priority = 0
                filtered_list[#filtered_list + 1] = entry

            elseif my_step == 1 and state.expected_step == 1 then
                -- Sequence not yet started; step 1 competes normally
                filtered_list[#filtered_list + 1] = entry

            else
                -- Not the due step and sequence is running — suppress
            end
        end
    end

    table.sort(filtered_list, function(a, b)
        return a.eff_priority < b.eff_priority
    end)


    -- ── Cast loop ─────────────────────────────────────────────────────
    for _, entry in ipairs(filtered_list) do
        local spell_id = entry.spell_id
        local cfg      = entry.cfg


        -- Self-cast spells skip the enemy-present requirement
        if not cfg.self_cast then
            if not targets.is_valid or (targets.enemy_count or 0) <= 0 then
                goto next_spell
            end
        end

        -- Skip cooldown check for channeled spells - they need to keep attempting to cast
        -- even during brief cooldowns to maintain movement toward targets
        if not cfg.is_channel then
            if not spell_tracker.is_off_cooldown(spell_id, cfg.cooldown, cfg.charges) then
                goto next_spell
            end
        end

        if not utility.is_spell_ready(spell_id) then
            goto next_spell
        end
        
        -- Skip resource check for channeled spells - they need to attempt casting even with low resources
        -- because the casting attempt makes the character walk toward targets
        if not cfg.is_channel then
            if not utility.is_spell_affordable(spell_id) then
                goto next_spell
            end
        end

        -- boss_only / elite_only / use_on_hard_only filters don't apply to self-cast
        if not cfg.self_cast then
            if cfg.use_on_hard_only then
                if not targets.has_boss and not targets.has_elite and not targets.has_champion then
                    goto next_spell
                end
            end
            if cfg.boss_only  and not targets.has_boss  then
                goto next_spell
            end
            if cfg.elite_only and not targets.has_elite
                and not targets.has_boss and not targets.has_champion
            then
                goto next_spell
            end
        end

        -- use_on_cooldown: cast when the tracked buff is NOT active (proc/reapply mode)
        if cfg.use_on_cooldown then
            if cfg.buff_hash and cfg.buff_hash ~= 0 then
                if _player_has_buff(cfg.buff_hash, 1) then
                    goto next_spell
                end
            end
        end

        if cfg.require_buff then
            if not _player_has_buff(cfg.buff_hash, cfg.buff_stacks) then
                goto next_spell
            end
        end

        if not _check_hp_condition(cfg) then
            goto next_spell
        end
        
        if not _check_res_condition(cfg) then
            goto next_spell
        end

        -- For channeled spells, use spell range for min_enemies check since they walk toward targets
        local aoe_check = cfg.is_channel and (cfg.range or range) or (cfg.aoe_range or 6.0)

        -- skip_small_packs: only cast when enough enemies are grouped
        if cfg.skip_small_packs then
            local pack_count = target_selector.count_near(targets, player_pos, aoe_check)
            if pack_count < (cfg.min_pack_size or 3) then
                goto next_spell
            end
        end

        if cfg.min_enemies > 0 then
            local nearby = target_selector.count_near(targets, player_pos, aoe_check)
            if nearby < cfg.min_enemies then
                goto next_spell
            end
        end

        -- ── Self-cast path ────────────────────────────────────────────
        if cfg.self_cast then
            local ok = cast_spell.self(spell_id, settings.anim_delay or 0.05)
            if not ok then
                ok = cast_spell.position(spell_id, player_pos, settings.anim_delay or 0.05)
            end
            if ok then
                spell_tracker.record_cast(spell_id, cfg.charges)
                _gcd_until = get_time_since_inject() + GLOBAL_GCD
                apply_combo_boost(cfg)
                if cfg.seq_enabled and cfg.seq_name and cfg.seq_name ~= '' then
                    local meta = seq_meta[cfg.seq_name]
                    local max_step = meta and meta.max_step or cfg.seq_step
                    if cfg.seq_step >= max_step then _seq_reset(cfg.seq_name)
                    else _seq_advance(cfg.seq_name, cfg.seq_step, cfg.seq_window) end
                end
                return true
            end
            goto next_spell
        end

        local spell_range = cfg.range or range
        
        local target = target_selector.pick_target(targets, cfg, player_pos, spell_range)
        if not target then
            local stype    = cfg.spell_type or 0
            local is_melee = (stype == 1) or (stype == 0 and (spell_range or 0) <= 6.0)
            if is_melee and targets.closest then
                try_movement_spell(equipped_ids, targets.closest, player_pos, settings)
            end
            goto next_spell
        end

        -- ── Check minimum engagement range ────────────────────────────────
        -- Force movement toward target if it's within spell range but beyond
        -- minimum engagement distance (for ranged skills that should be used at melee)
        -- Channeled spells always use 0 (no minimum), movement spells use min_range
        local min_range = cfg.is_channel and 0.0 or (cfg.min_range or 0.0)
        if min_range > 0 then
            local tpos = nil
            pcall(function() tpos = target:get_position() end)
            if tpos then
                local dist_sq = target_selector.dist2(player_pos, tpos)
                local distance = math.sqrt(dist_sq)
                
                
                -- Target is in spell range but too far from desired engagement distance
                if distance > min_range then
                    -- Count available movement spells
                    local movement_count = 0
                    for _, mid in ipairs(equipped_ids) do
                        if mid and mid > 1 then
                            local mcfg = spell_config.get(mid)
                            if mcfg.enabled and mcfg.is_movement then
                                movement_count = movement_count + 1
                            end
                        end
                    end
                    
                    if try_movement_spell(equipped_ids, target, player_pos, settings) then
                        goto next_spell  -- Movement spell cast, skip this spell for now
                    else
                    end
                    -- If no movement spell available or failed, fall through to normal cast
                end
            end
        end

        -- ── Channel path ──────────────────────────────────────────────
        if cfg.is_channel then
            local tpos = nil
            pcall(function() tpos = target:get_position() end)
            if tpos then
                
                -- Cast the channel spell - it will move us toward the target automatically
                local ok = pcall(function()
                    cast_spell.add_channel_spell(
                        spell_id,
                        0.0, 0.0,
                        target, tpos,
                        settings.anim_delay or 0.05,
                        0.1
                    )
                end)
                if ok then
                    _active_channel = { spell_id = spell_id, cfg = cfg }
                    spell_tracker.record_cast(spell_id, cfg.charges)
                    apply_combo_boost(cfg)
                    if cfg.seq_enabled and cfg.seq_name and cfg.seq_name ~= '' then
                        local meta = seq_meta[cfg.seq_name]
                        local max_step = meta and meta.max_step or cfg.seq_step
                        if cfg.seq_step >= max_step then
                            _seq_reset(cfg.seq_name)
                        else
                            _seq_advance(cfg.seq_name, cfg.seq_step, cfg.seq_window)
                        end
                    end
                    return true
                end
            end
            goto next_spell
        end

        -- ── Normal cast path ──────────────────────────────────────────
        if try_cast(spell_id, target, player_pos, settings.anim_delay or 0.05) then
            spell_tracker.record_cast(spell_id, cfg.charges)
            _gcd_until = get_time_since_inject() + GLOBAL_GCD
            apply_combo_boost(cfg)

            if cfg.seq_enabled and cfg.seq_name and cfg.seq_name ~= '' then
                local meta     = seq_meta[cfg.seq_name]
                local max_step = meta and meta.max_step or cfg.seq_step
                if cfg.seq_step >= max_step then
                    _seq_reset(cfg.seq_name)
                else
                    _seq_advance(cfg.seq_name, cfg.seq_step, cfg.seq_window)
                end
            end


            return true
        end

        ::next_spell::
    end

    return false
end

function rotation_engine.set_scan_range(r)
    _scan_range = r or 12.0
end

return rotation_engine
