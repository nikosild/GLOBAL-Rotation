local plugin_label   = 'global_rotation_alitis'
local plugin_version = '3.0'
console.print('Lua Plugin - GLOBAL Rotation - ALiTiS - v' .. plugin_version)

local gui = {}

local _spell_trees = {}

local function _get_spell_tree(spell_id)
    local id = tostring(spell_id)
    if _spell_trees[id] then return _spell_trees[id] end
    local t = tree_node:new(2)
    _spell_trees[id] = t
    return t
end

local function _pretty_spell_name(raw)
    if not raw or raw == '' then return nil end
    raw = tostring(raw):gsub('[%[%]]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    local parts = {}
    for p in raw:gmatch('[^_]+') do parts[#parts + 1] = p end
    if #parts >= 2 then table.remove(parts, 1) end -- drop class prefix
    local phrase = table.concat(parts, ' ')
    phrase = phrase:lower():gsub('(%a)([%w\']*)', function(a, b) return a:upper() .. b end)
    return phrase
end


local function cb(default, key)
    return checkbox:new(default, get_hash(plugin_label .. '_' .. key))
end
local function si(min, max, default, key)
    return slider_int:new(min, max, default, get_hash(plugin_label .. '_' .. key))
end
local function sf(min, max, default, key)
    return slider_float:new(min, max, default, get_hash(plugin_label .. '_' .. key))
end

gui.plugin_label   = plugin_label
gui.plugin_version = plugin_version

gui.elements = {
    main_tree      = tree_node:new(0),
    enabled        = cb(false, 'enabled'),
    pause_in_town  = cb(true, 'pause_in_town'),
    use_keybind    = cb(false, 'use_keybind'),
    keybind        = keybind:new(0x0A, true, get_hash(plugin_label .. '_keybind')),

    global_tree    = tree_node:new(1),
    anim_delay     = sf(0.0, 0.5,  0.05, 'anim_delay'),

    export_profile = cb(false, 'export_profile'),
    import_profile = cb(false, 'import_profile'),
    reload_profile = cb(true, 'reload_profile'),
    build_name_combo  = combo_box:new(0, get_hash(plugin_label .. '_build_name')),
    build_profile_tree = tree_node:new(2),

    overlay_enabled    = cb(true,  'overlay_enabled'),
    overlay_tree       = tree_node:new(2),
    overlay_x          = si(0, 3000, 20,  'overlay_x'),
    overlay_y          = si(0, 3000, 20,  'overlay_y'),
    overlay_font_size  = si(12, 19, 14,   'overlay_font_size'),
    overlay_line_gap   = si(0, 5,   0,    'overlay_line_gap'),
    overlay_show_buffs = cb(false, 'overlay_show_buffs'),

    show_global_range  = cb(false, 'show_global_range'),

    debug_mode     = cb(false, 'debug_mode'),

    equipped_tree  = tree_node:new(1),
    inactive_tree  = tree_node:new(1),

    -- Evade skill section
    evade_tree              = tree_node:new(1),
    evade_enabled           = cb(false, 'evade_enabled'),
    evade_cooldown          = sf(0.0, 10.0, 0.5, 'evade_cooldown'),
    evade_on_danger         = cb(true,  'evade_on_danger'),
    evade_auto_engage       = cb(false, 'evade_auto_engage'),
    evade_engage_dist       = sf(0.0, 5.0, 2.5, 'evade_engage_dist'),
    evade_min_range         = sf(0.0, 15.0, 0.0, 'evade_min_range'),
    -- Evade Replacement: auto-fire evade on its own independent cooldown
    special_evade_enabled    = cb(false, 'special_evade_enabled'),
    special_evade_cooldown   = sf(0.0, 5.0, 0.5, 'special_evade_cooldown'),
    special_evade_min_enemies = si(0, 20, 1, 'special_evade_min_enemies'),
    special_evade_scan_range  = sf(1.0, 30.0, 12.0, 'special_evade_scan_range'),
    -- Sequence and combo chain for Evade (rendered inside Evade Settings)
    evade_seq_tree          = tree_node:new(2),
    evade_combo_tree        = tree_node:new(2),

    -- Butcher mode: fires keys 1/2/3/4/RC while Possess_Butcher buff is active
    butcher_tree            = tree_node:new(1),
    butcher_enabled         = cb(false, 'butcher_enabled'),
    butcher_use_keybind     = cb(false, 'butcher_use_keybind'),
    butcher_keybind         = keybind:new(0x0A, true, get_hash(plugin_label .. '_butcher_keybind')),
    -- Keys 1-4: hardcoded (cd=0.5/0.65/0.8/0.95, min_enemies=0, no scan range)
    butcher_k1_enabled      = cb(false, 'butcher_k1_enabled'),
    butcher_k2_enabled      = cb(false, 'butcher_k2_enabled'),
    butcher_k3_enabled      = cb(false, 'butcher_k3_enabled'),
    butcher_k4_enabled      = cb(false, 'butcher_k4_enabled'),
    -- Left Click (Carve)
    butcher_lc_enabled      = cb(false, 'butcher_lc_enabled'),
    butcher_lc_min_enemies  = si(0, 1, 0, 'butcher_lc_min_enemies'),
    butcher_rc_enabled      = cb(false, 'butcher_rc_enabled'),
    butcher_rc_cooldown     = si(1, 2, 1, 'butcher_rc_cooldown'),
    butcher_rc_scan_range   = si(5, 6, 5, 'butcher_rc_scan_range'),
}

gui.render = function(spell_config, equipped_ids, all_known_ids)
    if not gui.elements.main_tree:push('GLOBAL Rotation | ALiTiS | v' .. plugin_version) then return end

    gui.elements.enabled:render('Enable', 'Enable the universal rotation')
    gui.elements.pause_in_town:render('Pause in Town', 'Automatically pause rotation when in town')
    gui.elements.use_keybind:render('Use keybind', 'Toggle rotation on/off with a key')
    if gui.elements.use_keybind:get() then
        render_menu_header('Click the key field below and press a key to bind it. The default shown is a placeholder — not Space.')
        gui.elements.keybind:render('Toggle Key', 'Press a key to bind it. The shown default is a placeholder — click and press your desired key to assign it.')
    end

    if gui.elements.global_tree:push('Global Settings') then
        gui.elements.anim_delay:render('Animation Delay (s)', 'Global animation delay after each cast', 2)

        gui.elements.debug_mode:render('Debug Mode', 'Print cast info to console')

        gui.elements.overlay_enabled:render('Overlay', 'Show/hide the on-screen overlay')
        if gui.elements.overlay_enabled:get() then
            if gui.elements.overlay_tree:push('Display Overlay Settings') then
                gui.elements.overlay_x:render('Overlay X', 'Overlay left position (px)', 1)
                gui.elements.overlay_y:render('Overlay Y', 'Overlay top position (px)', 1)
                gui.elements.overlay_font_size:render('Font Size', 'Size of the overlay text', 1)
                gui.elements.overlay_line_gap:render('Line Gap', 'Extra spacing between lines', 1)
                gui.elements.overlay_show_buffs:render('Show Active Buff List', 'Show active buffs in the overlay')
                gui.elements.overlay_tree:pop()
            end
        end

        -- Build Profile as its own main category (at the end)
        if gui.elements.build_profile_tree:push('Build Profile') then
            local build_presets = {
                'Default', 'Burst', 'Farm', 'Boss', 'Safe', 'Speed',
                'AoE', 'Single Target', 'Leveling', 'Endgame', 'Custom A', 'Custom B'
            }
            gui.elements.build_name_combo:render('Build Name', build_presets, 'Name used when saving/loading this profile. Each name saves as a separate file.')
            gui.elements.import_profile:render('Import build profile', 'Load settings from the selected class + build JSON file')
            gui.elements.export_profile:render('Export build profile', 'Save current settings to a named JSON file for this class and build')
            gui.elements.reload_profile:render('Reload profile (F5)', 'Press F5 or click to reload the current build profile from disk')
            gui.elements.build_profile_tree:pop()
        end

        gui.elements.global_tree:pop()
    end

    -- ── Butcher Master Toggle ─────────────────────────────────────────────
    gui.elements.butcher_enabled:render('Butcher Mode', 'Enable automatic key presses while Possess_Butcher buff is active')
    gui.elements.butcher_use_keybind:render('Use Butcher KeyMode', 'Toggle Butcher KeyMode on/off with a key')
    if gui.elements.butcher_use_keybind:get() then
        render_menu_header('Click the key field below and press a key to bind it.')
        gui.elements.butcher_keybind:render('Butcher KeyMode Toggle', 'Press a key to bind it for toggling Butcher KeyMode')
    end

    -- ── Butcher Mode Settings ─────────────────────────────────────────────
    if gui.elements.butcher_enabled:get() then
        if gui.elements.butcher_tree:push('Butcher Mode Settings') then
            local function render_butcher_key(label, en, cd, me, sr)
                en:render(label, 'Enable auto-press for this key in Butcher form')
                if en:get() then
                    cd:render(label .. ' Cooldown (s)', 'How often this key fires', 1)
                    me:render(label .. ' Min Enemies', 'Minimum enemies nearby to trigger. 0 = always.', 1)
                    if me:get() > 0 then
                        sr:render(label .. ' Scan Range', 'Range to count enemies for min enemies check', 1)
                    end
                end
            end

            local e = gui.elements
            e.butcher_k1_enabled:render('Hell Charge',   'Enable Hell Charge (Key 1) — 0.5s cooldown, always fires')
            e.butcher_k2_enabled:render('Culling',        'Enable Culling (Key 2) — 0.65s cooldown, always fires')
            e.butcher_k3_enabled:render('Hail of Hooks',  'Enable Hail of Hooks (Key 3) — 0.8s cooldown, always fires')
            e.butcher_k4_enabled:render('Furnace Blast',  'Enable Furnace Blast (Key 4) — 0.95s cooldown, always fires')

            -- Carve (Left Click): cooldown=0.1 hardcoded, min_enemies slider 0-1, no scan range slider
            e.butcher_lc_enabled:render('Carve (Left Click)', 'Enable Carve — 0.1s cooldown')
            if e.butcher_lc_enabled:get() then
                e.butcher_lc_min_enemies:render('Carve (Left Click) Min Enemies', 'Min enemies nearby. 0 = always fire. 1 = needs enemy at 12 range.', 1)
            end

            -- Molten Slam (Right Click): cooldown slider 1-2s, min_enemies=1 hardcoded, scan range 5-6
            e.butcher_rc_enabled:render('Molten Slam (Right Click)', 'Enable Molten Slam — requires 1 nearby enemy')
            if e.butcher_rc_enabled:get() then
                e.butcher_rc_cooldown:render('Molten Slam (Right Click) Cooldown (s)', 'How often Molten Slam fires (1 or 2 seconds)', 1)
                e.butcher_rc_scan_range:render('Molten Slam (Right Click) Scan Range', 'Range to detect nearby enemy (5 or 6 yards)', 1)
            end

            gui.elements.butcher_tree:pop()
        end
    end

    -- ── Evade / Dodge Skill ───────────────────────────────────────────────
    local equipped_set = {}
    for _, id in ipairs(equipped_ids) do
        if id and id > 1 then equipped_set[id] = true end
    end

    if gui.elements.equipped_tree:push('Equipped Spells') then
        -- ── Evade Settings (first inside Equipped Spells) ─────────────────
        if gui.elements.evade_tree:push('Evade Settings') then
            render_menu_header('Choose ONLY ONE:')
            render_menu_header('1: Classic Evade')
            render_menu_header('2: Evade Replacement')
            gui.elements.evade_enabled:render('Classic Evade', 'Fires Evade automatically. Works for basic evade triggering.')
            if gui.elements.evade_enabled:get() then
                gui.elements.evade_cooldown:render('Cooldown (s)', 'Minimum seconds between evade casts to prevent spam', 1)
                gui.elements.evade_on_danger:render('Fire on Danger Zone', 'Automatically evade when stepping into a detected danger area (AoE indicator / evade zone)')
                gui.elements.evade_auto_engage:render('Auto Engage', 'Use Evade to dash toward the current target when available')
                if gui.elements.evade_auto_engage:get() then
                    gui.elements.evade_engage_dist:render('Engage Distance', 'Stop this many units short of the target when dashing (0 = on top of target)', 1)
                    gui.elements.evade_min_range:render('Minimum Range', 'Don\'t cast if target is closer than this distance (0 = no minimum). Prevents wasting Evade on very close targets.', 1)
                end
                if gui.elements.evade_seq_tree:push('Sequence Formula') then
                    render_menu_header('Place Evade as a step inside a cast sequence.')
                    render_menu_header('Example: Evade (step 1) -> Skill A (step 2) to proc its buff.')
                    spell_config.render_evade_sequence(337031)
                    gui.elements.evade_seq_tree:pop()
                end
                if gui.elements.evade_combo_tree:push('Combo Chain') then
                    render_menu_header('After Evade fires, temporarily boost a spell\'s priority.')
                    spell_config.render_evade_combo(337031)
                    gui.elements.evade_combo_tree:pop()
                end
            end
            render_menu_header('Any class-specific evade replacement')
            gui.elements.special_evade_enabled:render('Evade Replacement', 'Triggers Arbiter form evade and any class-specific evade replacements.')
            if gui.elements.special_evade_enabled:get() then
                gui.elements.special_evade_cooldown:render('Cooldown (s)', 'How often Evade Replacement fires automatically', 1)
                gui.elements.special_evade_min_enemies:render('Min Enemies Nearby', 'Minimum enemies within scan range to trigger. 0 = always fire on cooldown.', 1)
                if gui.elements.special_evade_min_enemies:get() > 0 then
                    gui.elements.special_evade_scan_range:render('Enemy Scan Range', 'Range to count nearby enemies for the min enemies check', 1)
                end
            end
            gui.elements.evade_tree:pop()
        end

        -- ── Spells ────────────────────────────────────────────────────────
        render_menu_header('These spells are currently on your skill bar.')
        local any = false
        local lc_rc = {}
        local idx = 0
        for _, spell_id in ipairs(equipped_ids) do
            if spell_id and spell_id > 1 then
                idx = idx + 1
                if idx <= 2 then
                    table.insert(lc_rc, spell_id)
                else
                    any = true
                    local name = spell_config.get_custom_name(spell_id) or _pretty_spell_name(get_name_for_spell(spell_id)) or ('Spell ' .. spell_id)
                    local spell_tree = _get_spell_tree(spell_id)
                    if spell_tree:push(name) then
                        spell_config.render(spell_id, name)
                        spell_tree:pop()
                    end
                end
            end
        end
        for _, spell_id in ipairs(lc_rc) do
            any = true
            local name = spell_config.get_custom_name(spell_id) or _pretty_spell_name(get_name_for_spell(spell_id)) or ('Spell ' .. spell_id)
            local spell_tree = _get_spell_tree(spell_id)
            if spell_tree:push(name) then
                spell_config.render(spell_id, name)
                spell_tree:pop()
            end
        end
        if not any then
            render_menu_header('No spells detected on skill bar.')
        end
        gui.elements.equipped_tree:pop()
    end

    if all_known_ids and #all_known_ids > 0 then
        if gui.elements.inactive_tree:push('Other Known Spells') then
            render_menu_header('Spells detected, but not currently on bar.')
            for _, spell_id in ipairs(all_known_ids) do
                if not equipped_set[spell_id] then
                    local name = spell_config.get_custom_name(spell_id) or _pretty_spell_name(get_name_for_spell(spell_id)) or ('Spell ' .. spell_id)
                    local spell_tree = _get_spell_tree(spell_id)
                    if spell_tree:push(name) then
                        spell_config.render(spell_id, name)
                        spell_tree:pop()
                    end
                end
            end
            gui.elements.inactive_tree:pop()
        end
    end

    gui.elements.main_tree:pop()
end

return gui
