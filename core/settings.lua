local gui = require "gui"
local settings = {
    enabled = false,
    movement = true,
    salvage = true,
    path_angle = 1,
    silent_chest = true,
    helltide_chest = true,
    ore = true,
    herb = true,
    shrine = true,
    goblin = true,
    event = true,
    forced_chest_interval = 1,
    chest_detection_range = 30,
    chest_blacklist_duration = 2,
    chest_nav_log_interval = 1,
    chest_rescan_interval = 1,
}

function settings:update_settings()
    settings.enabled = gui.elements.main_toggle:get()
    settings.movement = gui.elements.movement_toggle:get()
    settings.salvage = gui.elements.salvage_toggle:get()
    settings.silent_chest = gui.elements.silent_chest_toggle:get()
    settings.helltide_chest = gui.elements.helltide_chest_toggle:get()
    settings.ore = gui.elements.ore_toggle:get()
    settings.herb = gui.elements.herb_toggle:get()
    settings.shrine = gui.elements.shrine_toggle:get()
    settings.goblin = gui.elements.goblin_toggle:get()
    settings.event = gui.elements.event_toggle:get()
    settings.chaos_rift = gui.elements.chaos_rift_toggle:get()
    settings.forced_chest_interval = gui.elements.forced_chest_interval:get()
    settings.chest_blacklist_duration = gui.elements.chest_blacklist_duration:get()
    settings.chest_nav_log_interval = gui.elements.chest_nav_log_interval:get()
    settings.chest_rescan_interval = gui.elements.chest_rescan_interval:get()
end

return settings