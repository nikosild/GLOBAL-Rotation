local plugin_label = 'global_rotation_alitis'

local spell_config = {}

local _elements = {}
local _buff_name_cache = {}
local _buff_state = {}
local _prev_channel_state = {}  -- Track previous channel spell state per spell_id

local buff_provider   = require 'core.buff_provider'
local target_selector = require 'core.target_selector'

-- Equipped spell list (set by main.lua each frame)
local _equipped_ids   = {}
local _equipped_names = {}  -- parallel array of display names

local _custom_names = {}  -- [spell_id_str] = name
local _custom_names_path = nil

local function _get_custom_names_path()
    if _custom_names_path then return _custom_names_path end
    local root = ''
    pcall(function()
        -- package.path points to core/ subfolder, go up one level to script root
        local p = package.path:match('(.*[/\\])') or ''
        -- Remove trailing 'core/' or 'core\' if present
        p = p:gsub('[/\\]?core[/\\]$', '')
        p = p:gsub('[/\\]?core[/\\]?$', '')
        if p ~= '' and not p:match('[/\\]$') then p = p .. '\\' end
        root = p
    end)
    _custom_names_path = root .. 'custom_names.txt'
    return _custom_names_path
end

local function _pretty_name(raw, id)
    if not raw then return 'Spell ' .. id end
    raw = tostring(raw):gsub('[%[%]]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    local parts = {}
    for p in raw:gmatch('[^_]+') do parts[#parts + 1] = p end
    if #parts >= 2 then table.remove(parts, 1) end
    local phrase = table.concat(parts, ' ')
    return phrase:lower():gsub('(%a)([%w\']*)', function(a, b) return a:upper() .. b end)
end

function spell_config.load_custom_names()
    local path = _get_custom_names_path()
    _custom_names = {}
    local f = io.open(path, 'r')
    if not f then return end
    for line in f:lines() do
        line = line:match('^%s*(.-)%s*$')
        if line ~= '' and not line:match('^#') then
            -- Format: N) Old name: SpellName (12345678)=CustomName
            local id, name = line:match('%((%d+)%)=(.+)$')
            if id and name then
                _custom_names[id] = name
            end
        end
    end
    f:close()
end

function spell_config.update_custom_names_file()
    if not _equipped_ids or #_equipped_ids == 0 then return end
    local path = _get_custom_names_path()
    local fw = io.open(path, 'w')
    if not fw then return end
    fw:write("# Custom skill names for GLOBAL Rotation\n")
    fw:write("# Edit the names after '=' and press F5 to reload.\n")
    fw:write("# Leave a name unchanged to keep the original.\n")
    fw:write("\n")

    -- Split into LC/RC (first 2 slots) and keys 1-4 (slots 3+)
    local lc_rc = {}
    local keys  = {}
    local slot  = 0
    for _, id in ipairs(_equipped_ids) do
        if id and id > 1 then
            slot = slot + 1
            if slot <= 2 then
                table.insert(lc_rc, { id = id, slot = slot })
            else
                table.insert(keys, { id = id, slot = slot })
            end
        end
    end

    -- Write keys 1-4 first
    local key_num = 0
    for _, entry in ipairs(keys) do
        key_num = key_num + 1
        local id       = entry.id
        local current  = _custom_names[tostring(id)]
        local original = _pretty_name(get_name_for_spell(id), id)
        local display  = current or original
        fw:write(key_num .. ") Old name: " .. original .. " (" .. tostring(id) .. ")=" .. display .. "\n")
    end

    -- Write LC/RC last with fixed labels
    local mouse_labels = { 'Left Click', 'Right Click' }
    for i, entry in ipairs(lc_rc) do
        local id       = entry.id
        local current  = _custom_names[tostring(id)]
        local original = _pretty_name(get_name_for_spell(id), id)
        local label    = mouse_labels[i] or ('Mouse ' .. i)
        local display  = current or original
        fw:write(label .. ") Old name: " .. original .. " (" .. tostring(id) .. ")=" .. display .. "\n")
    end

    fw:close()
end

function spell_config.get_custom_name(spell_id)
    if not spell_id then return nil end
    local v = _custom_names[tostring(spell_id)]
    if v and v ~= '' then return v end
    return nil
end

function spell_config.set_equipped_spells(ids)
    _equipped_ids   = ids or {}
    _equipped_names = {}
    for _, id in ipairs(_equipped_ids) do
        if id and id > 1 then
            local raw  = get_name_for_spell(id)
            local name = raw or ('Spell ' .. id)
            if raw then
                raw = tostring(raw):gsub('[%[%]]', ''):gsub('^%s+', ''):gsub('%s+$', '')
                local parts = {}
                for p in raw:gmatch('[^_]+') do parts[#parts + 1] = p end
                if #parts >= 2 then table.remove(parts, 1) end
                local phrase = table.concat(parts, ' ')
                name = phrase:lower():gsub('(%a)([%w\']*)', function(a, b) return a:upper() .. b end)
            end
            _equipped_names[#_equipped_names + 1] = name .. ' (' .. id .. ')'
        end
    end
end

-- Combo chain state per spell (stores selected index -> spell_id mapping)
local _combo_state = {}  -- [spell_id] = { target_id = number }

-- Sequence name state per spell (stores the free-text sequence name)
local _seq_name_state = {}  -- [spell_id] = string

local function key(spell_id, suffix)
    return plugin_label .. '_spell_' .. tostring(spell_id) .. '_' .. suffix
end

local function _get_buff_state(spell_id)
    local k  = tostring(spell_id)
    local st = _buff_state[k]
    if st then return st end
    st = { buff_hash = 0, buff_name = '', last_list_sig = nil }
    _buff_state[k] = st
    return st
end

local function _ensure_buff_combo(e, spell_id)
    if e.buff_combo then return end
    local st          = _get_buff_state(spell_id)
    local default_idx = (type(st.buff_hash) == 'number' and st.buff_hash ~= 0) and 1 or 0
    e.buff_combo      = combo_box:new(default_idx, get_hash(key(spell_id, 'buff_combo')))
end

local function get_elements(spell_id)
    local id = tostring(spell_id)
    if _elements[id] then return _elements[id] end

    local e = {
        enabled       = checkbox:new(true,  get_hash(key(spell_id, 'enabled'))),

        -- Single priority
        priority      = slider_int:new(1, 10, 5, get_hash(key(spell_id, 'priority'))),

        cooldown      = slider_float:new(0.0, 5.0, 0.4, get_hash(key(spell_id, 'cooldown'))),
        charges       = slider_int:new(1, 5, 1,   get_hash(key(spell_id, 'charges'))),

        spell_type    = combo_box:new(0, get_hash(key(spell_id, 'spell_type'))),
        target_mode   = combo_box:new(0, get_hash(key(spell_id, 'target_mode'))),

        range         = slider_float:new(1.0, 30.0, 12.0, get_hash(key(spell_id, 'range'))),
        aoe_range     = slider_float:new(1.0, 20.0, 12.0, get_hash(key(spell_id, 'aoe_range'))),

        require_buff  = checkbox:new(false, get_hash(key(spell_id, 'require_buff'))),
        buff_combo    = nil,
        buff_stacks   = slider_int:new(1, 50, 1, get_hash(key(spell_id, 'buff_stacks'))),
        use_on_cooldown = checkbox:new(false, get_hash(key(spell_id, 'use_on_cooldown'))),

        elite_only    = checkbox:new(false, get_hash(key(spell_id, 'elite_only'))),
        boss_only     = checkbox:new(false, get_hash(key(spell_id, 'boss_only'))),
        min_enemies   = slider_int:new(0, 15, 1, get_hash(key(spell_id, 'min_enemies'))),

        -- Skip small packs: only cast when enough enemies are grouped
        skip_small_packs = checkbox:new(false, get_hash(key(spell_id, 'skip_small_packs'))),
        min_pack_size    = slider_int:new(2, 15, 3, get_hash(key(spell_id, 'min_pack_size'))),

        -- Hard enemies only: only cast on elites, champions, or bosses
        use_on_hard_only = checkbox:new(false, get_hash(key(spell_id, 'use_on_hard_only'))),

        -- Movement spell (on danger): fires when player enters a danger zone
        is_evade         = checkbox:new(false, get_hash(key(spell_id, 'is_evade'))),

        -- Health condition
        use_hp_condition = checkbox:new(false, get_hash(key(spell_id, 'use_hp_condition'))),
        hp_mode          = combo_box:new(0,    get_hash(key(spell_id, 'hp_mode'))),
        hp_threshold     = slider_int:new(1, 100, 50, get_hash(key(spell_id, 'hp_threshold'))),

        -- Resource condition (foreign implementation — works correctly)
        use_res_condition = checkbox:new(false, get_hash(key(spell_id, 'use_res_condition'))),
        res_mode          = combo_box:new(1,    get_hash(key(spell_id, 'res_mode'))),  -- default: Above %
        res_threshold     = slider_int:new(1, 100, 50, get_hash(key(spell_id, 'res_threshold'))),

        -- Self cast: cast on player position, no target required
        self_cast         = checkbox:new(false, get_hash(key(spell_id, 'self_cast'))),

        -- Combo chain (original: one spell boosts next spell priority)
        combo_enabled    = checkbox:new(false, get_hash(key(spell_id, 'combo_enabled'))),
        combo_spell_sel  = combo_box:new(0,    get_hash(key(spell_id, 'combo_spell_sel'))),
        combo_window     = slider_float:new(0.5, 5.0, 2.0, get_hash(key(spell_id, 'combo_window'))),
        combo_boost      = slider_int:new(1, 10, 1,         get_hash(key(spell_id, 'combo_boost'))),

        -- Movement spell (gap closer): closes distance to melee targets
        is_movement      = checkbox:new(false, get_hash(key(spell_id, 'is_movement'))),
        min_range        = slider_float:new(0.0, 15.0, 0.0, get_hash(key(spell_id, 'min_range'))),

        -- Channel spell (Whirlwind, Incinerate, etc.)
        is_channel            = checkbox:new(false, get_hash(key(spell_id, 'is_channel'))),
        channel_break_for_cds = checkbox:new(true,  get_hash(key(spell_id, 'channel_break_cds'))),

        -- ──────────────────────────────────────────────────────────────
        -- SEQUENCE FORMULA
        --   seq_enabled     : bool   — opt-in
        --   seq_name        : stored in _seq_name_state (free-text string)
        --   seq_step        : int    — position inside the sequence (1 = first)
        --   seq_window      : float  — max seconds allowed between steps
        --   seq_cd_behavior : int    — what to do when due step is on cooldown
        --       0 = Pause & cast freely  (sequence waits, window kept alive)
        --       1 = Wait (hold)          (nothing else fires)
        --       2 = Skip & advance       (skip this step, move to next)
        --       3 = Reset                (abort and restart from step 1)
        -- ──────────────────────────────────────────────────────────────
        seq_enabled     = checkbox:new(false, get_hash(key(spell_id, 'seq_enabled'))),
        seq_step        = slider_int:new(1, 10, 1, get_hash(key(spell_id, 'seq_step'))),
        seq_window      = slider_float:new(0.5, 10.0, 2.0, get_hash(key(spell_id, 'seq_window'))),
        seq_cd_behavior = combo_box:new(0, get_hash(key(spell_id, 'seq_cd_behavior'))),

        -- Advanced Settings folder
        advanced_tree   = tree_node:new(2),
        
        -- Visual range indicator
        show_range      = checkbox:new(false, get_hash(key(spell_id, 'show_range'))),
    }

    _elements[id] = e
    return e
end

local function _hash_list_sig(hashes)
    if type(hashes) ~= 'table' then return '' end
    local out = {}
    for i = 1, #hashes do out[#out + 1] = tostring(hashes[i] or 0) end
    return table.concat(out, ',')
end

-- ──────────────────────────────────────────────────────────────────────
-- Sequence name input helper
-- The game UI usually only provides checkbox / slider / combo widgets.
-- We store the name as a plain string keyed by spell_id and expose
-- two "arrow" buttons to cycle through a small palette of preset names
-- PLUS allow the user to just remember/type the same name manually.
-- In practice the name just needs to be identical between spells that
-- belong to the same sequence, so we also provide a "copy from equipped"
-- combo so the user can pick an existing name quickly.
-- ──────────────────────────────────────────────────────────────────────
local SEQ_PRESETS = {
    'Burst', 'Opener', 'Finisher', 'DOT', 'AOE Combo',
    'Execute', 'Setup', 'Chain A', 'Chain B', 'Chain C',
}

local function _get_seq_name(spell_id)
    return _seq_name_state[tostring(spell_id)] or ''
end

local function _set_seq_name(spell_id, name)
    _seq_name_state[tostring(spell_id)] = name or ''
end

-- Collect all unique sequence names currently assigned to any known spell
function spell_config.get_all_sequence_names()
    local seen = {}
    local out  = {}
    for _, v in pairs(_seq_name_state) do
        if v and v ~= '' and not seen[v] then
            seen[v] = true
            out[#out + 1] = v
        end
    end
    table.sort(out)
    return out
end

-- ────────────────────────────────────────────────────────────────────────────
-- GUI render
-- ────────────────────────────────────────────────────────────────────────────
function spell_config.render(spell_id, display_name)
    local e  = get_elements(spell_id)
    local st = _get_buff_state(spell_id)

    e.enabled:render('Enable', 'Enable this spell in the rotation')
    if not e.enabled:get() then return end

    e.priority:render('Priority (1=highest)', 'Lower number = cast first')

    e.spell_type:render('Spell type', { 'Auto', 'Melee', 'Ranged' }, 'Auto = default; Melee will move into range before casting')
    e.target_mode:render('Target selection', target_selector.mode_labels, 'How to pick the target for this spell')

    local stype = e.spell_type:get() or 0
    local range_label = (stype == 1) and 'Engage range' or 'Spell range'
    local range_tip   = (stype == 1) and 'Melee: will move toward the closest valid enemy until within this range' or 'Skip this spell if no valid enemy is within this range'
    e.range:render(range_label, range_tip, 1)
    e.aoe_range:render('AOE check radius', 'Count enemies within this radius (used for Min enemies and Cleave targeting)', 1)

    e.min_enemies:render('Min enemies near you', 'Minimum enemies within AOE check radius (0 = always)', 2)

    -- Skip small packs
    e.skip_small_packs:render('Skip small packs', 'Only cast when enough enemies are grouped in one spot')
    if e.skip_small_packs:get() then
        e.min_pack_size:render('Min pack size', 'Minimum enemies required within AOE radius to consider the group worth casting on', 1)
    end

    -- Hard enemies only
    e.use_on_hard_only:render('Use on Elite / Champion / Boss only', 'Skip this spell against normal enemies — only cast when fighting an elite, champion, or boss')

    if e.advanced_tree:push('Advanced Settings') then

    -- Use on Cooldown (buff proc mode)
    e.use_on_cooldown:render('Use on Cooldown', 'Cast this spell whenever the selected buff is NOT active — use it to proc or reapply the buff. Overrides Require Buff logic.')

    e.require_buff:render('Require Buff', 'Only trigger when a specific buff is active on you')
    if e.require_buff:get() then
        _ensure_buff_combo(e, spell_id)

        local stored_hash = st.buff_hash or 0
        local stored_name = st.buff_name
        if (not stored_name or stored_name == '') then
            stored_name = _buff_name_cache[tostring(spell_id)] or ''
        end

        local items, hashes = buff_provider.get_available_buffs_and_missing(stored_hash, stored_name)

        local desired_idx = 0
        if stored_hash ~= 0 then
            for i = 1, #hashes do
                if hashes[i] == stored_hash then desired_idx = i - 1; break end
            end
        end

        local sig = tostring(desired_idx) .. '|' .. _hash_list_sig(hashes)
        if st.last_list_sig ~= sig then
            if type(e.buff_combo.set) == 'function' then
                pcall(e.buff_combo.set, e.buff_combo, desired_idx)
            end
            st.last_list_sig = sig
        else
            local cur = e.buff_combo:get()
            if type(cur) == 'number' then
                local cur_hash = hashes[cur + 1] or 0
                if cur_hash ~= stored_hash then
                    if type(e.buff_combo.set) == 'function' then
                        pcall(e.buff_combo.set, e.buff_combo, desired_idx)
                    end
                end
            end
        end

        e.buff_combo:render('Buff', items, 'Buff must be active on you to allow the spell (missing entry shows saved selection)')

        local sel = e.buff_combo:get()
        if type(sel) ~= 'number' then sel = 0 end
        local sel_hash = hashes[sel + 1] or 0

        st.buff_hash = sel_hash

        if sel_hash ~= 0 then
            local sel_name = items[sel + 1] or ''
            sel_name = sel_name:gsub(' %(missing%)$', '')
            if sel_name ~= '' then
                st.buff_name = sel_name
                _buff_name_cache[tostring(spell_id)] = sel_name
            end
        end

        e.buff_stacks:render('Min Stacks', 'Minimum buff stack count required (default: 1)', 1)
    end

    -- Self cast
    e.self_cast:render('Self Cast', 'Cast on yourself — no target required (useful for buffs, movement, AoE centered on player)')

    -- HP condition
    e.use_hp_condition:render('HP Condition', 'Only cast this spell when HP is above/below a threshold')
    if e.use_hp_condition:get() then
        e.hp_mode:render('HP Check', { 'Below %', 'Above %' }, 'Cast when HP is below or above the threshold')
        e.hp_threshold:render('HP Threshold %', 'Your health percentage threshold')
    end

    -- Resource condition
    e.use_res_condition:render('Resource Condition', 'Only cast when your primary resource (mana, fury, etc.) meets a threshold')
    if e.use_res_condition:get() then
        e.res_mode:render('Mode', { 'Below %', 'Above %' }, 'Below %: cast when resource is low. Above %: cast when resource is high (e.g. spenders)')
        e.res_threshold:render('Threshold %', 'Percentage of max resource (1-100). Skipped gracefully if API returns 0 (e.g. Rogue energy)')
    end

    -- ── Channel / Movement flags ─────────────────────────────────────
    e.is_channel:render('Channel Spell', 'This spell is channeled (Whirlwind, Incinerate, etc.) — will keep channeling while conditions are met')
    
    -- Auto-sync: channel_break_for_cds matches is_channel state (only when is_channel changes)
    local is_channel_enabled = e.is_channel:get()
    local prev_channel_state = _prev_channel_state[spell_id]
    
    if prev_channel_state ~= is_channel_enabled then
        -- Channel Spell checkbox was just toggled
        _prev_channel_state[spell_id] = is_channel_enabled
        
        if is_channel_enabled then
            e.channel_break_for_cds:set(true)
        else
            e.channel_break_for_cds:set(false)
        end
    end
    
    -- Always show Break for Cooldowns (user can manually toggle it)
    e.channel_break_for_cds:render('Break for Cooldowns', 'Cast ready cooldown spells while channeling (without interrupting the channel)')
    
    e.is_movement:render('Movement Spell (Gap Closer)', 'Use this spell to close distance to melee targets (dash, teleport, leap, etc.). Fires automatically when a melee target is out of range.')
    if e.is_movement:get() then
        e.min_range:render('Minimum Range', 'Don\'t cast if target is closer than this distance (0 = no minimum). Prevents wasting charges on very close targets.', 1)
    end
    e.is_evade:render('Movement Spell (On Danger)', 'Fire this spell automatically when the player enters a dangerous position (evade zone). Bypasses normal rotation priority. Use for defensive dashes or escapes.')

    -- ── Combo Chain ──────────────────────────────────────────────────
    e.combo_enabled:render('Combo Chain', 'After casting this spell, boost another spell priority')
    if e.combo_enabled:get() then
        local combo_items = { 'None' }
        local combo_ids   = { 0 }
        -- Always include Evade as an option (ID 337031, not on bar)
        if spell_id ~= 337031 then
            combo_items[#combo_items + 1] = 'Evade'
            combo_ids[#combo_ids + 1]     = 337031
        end
        for i, id in ipairs(_equipped_ids) do
            if id and id > 1 and id ~= spell_id then
                combo_items[#combo_items + 1] = _equipped_names[i] or ('Spell ' .. id)
                combo_ids[#combo_ids + 1]     = id
            end
        end

        local cs = _combo_state[tostring(spell_id)]
        if cs and cs.target_id and cs.target_id > 0 then
            local found = false
            for idx, cid in ipairs(combo_ids) do
                if cid == cs.target_id then
                    local cur_sel = e.combo_spell_sel:get()
                    if type(cur_sel) ~= 'number' or cur_sel ~= (idx - 1) then
                        pcall(function() e.combo_spell_sel:set(idx - 1) end)
                    end
                    found = true
                    break
                end
            end
            if not found and cs.target_id > 0 then
                local missing_name = get_name_for_spell(cs.target_id) or ('Spell ' .. cs.target_id)
                combo_items[#combo_items + 1] = missing_name .. ' (not equipped)'
                combo_ids[#combo_ids + 1]     = cs.target_id
                pcall(function() e.combo_spell_sel:set(#combo_items - 1) end)
            end
        end

        e.combo_spell_sel:render('Chain to Spell', combo_items, 'Which spell to boost after casting this one')

        local sel         = e.combo_spell_sel:get()
        if type(sel) ~= 'number' then sel = 0 end
        local selected_id = combo_ids[sel + 1] or 0

        if not _combo_state[tostring(spell_id)] then
            _combo_state[tostring(spell_id)] = { target_id = 0 }
        end
        _combo_state[tostring(spell_id)].target_id = selected_id

        e.combo_window:render('Combo Window (s)', 'How long the priority boost lasts', 1)
        e.combo_boost:render('Boosted Priority', 'Priority of the chained spell during the window (1=highest)', 1)
    end

    -- ── SEQUENCE FORMULA ─────────────────────────────────────────────
    e.seq_enabled:render('Sequence Formula', 'Cast this spell as part of a fixed-order sequence (A -> B -> C).')

    if e.seq_enabled:get() then
        e.seq_step:render('Step (1 = first)', 'Order of this spell in the sequence. Step 1 fires freely; later steps fire only after the previous step lands.')
        e.seq_window:render('Window (s)', 'Seconds to land the next step before the sequence resets.', 1)
        e.seq_cd_behavior:render(
            'On Cooldown',
            { 'Pause (cast others freely)', 'Wait (hold all)', 'Skip (advance)', 'Reset (restart)' },
            'What to do when this step is due but still on cooldown.'
        )

        -- ── Sequence Name ────────────────────────────────────────────
        local cur_name    = _get_seq_name(spell_id)
        local known_names = spell_config.get_all_sequence_names()

        local name_items  = {}
        local name_values = {}

        local cur_label = (cur_name ~= '') and ('[Active] ' .. cur_name) or '-- pick a name --'
        name_items[1]   = cur_label
        name_values[1]  = cur_name

        for _, n in ipairs(known_names) do
            if n ~= cur_name then
                name_items[#name_items + 1]  = n
                name_values[#name_values + 1] = n
            end
        end

        local existing_set = {}
        for _, n in ipairs(known_names) do existing_set[n] = true end
        for _, p in ipairs(SEQ_PRESETS) do
            if not existing_set[p] and p ~= cur_name then
                name_items[#name_items + 1]  = '[New] ' .. p
                name_values[#name_values + 1] = p
            end
        end

        local nce = _elements[tostring(spell_id)].seq_name_combo
        if not nce then
            nce = combo_box:new(0, get_hash(key(spell_id, 'seq_name_sel')))
            _elements[tostring(spell_id)].seq_name_combo = nce
        end

        nce:render('Sequence Name', name_items, 'Spells sharing the same name and consecutive steps form one sequence.')

        local sel_idx = nce:get()
        if type(sel_idx) == 'number' and sel_idx > 0 then
            local picked = name_values[sel_idx + 1]
            if picked and picked ~= '' and picked ~= cur_name then
                _set_seq_name(spell_id, picked)
                pcall(function() nce:set(0) end)
            end
        end

        local active = _get_seq_name(spell_id)
        if active ~= '' then
            render_menu_header('Sequence: "' .. active .. '"  |  Step: ' .. e.seq_step:get())
        else
            render_menu_header('[!] Pick a Sequence Name above.')
        end
    end
    
    -- Visual range indicator (at the end of advanced settings)
    e.show_range:render('Show Spell Range Circle', 'Draw a circle around the player showing this spell\'s range')

    e.advanced_tree:pop()
    end -- advanced_tree
end

-- ────────────────────────────────────────────────────────────────────────────
-- Focused render for Evade — only Sequence Formula settings
-- Called from gui.lua Evade Settings section
-- ────────────────────────────────────────────────────────────────────────────
function spell_config.render_evade_sequence(spell_id)
    local e = get_elements(spell_id)

    e.seq_enabled:render('Enable Sequence', 'Include Evade as a step in a cast sequence')
    if not e.seq_enabled:get() then return end

    e.seq_step:render('Step (1 = first)', 'Position of Evade in the sequence. Step 1 fires freely; later steps fire only after the previous step lands.')
    e.seq_window:render('Window (s)', 'Seconds to land the next step before the sequence resets.', 1)
    e.seq_cd_behavior:render(
        'On Cooldown',
        { 'Pause (cast others freely)', 'Wait (hold all)', 'Skip (advance)', 'Reset (restart)' },
        'What to do when Evade is due but still on cooldown.'
    )

    local cur_name    = _get_seq_name(spell_id)
    local known_names = spell_config.get_all_sequence_names()
    local name_items  = {}
    local name_values = {}

    local cur_label = (cur_name ~= '') and ('[Active] ' .. cur_name) or '-- pick a name --'
    name_items[1]   = cur_label
    name_values[1]  = cur_name

    for _, n in ipairs(known_names) do
        if n ~= cur_name then
            name_items[#name_items + 1]  = n
            name_values[#name_values + 1] = n
        end
    end

    local existing_set = {}
    for _, n in ipairs(known_names) do existing_set[n] = true end
    for _, p in ipairs(SEQ_PRESETS) do
        if not existing_set[p] and p ~= cur_name then
            name_items[#name_items + 1]  = '[New] ' .. p
            name_values[#name_values + 1] = p
        end
    end

    local nce = _elements[tostring(spell_id)].seq_name_combo
    if not nce then
        nce = combo_box:new(0, get_hash(key(spell_id, 'seq_name_sel')))
        _elements[tostring(spell_id)].seq_name_combo = nce
    end

    nce:render('Sequence Name', name_items, 'Spells sharing the same name and consecutive steps form one sequence.')

    local sel_idx = nce:get()
    if type(sel_idx) == 'number' and sel_idx > 0 then
        local picked = name_values[sel_idx + 1]
        if picked and picked ~= '' and picked ~= cur_name then
            _set_seq_name(spell_id, picked)
            pcall(function() nce:set(0) end)
        end
    end

    local active = _get_seq_name(spell_id)
    if active ~= '' then
        render_menu_header('Sequence: "' .. active .. '"  |  Step: ' .. e.seq_step:get())
    else
        render_menu_header('[!] Pick a Sequence Name above.')
    end
end

-- ────────────────────────────────────────────────────────────────────────────
-- Focused render for Evade — only Combo Chain settings
-- Called from gui.lua Evade Settings section
-- ────────────────────────────────────────────────────────────────────────────
function spell_config.render_evade_combo(spell_id)
    local e = get_elements(spell_id)

    e.combo_enabled:render('Enable Combo Chain', 'After Evade fires, temporarily boost another spell\'s priority')
    if not e.combo_enabled:get() then return end

    local combo_items = { 'None' }
    local combo_ids   = { 0 }
    for i, id in ipairs(_equipped_ids) do
        if id and id > 1 then
            combo_items[#combo_items + 1] = _equipped_names[i] or ('Spell ' .. id)
            combo_ids[#combo_ids + 1]     = id
        end
    end

    local cs = _combo_state[tostring(spell_id)]
    if cs and cs.target_id and cs.target_id > 0 then
        local found = false
        for idx, cid in ipairs(combo_ids) do
            if cid == cs.target_id then
                local cur_sel = e.combo_spell_sel:get()
                if type(cur_sel) ~= 'number' or cur_sel ~= (idx - 1) then
                    pcall(function() e.combo_spell_sel:set(idx - 1) end)
                end
                found = true
                break
            end
        end
        if not found and cs.target_id > 0 then
            local missing_name = get_name_for_spell(cs.target_id) or ('Spell ' .. cs.target_id)
            combo_items[#combo_items + 1] = missing_name .. ' (not equipped)'
            combo_ids[#combo_ids + 1]     = cs.target_id
            pcall(function() e.combo_spell_sel:set(#combo_items - 1) end)
        end
    end

    e.combo_spell_sel:render('Boost Spell', combo_items, 'Which spell gets a priority boost after Evade fires')

    local sel = e.combo_spell_sel:get()
    if type(sel) ~= 'number' then sel = 0 end
    local selected_id = combo_ids[sel + 1] or 0
    if not _combo_state[tostring(spell_id)] then
        _combo_state[tostring(spell_id)] = { target_id = 0 }
    end
    _combo_state[tostring(spell_id)].target_id = selected_id

    e.combo_window:render('Combo Window (s)', 'How long the priority boost lasts', 1)
    e.combo_boost:render('Priority Boost', 'How much to subtract from the boosted spell\'s base priority', 1)
end

-- ────────────────────────────────────────────────────────────────────────────
-- spell_config.get  — returns a flat config table used by rotation_engine
-- ────────────────────────────────────────────────────────────────────────────
function spell_config.get(spell_id)
    local e  = get_elements(spell_id)
    local st = _get_buff_state(spell_id)

    return {
        enabled       = e.enabled:get(),
        priority      = e.priority:get(),

        cooldown      = e.cooldown:get(),
        charges       = e.charges:get(),

        spell_type    = e.spell_type:get(),
        target_mode   = e.target_mode:get(),

        range         = e.range:get(),
        aoe_range     = e.aoe_range:get(),

        elite_only    = e.elite_only:get(),
        boss_only     = e.boss_only:get(),
        min_enemies   = e.min_enemies:get(),

        skip_small_packs = e.skip_small_packs:get(),
        min_pack_size    = e.min_pack_size:get(),
        use_on_hard_only = e.use_on_hard_only:get(),

        require_buff  = e.require_buff:get(),
        buff_hash     = st.buff_hash or 0,
        buff_name     = (st.buff_name ~= '' and st.buff_name) or (_buff_name_cache[tostring(spell_id)] or ''),
        buff_stacks   = e.buff_stacks:get(),
        use_on_cooldown = e.use_on_cooldown:get(),

        use_hp_condition  = e.use_hp_condition:get(),
        hp_mode           = e.hp_mode:get(),
        hp_threshold      = e.hp_threshold:get(),

        use_res_condition = e.use_res_condition:get(),
        res_mode          = e.res_mode:get(),
        res_threshold     = e.res_threshold:get(),

        self_cast         = e.self_cast:get(),

        combo_enabled   = e.combo_enabled:get(),
        combo_spell_id  = (_combo_state[tostring(spell_id)] and _combo_state[tostring(spell_id)].target_id) or 0,
        combo_window    = e.combo_window:get(),
        combo_boost     = e.combo_boost:get(),

        is_movement     = e.is_movement:get(),
        min_range       = e.min_range:get(),
        is_evade        = e.is_evade:get(),
        is_channel      = e.is_channel:get(),
        channel_break_for_cds = e.channel_break_for_cds:get(),

        -- Sequence formula fields
        seq_enabled     = e.seq_enabled:get(),
        seq_name        = _get_seq_name(spell_id),
        seq_step        = e.seq_step:get(),
        seq_window      = e.seq_window:get(),
        seq_cd_behavior = e.seq_cd_behavior:get(),
        
        -- Visual range indicator
        show_range      = e.show_range:get(),
    }
end

-- ────────────────────────────────────────────────────────────────────────────
-- spell_config.apply  — used by profile import
-- ────────────────────────────────────────────────────────────────────────────
local function _set_element(el, val)
    if not el then return end
    if type(el.set) == 'function' then pcall(el.set, el, val); return end
    if type(el.set_value) == 'function' then pcall(el.set_value, el, val); return end
end

function spell_config.apply(spell_id, cfg)
    if type(cfg) ~= 'table' then return end
    local e  = get_elements(spell_id)
    local st = _get_buff_state(spell_id)

    _set_element(e.enabled,   cfg.enabled)
    -- Accept priority, priority_st, or priority_aoe from old profiles — use whichever is present
    _set_element(e.priority, cfg.priority or cfg.priority_st or cfg.priority_aoe)

    _set_element(e.cooldown,  cfg.cooldown)
    _set_element(e.charges,   cfg.charges)
    _set_element(e.spell_type, cfg.spell_type)
    _set_element(e.target_mode, cfg.target_mode)

    _set_element(e.range,     cfg.range)
    _set_element(e.aoe_range, cfg.aoe_range)

    _set_element(e.elite_only,   cfg.elite_only)
    _set_element(e.boss_only,    cfg.boss_only)
    _set_element(e.min_enemies,  cfg.min_enemies)
    _set_element(e.skip_small_packs, cfg.skip_small_packs)
    _set_element(e.min_pack_size,    cfg.min_pack_size)
    _set_element(e.use_on_hard_only, cfg.use_on_hard_only)
    _set_element(e.require_buff, cfg.require_buff)
    _set_element(e.buff_stacks,  cfg.buff_stacks)
    _set_element(e.use_on_cooldown, cfg.use_on_cooldown)

    _set_element(e.use_hp_condition, cfg.use_hp_condition)
    _set_element(e.hp_mode,          cfg.hp_mode)
    _set_element(e.hp_threshold,     cfg.hp_threshold)
    _set_element(e.use_res_condition, cfg.use_res_condition)
    _set_element(e.res_mode,          cfg.res_mode)
    _set_element(e.res_threshold,     cfg.res_threshold)
    _set_element(e.self_cast,         cfg.self_cast)

    _set_element(e.combo_enabled, cfg.combo_enabled)
    if type(cfg.combo_spell_id) == 'number' then
        if not _combo_state[tostring(spell_id)] then
            _combo_state[tostring(spell_id)] = { target_id = 0 }
        end
        _combo_state[tostring(spell_id)].target_id = cfg.combo_spell_id
    end
    _set_element(e.combo_window, cfg.combo_window)
    _set_element(e.combo_boost,  cfg.combo_boost)
    _set_element(e.is_movement,  cfg.is_movement)
    _set_element(e.min_range,    cfg.min_range)
    _set_element(e.is_evade,     cfg.is_evade)
    _set_element(e.is_channel,   cfg.is_channel)
    _set_element(e.channel_break_for_cds, cfg.channel_break_for_cds)

    -- Sequence fields
    _set_element(e.seq_enabled,     cfg.seq_enabled)
    _set_element(e.seq_step,        cfg.seq_step)
    _set_element(e.seq_window,      cfg.seq_window)
    _set_element(e.seq_cd_behavior, cfg.seq_cd_behavior)
    if type(cfg.seq_name) == 'string' and cfg.seq_name ~= '' then
        _set_seq_name(spell_id, cfg.seq_name)
    end
    
    -- Visual range indicator
    _set_element(e.show_range, cfg.show_range)

    if type(cfg.buff_hash) == 'number' then st.buff_hash = cfg.buff_hash end
    if type(cfg.buff_name) == 'string' then st.buff_name = cfg.buff_name end
    if type(cfg.buff_name) == 'string' and cfg.buff_name ~= '' then
        _buff_name_cache[tostring(spell_id)] = cfg.buff_name
    end

    st.last_list_sig = nil
    e.buff_combo     = nil
end

return spell_config
