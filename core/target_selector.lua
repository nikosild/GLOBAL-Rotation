local target_selector = {}

local SCAN_RANGE = 16.0

local function _try(fn, ...)
    local ok, v = pcall(fn, ...)
    if not ok then return nil end
    return v
end

local function _truthy(fn, ...)
    local v = _try(fn, ...)
    return v and true or false
end

local function _pos(obj)
    return _try(function() return obj:get_position() end)
end

local function _dist2(a_pos, b_pos)
    if a_pos and a_pos.squared_dist_to_ignore_z then
        return _try(function() return a_pos:squared_dist_to_ignore_z(b_pos) end) or math.huge
    end
    if not (a_pos and b_pos and a_pos.x and b_pos.x) then return math.huge end
    local dx = a_pos:x() - b_pos:x()
    local dy = a_pos:y() - b_pos:y()
    return dx * dx + dy * dy
end

function target_selector.dist2(a_pos, b_pos)
    return _dist2(a_pos, b_pos)
end

local function _is_dead(obj)
    return _truthy(function() return obj:is_dead() end)
end

local function _get_health(obj)
    return _try(function() return obj:get_current_health() end) or 0
end

local function _is_valid_enemy(obj)
    if not obj then return false end
    if _is_dead(obj) then return false end
    if obj.is_enemy and not _truthy(function() return obj:is_enemy() end) then return false end
    if obj.is_hidden and _truthy(function() return obj:is_hidden() end) then return false end
    if obj.is_invulnerable and _truthy(function() return obj:is_invulnerable() end) then return false end
    if obj.is_town_npc and _truthy(function() return obj:is_town_npc() end) then return false end
    return true
end

local function _enemy_list()
    if not actors_manager then return {} end
    if type(actors_manager.get_enemy_npcs) == 'function' then
        return _try(actors_manager.get_enemy_npcs) or {}
    end
    if type(actors_manager.get_enemies) == 'function' then
        return _try(actors_manager.get_enemies) or {}
    end
    return {}
end

local function _is_boss(obj)     return obj.is_boss and _truthy(function() return obj:is_boss() end) end
local function _is_elite(obj)    return obj.is_elite and _truthy(function() return obj:is_elite() end) end
local function _is_champion(obj) return obj.is_champion and _truthy(function() return obj:is_champion() end) end

------------------------------------------------------------
-- Target selection mode labels
------------------------------------------------------------
target_selector.mode_labels = { 'Priority', 'Closest', 'Lowest HP', 'Highest HP', 'Cleave Center' }
target_selector.MODE_PRIORITY = 0
target_selector.MODE_CLOSEST  = 1
target_selector.MODE_LOWEST   = 2
target_selector.MODE_HIGHEST  = 3
target_selector.MODE_CLEAVE   = 4

------------------------------------------------------------
-- Get all targets with metadata
------------------------------------------------------------
function target_selector.get_targets(player_pos, range)
    range = range or SCAN_RANGE
    local r2 = range * range

    local enemies = _enemy_list()
    local result = {
        is_valid       = false,
        closest        = nil,
        closest_elite  = nil,
        closest_boss   = nil,
        closest_champ  = nil,
        has_elite      = false,
        has_boss       = false,
        has_champion   = false,
        enemy_count    = 0,
        all_enemies    = {},
    }

    local closest_dist       = math.huge
    local closest_elite_dist = math.huge
    local closest_boss_dist  = math.huge
    local closest_champ_dist = math.huge

    for _, enemy in ipairs(enemies or {}) do
        if not _is_valid_enemy(enemy) then goto continue end

        local epos = _pos(enemy)
        if not epos then goto continue end

        local d2 = _dist2(epos, player_pos)
        if d2 > r2 then goto continue end

        result.is_valid = true
        result.enemy_count = result.enemy_count + 1
        result.all_enemies[#result.all_enemies + 1] = enemy

        if d2 < closest_dist then
            closest_dist = d2
            result.closest = enemy
        end

        if _is_boss(enemy) then
            result.has_boss = true
            if d2 < closest_boss_dist then
                closest_boss_dist = d2
                result.closest_boss = enemy
            end
        elseif _is_elite(enemy) then
            result.has_elite = true
            if d2 < closest_elite_dist then
                closest_elite_dist = d2
                result.closest_elite = enemy
            end
        elseif _is_champion(enemy) then
            result.has_champion = true
            if d2 < closest_champ_dist then
                closest_champ_dist = d2
                result.closest_champ = enemy
            end
        end

        ::continue::
    end

    return result
end

------------------------------------------------------------
-- Pick target based on mode
------------------------------------------------------------
function target_selector.pick_target(targets, spell_cfg, player_pos, range)
    if not (targets and targets.is_valid) then return nil end

    local r2 = nil
    if range and player_pos then r2 = range * range end

    local function in_range(enemy)
        if not r2 then return true end
        local epos = _pos(enemy)
        if not epos then return false end
        return _dist2(epos, player_pos) <= r2
    end

    -- Collect in-range candidates
    local candidates = {}
    for _, e in ipairs(targets.all_enemies or {}) do
        if e and in_range(e) then
            candidates[#candidates + 1] = e
        end
    end
    if #candidates == 0 then return nil end

    -- Enforce boss_only / elite_only filters
    if spell_cfg and spell_cfg.boss_only then
        local filtered = {}
        for _, e in ipairs(candidates) do
            if _is_boss(e) then filtered[#filtered + 1] = e end
        end
        candidates = filtered
        if #candidates == 0 then return nil end
    elseif spell_cfg and spell_cfg.elite_only then
        local filtered = {}
        for _, e in ipairs(candidates) do
            if _is_boss(e) or _is_elite(e) or _is_champion(e) then
                filtered[#filtered + 1] = e
            end
        end
        candidates = filtered
        if #candidates == 0 then return nil end
    end

    local mode = (spell_cfg and spell_cfg.target_mode) or 0

    -- Mode 0: Priority (boss > elite > champion > closest)
    if mode == target_selector.MODE_PRIORITY then
        local best_boss, best_elite, best_champ, best_any = nil, nil, nil, nil
        local bd, ed, cd, ad = math.huge, math.huge, math.huge, math.huge
        for _, e in ipairs(candidates) do
            local d2 = _dist2(_pos(e), player_pos)
            if _is_boss(e) and d2 < bd then best_boss = e; bd = d2 end
            if _is_elite(e) and d2 < ed then best_elite = e; ed = d2 end
            if _is_champion(e) and d2 < cd then best_champ = e; cd = d2 end
            if d2 < ad then best_any = e; ad = d2 end
        end
        return best_boss or best_elite or best_champ or best_any
    end

    -- Mode 1: Closest
    if mode == target_selector.MODE_CLOSEST then
        local best, best_d2 = nil, math.huge
        for _, e in ipairs(candidates) do
            local d2 = _dist2(_pos(e), player_pos)
            if d2 < best_d2 then best = e; best_d2 = d2 end
        end
        return best
    end

    -- Mode 2: Lowest HP (execute)
    if mode == target_selector.MODE_LOWEST then
        local best, best_hp = nil, math.huge
        for _, e in ipairs(candidates) do
            local hp = _get_health(e)
            if hp < best_hp then best = e; best_hp = hp end
        end
        return best
    end

    -- Mode 3: Highest HP
    if mode == target_selector.MODE_HIGHEST then
        local best, best_hp = nil, -1
        for _, e in ipairs(candidates) do
            local hp = _get_health(e)
            if hp > best_hp then best = e; best_hp = hp end
        end
        return best
    end

    -- Mode 4: Cleave center (enemy with most others nearby)
    if mode == target_selector.MODE_CLEAVE then
        local cleave_radius = (spell_cfg and spell_cfg.aoe_range) or 6.0
        local cr2 = cleave_radius * cleave_radius
        local best, best_count = nil, -1
        for _, e in ipairs(candidates) do
            local epos = _pos(e)
            if epos then
                local count = 0
                for _, o in ipairs(candidates) do
                    local opos = _pos(o)
                    if opos and _dist2(epos, opos) <= cr2 then count = count + 1 end
                end
                if count > best_count then best = e; best_count = count end
            end
        end
        return best
    end

    -- Fallback
    local best, best_d2 = nil, math.huge
    for _, e in ipairs(candidates) do
        local d2 = _dist2(_pos(e), player_pos)
        if d2 < best_d2 then best = e; best_d2 = d2 end
    end
    return best
end

------------------------------------------------------------
-- Count enemies near player position
------------------------------------------------------------
function target_selector.count_near(targets, pos, radius)
    if not (targets and targets.all_enemies) then return 0 end
    local r2 = radius * radius
    local c = 0
    for _, enemy in ipairs(targets.all_enemies) do
        local epos = _pos(enemy)
        if epos and _dist2(epos, pos) <= r2 then c = c + 1 end
    end
    return c
end

return target_selector
