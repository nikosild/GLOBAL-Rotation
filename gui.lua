local plugin_label   = 'global_rotation_alitis'
local plugin_version = '2.0'
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
    use_keybind    = cb(false, 'use_keybind'),
    keybind        = keybind:new(0x0A, true, get_hash(plugin_label .. '_keybind')),

    global_tree    = tree_node:new(1),
    scan_range     = sf(5.0, 30.0, 16.0, 'scan_range'),
    anim_delay     = sf(0.0, 0.5,  0.05, 'anim_delay'),

    export_profile = cb(false, 'export_profile'),
    import_profile = cb(false, 'import_profile'),
    build_name_combo  = combo_box:new(0, get_hash(plugin_label .. '_build_name')),
    build_profile_tree = tree_node:new(2),

    overlay_enabled    = cb(true,  'overlay_enabled'),
    overlay_tree       = tree_node:new(2),
    overlay_x          = si(0, 3000, 20,  'overlay_x'),
    overlay_y          = si(0, 3000, 20,  'overlay_y'),
    overlay_font_size  = si(12, 19, 14,   'overlay_font_size'),
    overlay_line_gap   = si(0, 5,   0,    'overlay_line_gap'),
    overlay_show_buffs = cb(false, 'overlay_show_buffs'),

    debug_mode     = cb(false, 'debug_mode'),

    equipped_tree  = tree_node:new(1),
    inactive_tree  = tree_node:new(1),

    -- Dedicated Evade skill section (spell ID 337031 hardcoded — Hardcore universal)
    evade_tree           = tree_node:new(1),
    evade_enabled        = cb(false, 'evade_enabled'),
    evade_cooldown       = sf(0.0, 10.0, 1.0, 'evade_cooldown'),
    evade_on_danger      = cb(true,  'evade_on_danger'),
    evade_auto_engage    = cb(false, 'evade_auto_engage'),
    evade_engage_dist    = sf(0.0, 5.0, 2.5, 'evade_engage_dist'),
    -- Sequence and combo chain for Evade (rendered inside Evade Settings)
    evade_seq_tree       = tree_node:new(2),
    evade_combo_tree     = tree_node:new(2),
}

gui.render = function(spell_config, equipped_ids, all_known_ids)
    if not gui.elements.main_tree:push('GLOBAL Rotation | ALiTiS | v' .. plugin_version) then return end

    gui.elements.enabled:render('Enable', 'Enable the universal rotation')
    gui.elements.use_keybind:render('Use keybind', 'Toggle rotation on/off with a key')
    if gui.elements.use_keybind:get() then
        gui.elements.keybind:render('Toggle Key', 'Key to toggle the rotation')
    end

    if gui.elements.global_tree:push('Global Settings') then
        gui.elements.scan_range:render('Scan Range', 'How far to scan for enemies', 1)
        gui.elements.anim_delay:render('Animation Delay (s)', 'Global animation delay after each cast', 2)

        if gui.elements.build_profile_tree:push('Build Profile') then
            local build_presets = {
                'Default', 'Burst', 'Farm', 'Boss', 'Safe', 'Speed',
                'AoE', 'Single Target', 'Leveling', 'Endgame', 'Custom A', 'Custom B'
            }
            gui.elements.build_name_combo:render('Build Name', build_presets, 'Name used when saving/loading this profile. Each name saves as a separate file.')
            gui.elements.import_profile:render('Import build profile', 'Load settings from the selected class + build JSON file')
            gui.elements.export_profile:render('Export build profile', 'Save current settings to a named JSON file for this class and build')
            gui.elements.build_profile_tree:pop()
        end

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

        gui.elements.debug_mode:render('Debug Mode', 'Print cast info to console')

        gui.elements.global_tree:pop()
    end

    -- ── Evade / Dodge Skill ───────────────────────────────────────────────
    if gui.elements.evade_tree:push('Evade Settings') then
        render_menu_header('Evade is a universal ability available to all Hardcore players.')
        render_menu_header('Spell ID 337031 is used automatically — no configuration needed.')
        gui.elements.evade_enabled:render('Enable Evade', 'Let the plugin trigger the Evade skill automatically')
        if gui.elements.evade_enabled:get() then
            gui.elements.evade_cooldown:render('Cooldown (s)', 'Minimum seconds between evade casts to prevent spam', 1)
            gui.elements.evade_on_danger:render('Fire on Danger Zone', 'Automatically evade when stepping into a detected danger area (AoE indicator / evade zone)')
            gui.elements.evade_auto_engage:render('Auto Engage', 'Use Evade to dash toward the current target when available')
            if gui.elements.evade_auto_engage:get() then
                gui.elements.evade_engage_dist:render('Engage Distance', 'Stop this many units short of the target when dashing (0 = on top of target)', 1)
            end

            -- Sequence Formula for Evade
            if gui.elements.evade_seq_tree:push('Sequence Formula') then
                render_menu_header('Place Evade as a step inside a cast sequence.')
                render_menu_header('Example: Evade (step 1) -> Skill A (step 2) to proc its buff.')
                spell_config.render_evade_sequence(337031)
                gui.elements.evade_seq_tree:pop()
            end

            -- Combo Chain for Evade
            if gui.elements.evade_combo_tree:push('Combo Chain') then
                render_menu_header('After Evade fires, temporarily boost a spell\'s priority.')
                spell_config.render_evade_combo(337031)
                gui.elements.evade_combo_tree:pop()
            end
        end
        gui.elements.evade_tree:pop()
    end

    local equipped_set = {}
    for _, id in ipairs(equipped_ids) do
        if id and id > 1 then equipped_set[id] = true end
    end

    if gui.elements.equipped_tree:push('Equipped Spells') then
        render_menu_header('These spells are currently on your skill bar.')
        local any = false
        for _, spell_id in ipairs(equipped_ids) do
            if spell_id and spell_id > 1 then
                any = true
                local name = _pretty_spell_name(get_name_for_spell(spell_id)) or ('Spell ' .. spell_id)
                local spell_tree = _get_spell_tree(spell_id)
                if spell_tree:push(name) then
                    spell_config.render(spell_id, name)
                    spell_tree:pop()
                end
            end
        end
        if not any then
            render_menu_header('No spells detected on skill bar.')
        end
        gui.elements.equipped_tree:pop()
    end

    if all_known_ids and #all_known_ids > 0 then
        if gui.elements.inactive_tree:push('Other Known Spells') then
            render_menu_header('Spells detected previously but not currently on bar.')
            for _, spell_id in ipairs(all_known_ids) do
                if not equipped_set[spell_id] then
                    local name = _pretty_spell_name(get_name_for_spell(spell_id)) or ('Spell ' .. spell_id)
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
