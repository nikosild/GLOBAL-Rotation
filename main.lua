local plugin_label = 'global_rotation_alitis'

local gui             = require 'gui'
local spell_config    = require 'core.spell_config'
local spell_tracker   = require 'core.spell_tracker'
local rotation_engine = require 'core.rotation_engine'
local profile_io      = require 'core.profile_io'
local buff_provider    = require 'core.buff_provider'

local equipped_ids  = {}   -- spell IDs currently on bar
local all_known_ids = {}   -- union of all ever-seen IDs (persists through bar swaps)
local all_known_set = {}

local scan_interval = 2.0  -- re-scan bar every 2 seconds
local last_scan     = -999

local last_class_key = nil

local settings = {
    scan_range         = 12.0,
    anim_delay         = 0.05,
    debug              = false,
    use_batmobile      = false,
    enable_batmobile_fallback = false,
    overlay_enabled    = true,
    overlay_x          = 20,
    overlay_y          = 12,
    overlay_font_size  = 14,
    overlay_line_gap   = 0,
    overlay_show_buffs = false,
    evade = {
        enabled                = false,
        cooldown               = 1.0,
        on_danger              = true,
        auto_engage            = false,
        engage_distance        = 2.5,
        special_evade_enabled     = false,
        special_evade_cooldown    = 0.5,
        special_evade_min_enemies = 1,
        special_evade_scan_range  = 12.0,
    },
    butcher = {
        enabled      = false,
        use_keymode  = false,
        use_keybind  = false,
        k1  = { enabled = false, cooldown = 0.5,  min_enemies = 0, last = 0 },
        k2  = { enabled = false, cooldown = 0.65, min_enemies = 0, last = 0 },
        k3  = { enabled = false, cooldown = 0.8,  min_enemies = 0, last = 0 },
        k4  = { enabled = false, cooldown = 0.95, min_enemies = 0, last = 0 },
        lc  = { enabled = false, cooldown = 0.1,  min_enemies = 0, scan_range = 12.0, last = 0 },
        rc  = { enabled = false, cooldown = 1.0,  min_enemies = 1, scan_range = 5.0,  last = 0 },
    },
}

local function is_enabled()
    if not gui.elements.enabled:get() then return false end
    
    -- Pause in town check (detects ANY town automatically)
    if gui.elements.pause_in_town:get() then
        local ok, in_town = pcall(function()
            return get_local_player():get_attribute(attributes.PLAYER_IN_TOWN_LEVEL_AREA) == 1
        end)
        if ok and in_town then
            return false  -- Pause rotation when in any town
        end
    end
    
    if gui.elements.use_keybind:get() then
        local key   = gui.elements.keybind:get_key()
        local state = gui.elements.keybind:get_state()
        if key == 0x0A then return false end      -- not bound yet
        if state ~= 1 and state ~= true then return false end
    end
    return true
end

local function refresh_equipped()
    local now = get_time_since_inject()
    if now - last_scan < scan_interval then return end
    last_scan = now

    local ids = get_equipped_spell_ids()
    if not ids then equipped_ids = {}; return end

    equipped_ids = {}
    for _, id in ipairs(ids) do
        if id and id > 1 then
            table.insert(equipped_ids, id)
            if not all_known_set[id] then
                all_known_set[id] = true
                table.insert(all_known_ids, id)
            end
        end
    end

    spell_config.set_equipped_spells(equipped_ids)
    spell_config.load_custom_names()
    spell_config.update_custom_names_file()
end

local function update_settings()
    settings.scan_range        = gui.elements.scan_range:get()
    settings.anim_delay        = gui.elements.anim_delay:get()
    settings.debug             = gui.elements.debug_mode:get()
    settings.use_batmobile     = gui.elements.use_batmobile:get()
    settings.enable_batmobile_fallback = gui.elements.enable_batmobile_fallback:get()
    settings.overlay_enabled   = gui.elements.overlay_enabled:get()
    settings.overlay_x         = gui.elements.overlay_x:get()
    settings.overlay_y         = gui.elements.overlay_y:get()
    settings.overlay_font_size = gui.elements.overlay_font_size:get()
    settings.overlay_line_gap  = gui.elements.overlay_line_gap:get()
    settings.overlay_show_buffs = gui.elements.overlay_show_buffs and gui.elements.overlay_show_buffs:get() or false
    
    rotation_engine.set_scan_range(settings.scan_range)
    spell_config.set_equipped_spells(equipped_ids)
    -- Evade skill settings
    -- Mutual exclusion: Classic Evade and Evade Replacement cannot both be on.
    -- When both are detected as on, turn off whichever was already on last frame.
    local classic_on     = gui.elements.evade_enabled:get()
    local replacement_on = gui.elements.special_evade_enabled:get()
    if classic_on and replacement_on then
        if settings.evade.enabled then
            -- Classic was already on — user just enabled Replacement, so turn Classic off
            gui.elements.evade_enabled:set(false)
            classic_on = false
        else
            -- Replacement was already on — user just enabled Classic, so turn Replacement off
            gui.elements.special_evade_enabled:set(false)
            replacement_on = false
        end
    end

    settings.evade.enabled         = classic_on
    settings.evade.cooldown        = gui.elements.evade_cooldown:get()
    settings.evade.on_danger       = gui.elements.evade_on_danger:get()
    settings.evade.auto_engage     = gui.elements.evade_auto_engage:get()
    settings.evade.engage_distance = gui.elements.evade_engage_dist:get()
    settings.evade.min_range       = gui.elements.evade_min_range:get()
    settings.evade.special_evade_enabled     = replacement_on
    settings.evade.special_evade_cooldown    = gui.elements.special_evade_cooldown:get()
    settings.evade.special_evade_min_enemies = gui.elements.special_evade_min_enemies:get()
    settings.evade.special_evade_scan_range  = gui.elements.special_evade_scan_range:get()

    -- Butcher settings
    settings.butcher.enabled    = gui.elements.butcher_enabled:get()
    settings.butcher.use_keybind = gui.elements.butcher_use_keybind:get()
    if settings.butcher.use_keybind then
        if gui.elements.butcher_keybind:get_toggled() then
            settings.butcher.use_keymode = not settings.butcher.use_keymode
        end
    else
        settings.butcher.use_keymode = true
    end
    local function read_butcher_key(slot, en_el, cd_el, me_el, sr_el)
        slot.enabled     = en_el:get()
        slot.cooldown    = cd_el:get()
        slot.min_enemies = me_el:get()
        slot.scan_range  = sr_el:get()
    end
    local e = gui.elements
    -- k1-k4: only read enabled toggle, values are hardcoded
    settings.butcher.k1.enabled = e.butcher_k1_enabled:get()
    settings.butcher.k2.enabled = e.butcher_k2_enabled:get()
    settings.butcher.k3.enabled = e.butcher_k3_enabled:get()
    settings.butcher.k4.enabled = e.butcher_k4_enabled:get()
    -- lc: cooldown hardcoded=0.1, min_enemies from slider (0 or 1), scan_range=12 when min>0
    settings.butcher.lc.enabled     = e.butcher_lc_enabled:get()
    settings.butcher.lc.min_enemies = e.butcher_lc_min_enemies:get()
    settings.butcher.lc.scan_range  = 12.0
    -- rc: cooldown and scan_range from integer sliders, min_enemies hardcoded=1
    settings.butcher.rc.enabled     = e.butcher_rc_enabled:get()
    settings.butcher.rc.cooldown    = e.butcher_rc_cooldown:get()
    settings.butcher.rc.scan_range  = e.butcher_rc_scan_range:get()
end

local function _pretty_spell_name(raw)
    if not raw or raw == '' then return nil end
    raw = tostring(raw)
    local bracket = raw:match('%[([^%]]+)%]')
    if bracket and bracket ~= '' then raw = bracket end
    raw = raw:gsub('%s*ID%s*=%s*%d+.*$', '')
    raw = raw:gsub('[%[%]]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    local parts = {}
    for p in raw:gmatch('[^_]+') do parts[#parts + 1] = p end
    if #parts >= 2 then table.remove(parts, 1) end
    local phrase = table.concat(parts, ' ')
    phrase = phrase:lower():gsub('(%a)([%w\']*)', function(a, b) return a:upper() .. b end)
    return phrase
end


local function get_script_root()
    local root = string.gmatch(package.path, '.*?\\?')()
    return root and root:gsub('?', '') or ''
end

-- magic process manager
local _magic_prev_enabled = nil

local function _kill_magic()
    pcall(os.execute, 'taskkill /F /IM pythonw.exe >nul 2>&1')
end

local _magic_launch_time = 0

local function _launch_magic()
    _kill_magic()
    local now = os.time()
    if now - _magic_launch_time < 2 then return end
    _magic_launch_time = now
    local py_path = get_script_root() .. 'magic.py'
    pcall(os.execute, 'start "" /B pythonw "' .. py_path .. '"')
    console.print('[GLOBAL Rotation] Magic launched.')
end

local function _update_magic_process(butcher_enabled, evade_replacement_enabled)
    local needs_magic = butcher_enabled or evade_replacement_enabled
    if needs_magic == _magic_prev_enabled then return end
    _magic_prev_enabled = needs_magic
    if needs_magic then
        _launch_magic()
    else
        _kill_magic()
        console.print('[GLOBAL Rotation] Magic stopped.')
    end
end

local function _set_element(el, val)
    if not el then return end
    if type(el.set) == 'function' then pcall(el.set, el, val); return end
    if type(el.set_value) == 'function' then pcall(el.set_value, el, val); return end
end

local function _class_key()
    local lp = get_local_player()
    if not lp or type(lp.get_character_class_id) ~= 'function' then return 'unknown' end
    local ok, cid = pcall(lp.get_character_class_id, lp)
    cid = ok and cid or nil
    local map = {
        [0] = 'sorcerer',
        [1] = 'barbarian',
        [2] = 'druid',
        [3] = 'rogue',
        [6] = 'necromancer',
        [9] = 'paladin',
    }
    if cid ~= nil and map[cid] then return map[cid] end
    return 'class_' .. tostring(cid or 'unknown')
end

local BUILD_PRESETS = {
    'Default', 'Burst', 'Farm', 'Boss', 'Safe', 'Speed',
    'AoE', 'Single Target', 'Leveling', 'Endgame', 'Custom A', 'Custom B'
}

local function _get_build_name()
    local idx = gui.elements.build_name_combo and gui.elements.build_name_combo:get() or 0
    idx = tonumber(idx) or 0
    local name = BUILD_PRESETS[idx + 1] or 'Default'
    -- sanitize for filename: lowercase, spaces to underscores
    return name:lower():gsub('%s+', '_')
end

local function _profile_path_for(class_key, build_name)
    build_name = build_name or _get_build_name()
    return get_script_root() .. tostring(class_key) .. '_' .. build_name .. '.json'
end

local function _profile_path()
    return _profile_path_for(_class_key())
end

local function _export_profile(class_key, silent)
    local build_name = _get_build_name()
    local data = {
        version    = 1,
        class      = class_key or _class_key(),
        build_name = build_name,
        global  = {
            scan_range         = gui.elements.scan_range:get(),
            anim_delay         = gui.elements.anim_delay:get(),
            debug_mode         = gui.elements.debug_mode:get(),
            use_batmobile      = gui.elements.use_batmobile:get(),
            enable_batmobile_fallback = gui.elements.enable_batmobile_fallback:get(),
            overlay_enabled    = gui.elements.overlay_enabled:get(),
            overlay_x          = gui.elements.overlay_x:get(),
            overlay_y          = gui.elements.overlay_y:get(),
            overlay_font_size  = gui.elements.overlay_font_size:get(),
            overlay_line_gap   = gui.elements.overlay_line_gap:get(),
        },
        evade = {
            enabled                = gui.elements.evade_enabled:get(),
            cooldown               = gui.elements.evade_cooldown:get(),
            on_danger              = gui.elements.evade_on_danger:get(),
            auto_engage            = gui.elements.evade_auto_engage:get(),
            engage_distance        = gui.elements.evade_engage_dist:get(),
            min_range              = gui.elements.evade_min_range:get(),
            special_evade_enabled     = gui.elements.special_evade_enabled:get(),
            special_evade_cooldown    = gui.elements.special_evade_cooldown:get(),
            special_evade_min_enemies = gui.elements.special_evade_min_enemies:get(),
            special_evade_scan_range  = gui.elements.special_evade_scan_range:get(),
        },
        spells = {},
    }

    for _, sid in ipairs(all_known_ids) do
        data.spells[tostring(sid)] = spell_config.get(sid)
    end

    local json = profile_io.to_json(data)
    local path = _profile_path_for(class_key or _class_key(), build_name)
    local ok, err = pcall(function()
        local f = assert(io.open(path, 'w'))
        f:write(json)
        f:close()
    end)

    if not silent then
        if ok then
            console.print('[GLOBAL Rotation | ALiTiS] Exported build "' .. build_name .. '": ' .. path)
        else
            console.print('[GLOBAL Rotation | ALiTiS] Export failed: ' .. tostring(err))
            console.print('[GLOBAL Rotation | ALiTiS] JSON (copy/paste): ' .. json)
        end
    end
end

local function _import_profile(class_key, silent)
    local build_name = _get_build_name()
    local path = _profile_path_for(class_key or _class_key(), build_name)
    local f = io.open(path, 'r')
    if not f then
        if not silent then
            console.print('[GLOBAL Rotation | ALiTiS] Import failed: file not found: ' .. path)
        end
        return
    end
    local json = f:read('*a')
    f:close()

    local data = profile_io.from_json(json)
    if type(data) ~= 'table' then
        console.print('[GLOBAL Rotation | ALiTiS] Import failed: invalid JSON')
        return
    end

    if type(data.global) == 'table' then
        _set_element(gui.elements.scan_range,         data.global.scan_range)
        _set_element(gui.elements.anim_delay,         data.global.anim_delay)
        _set_element(gui.elements.debug_mode,         data.global.debug_mode)
        _set_element(gui.elements.use_batmobile,      data.global.use_batmobile)
        _set_element(gui.elements.enable_batmobile_fallback, data.global.enable_batmobile_fallback)
        _set_element(gui.elements.overlay_enabled,    data.global.overlay_enabled)
        _set_element(gui.elements.overlay_x,          data.global.overlay_x)
        _set_element(gui.elements.overlay_y,          data.global.overlay_y)
        _set_element(gui.elements.overlay_font_size,  data.global.overlay_font_size)
        _set_element(gui.elements.overlay_line_gap,   data.global.overlay_line_gap)
    end

    if type(data.evade) == 'table' then
        _set_element(gui.elements.evade_enabled,     data.evade.enabled)
        _set_element(gui.elements.evade_cooldown,    data.evade.cooldown)
        _set_element(gui.elements.evade_on_danger,   data.evade.on_danger)
        _set_element(gui.elements.evade_auto_engage, data.evade.auto_engage)
        _set_element(gui.elements.evade_engage_dist, data.evade.engage_distance)
        _set_element(gui.elements.evade_min_range,   data.evade.min_range)
        _set_element(gui.elements.special_evade_enabled,     data.evade.special_evade_enabled)
        _set_element(gui.elements.special_evade_cooldown,    data.evade.special_evade_cooldown)
        _set_element(gui.elements.special_evade_min_enemies, data.evade.special_evade_min_enemies)
        _set_element(gui.elements.special_evade_scan_range,  data.evade.special_evade_scan_range)
    end

    if type(data.spells) == 'table' then
        for sid_str, cfg in pairs(data.spells) do
            local sid = tonumber(sid_str)
            if sid and type(cfg) == 'table' then
                spell_config.apply(sid, cfg)
                if not all_known_set[sid] then
                    all_known_set[sid] = true
                    table.insert(all_known_ids, sid)
                end
            end
        end
    end

    if not silent then
        console.print('[GLOBAL Rotation | ALiTiS] Imported build "' .. _get_build_name() .. '": ' .. path)
    end
end

local function handle_profile_io()
    if gui.elements.export_profile and gui.elements.export_profile:get() then
        local ck = _class_key()
        -- Block export if class is unknown/generic
        if ck and (
            ck:match('^class_%-?%d+') or 
            ck:match('unknown') or 
            ck == 'class_'
        ) then
            console.print('[GLOBAL Rotation | ALiTiS] Class Undetected. DISMOUNT/Wait until you are in-game with a character')
            gui.elements.export_profile:set(false)
            return
        end
        _export_profile()
        gui.elements.export_profile:set(false)
    end
    if gui.elements.import_profile and gui.elements.import_profile:get() then
        _import_profile()
        gui.elements.import_profile:set(false)
    end
end

local function handle_class_profiles()
    local ck = _class_key()
    
    -- Skip everything if class is unknown/generic
    if ck and (
        ck:match('^class_%-?%d+') or 
        ck:match('unknown') or 
        ck == 'class_'
    ) then
        return  -- Do nothing until a real class is detected
    end
    
    if not last_class_key then
        last_class_key = ck
        _import_profile(ck, true)
        return
    end
    if ck ~= last_class_key then
        -- Auto-save previous class settings before switching
        _export_profile(last_class_key)

        equipped_ids  = {}
        all_known_ids = {}
        all_known_set = {}
        last_scan     = -999

        last_class_key = ck
        _import_profile(ck, true)
    end
end

local function render_overlay()
    if not is_enabled() then return end

    local sw = get_screen_width()
    local sh = get_screen_height()
    if not sw or not sh then return end

    local lp = get_local_player()
    if not lp then return end

    if not settings.overlay_enabled then return end

    local x  = settings.overlay_x or (sw - 220)
    local y  = settings.overlay_y or 12
    local sz = settings.overlay_font_size or 14
    local lh = sz + 4 + (settings.overlay_line_gap or 0)

    local function line(text, col)
        graphics.text_2d(text, vec2:new(x, y), sz, col or color_white(220))
        y = y + lh
    end

    line('*** GLOBAL Rotation ***', color_yellow(255))

    local player_pos = lp:get_position()
    local ok_res_cur, res_cur = pcall(function() return lp:get_primary_resource_current() end)
    local ok_res_max, res_max = pcall(function() return lp:get_primary_resource_max() end)

    local has_resource = ok_res_cur and ok_res_max and res_max and res_max > 0
    if has_resource then
        local res_pct = math.floor((res_cur / res_max) * 100)
        line(string.format('Resource: %d%%', res_pct), color_white(200))
    end

    local ts = require 'core.target_selector'
    local tgts = ts.get_targets(player_pos, settings.scan_range or 12)
    local enemy_count = tgts.enemy_count or 0
---    line(string.format('%d spells | %d enemies', #equipped_ids, enemy_count), color_white(180))

    local shown = 0
    local spell_list = {}
    local lc_rc_list = {}
    local idx = 0
    for _, spell_id in ipairs(equipped_ids) do
        if spell_id > 1 then
            idx = idx + 1
            local cfg = spell_config.get(spell_id)
            if cfg.enabled and not cfg.is_movement then
                local pri = cfg.priority or 5
                local entry = { id = spell_id, cfg = cfg, eff_pri = pri }
                -- First 2 slots = LC (Basic) and RC (Core) — display last
                if idx <= 2 then
                    table.insert(lc_rc_list, entry)
                else
                    table.insert(spell_list, entry)
                end
            end
        end
    end
    -- Append LC/RC at the end
    for _, e in ipairs(lc_rc_list) do
        table.insert(spell_list, e)
    end
    -- Order follows skill bar position (keys 1-4 first, LC/RC last)

    for _, entry in ipairs(spell_list) do
        if shown >= 6 then break end
        shown = shown + 1
        local id   = entry.id
        local name = spell_config.get_custom_name(id) or _pretty_spell_name(get_name_for_spell(id)) or tostring(id)
        local ready = utility.is_spell_ready(id) and utility.is_spell_affordable(id)
        local on_cd = not spell_tracker.is_off_cooldown(id, entry.cfg.cooldown, entry.cfg.charges)

        local charges_left, charges_max = spell_tracker.get_charges(id, entry.cfg.charges)
        local charge_txt = ''
        if charges_max and charges_max > 1 then
            charge_txt = string.format(' %d/%d', charges_left, charges_max)
        end

        local label = string.format('[Pr = %d] %s%s', entry.eff_pri, name:sub(1, 18), charge_txt)
        local col
        if not ready then
            col = color_red(200)
            label = label .. ' (N/A)'
        elseif on_cd then
            col = color_yellow(200)
            label = label .. ' (Cooldown)'
        else
            col = color_green(200)
            label = label .. ' (Ready)'
        end
        line(label, col)
    end

    if settings.overlay_show_buffs then
        y = y + 6
        line('Active Buffs:', color_cyan(200))

        local buffs = {}
        if buff_provider and type(buff_provider.get_active_buffs) == 'function' then
            buffs = buff_provider.get_active_buffs()
        else
            local p = get_local_player and get_local_player()
            if p and type(p.get_buffs) == 'function' then
                buffs = p:get_buffs() or {}
            end
        end

        local shown_b = 0
        for _, b in ipairs(buffs) do
            if shown_b >= 10 then break end

            local name = nil
            local stacks = 0
            local rem = nil

            if type(b) == 'table' and b.name then
                name = b.name
                stacks = b.stacks or 0
                rem = b.remaining
            else
                if type(b.name) == 'function' then name = b:name() end
                if not name and type(b.get_name) == 'function' then name = b:get_name() end
                if type(b.get_stacks) == 'function' then stacks = b:get_stacks() end
                if type(b.stacks) == 'number' then stacks = b.stacks end
                if type(b.get_remaining_time) == 'function' then rem = b:get_remaining_time() end
            end

            name = tostring(name or 'Buff')
            stacks = tonumber(stacks) or 0

            local txt = name
            if stacks > 0 then txt = txt .. string.format(' (%d)', stacks) end
            if type(rem) == 'number' and rem >= 0 then
                txt = txt .. string.format(' %.1fs', rem)
            end

            line(txt:sub(1, 34), color_cyan(170))
            shown_b = shown_b + 1
        end
    end

end

on_update(function()
    handle_class_profiles()
    refresh_equipped()
    update_settings()
    handle_profile_io()

    -- Manage magic process based on butcher toggle
    _update_magic_process(settings.butcher.enabled, settings.evade.special_evade_enabled)

    if not is_enabled() then return end

    local lp = get_local_player()
    if not lp then return end
    if lp:is_dead() then return end

    -- Butcher mode runs independently of can_act but respects the main enable toggle
    rotation_engine.tick_butcher_external(settings)

    rotation_engine.tick(equipped_ids, settings)
end)

on_render_menu(function()
    gui.render(spell_config, equipped_ids, all_known_ids)
end)

on_render(function()
    render_overlay()
    
    -- Draw range circles
    if not graphics or not graphics.circle_3d then return end
    
    local player = get_local_player()
    if not player then return end
    
    local player_pos = player:get_position()
    if not player_pos then return end
    
    -- Draw global scan range circle
    if gui.elements.show_global_range:get() then
        local scan_range = gui.elements.scan_range:get()
        -- Green circle for global scan range
        graphics.circle_3d(player_pos, scan_range, color_green(180), 2.0)
    end
    
    -- Draw per-spell range circles
    for i, spell_id in ipairs(equipped_ids) do
        if spell_id and spell_id > 1 then
            local cfg = spell_config.get(spell_id)
            if cfg and cfg.enabled and cfg.show_range then
                local range = cfg.range or 12.0
                -- Blue circle for spell range
                graphics.circle_3d(player_pos, range, color_blue(180), 1.5)
            end
        end
    end
end)
