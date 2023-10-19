local function contains(table, val)
   for i=1,#table do
      if table[i] == val then
         return true
      end
   end
   return false
end

---@param player_index uint
local function build_sprite_buttons(player_index)
    local player_global = global.players[player_index]

    local button_table = player_global.elements.button_table
    button_table.clear()

    local items = player_global.items
    local active_items = player_global.active_items
    for name, sprite_name in pairs(items) do
        local button_style = (contains(active_items, name) and "yellow_slot_button" or "recipe_slot_button")
        local action = (contains(active_items, name) and "fh_deselect_button" or "fh_select_button")
        if game.is_valid_sprite_path(sprite_name) then
            button_table.add {
                type = "sprite-button",
                sprite = sprite_name,
                tags = {
                    action = action,
                    item_name = name ---@type string
                },
                style = button_style
            }
        end
    end
end

---@param player_index uint
local function build_interface(player_index)
    local player_global = global.players[player_index]
    local player = game.get_player(player_index)
    if not player then
        return
    end

    if player_global.elements.main_frame ~= nil then
        player_global.elements.main_frame.destroy()
    end

    local relative_gui_type = defines.relative_gui_type.inserter_gui

    if player_global.entity.type == "splitter" then
        relative_gui_type = defines.relative_gui_type.splitter_gui
    end

    if player_global.entity.type == "loader" or player_global.entity.type == "loader-1x1" then
        relative_gui_type = defines.relative_gui_type.loader_gui
    end

    local anchor = {
        gui = relative_gui_type,
        position = defines.relative_gui_position.right
    }

    ---@type LuaGuiElement
    local main_frame = player.gui.relative.add{
        type = "scroll-pane",
        name = "main_frame",
        anchor = anchor
    }

    player_global.elements.main_frame = main_frame

    ---@type LuaGuiElement
    local content_frame = main_frame.add{
        type="frame",
        name="content_frame",
        direction="vertical",
        style = "fh_content_frame"
    }

    ---@type LuaGuiElement
    local button_frame = content_frame.add{
        type="frame",
        name="button_frame",
        direction="vertical",
        style = "fh_deep_frame"
    }
    ---@type LuaGuiElement
    local button_table = button_frame.add{
        type="table",
        name="button_table",
        column_count=1,
        style="filter_slot_table"
    }
    player_global.elements.button_table = button_table
    build_sprite_buttons(player_index)
end

---@param player_index uint
local function close_vanilla_ui_for_rebuild(player_index)
    local player_global = global.players[player_index]
    local player = game.get_player(player_index)
    if not player then
        return
    end
    -- close gui to be reopened next tick to refresh ui
    player_global.needs_reopen = true
    player_global.reopen = player.opened
    player_global.reopen_tick = game.tick
    player.opened = nil
end

---@param player_index uint
local function reopen_vanilla(player_index)
    local player_global = global.players[player_index]
    local player = game.get_player(player_index)
    player.opened = player_global.reopen
    player_global.needs_reopen = false
    player_global.reopen = nil
end

---@param player_index uint
local function init_global(player_index)
    ---@class PlayerTable
    global.players[player_index] = {
        elements = {},
        items = {}, ---@type table<string, SpritePath>
        active_items = {}, ---@type table<string, string>
        entity = nil, ---@type LuaEntity?
        needs_reopen = false,
        reopen = nil,
        reopen_tick = 0
    }
end

local FilterHelper = {}

-- this is run every tick when a filter gui is open to detect vanilla changes
-- active_items is a list of item names
---@param entity LuaEntity?
---@return table<string>
function FilterHelper.get_active_items(entity)
    if not entity or not entity.valid then
        return {}
    end
    local active_items = {}
    if entity.filter_slot_count > 0 and entity.type ~= "infinity-container" then
        for i = 1, entity.filter_slot_count do ---@type uint
            table.insert(active_items, entity.get_filter(i))
        end
    end
    if entity.type == "splitter" and entity.splitter_filter ~= nil then
        local item = entity.splitter_filter.name
        table.insert(active_items, item)
    end
    --TODO handle circuits
    return active_items
end

---@param entity LuaEntity
---@param items table<string, SpritePath>
---@param upstream uint?
---@param downstream uint?
---Adds to the filter item list for a transport belt
function FilterHelper.add_items_belt(entity, items, upstream, downstream)
    --TODO user config for this
    upstream = upstream or 10
    downstream = downstream or 10

    if entity.type == "transport-belt" then
        for i = 1, entity.get_max_transport_line_index() do ---@type uint
            local transport_line = entity.get_transport_line(i)
            for item, _ in pairs(transport_line.get_contents()) do
                items[item] = "item/" .. item
            end
        end
        if upstream > 0 then
            for _, belt in pairs(entity.belt_neighbours.inputs) do
                FilterHelper.add_items_belt(belt, items, upstream - 1, 0)
            end
        end
        if downstream > 0 then
            for _, belt in pairs(entity.belt_neighbours.outputs) do
                FilterHelper.add_items_belt(belt, items, 0, downstream - 1)
            end
        end
    end
end

---@param entity LuaEntity
---@param items table<string, SpritePath>
---Adds to the filter item list for an underground belt
function FilterHelper.add_items_underground_belt(entity, items)
    if entity.type ~= "underground-belt" then return end

    FilterHelper.add_items_transport_belt_connectable(entity, items)
end

---@param entity LuaEntity
---@param items table<string, SpritePath>
---Adds to the filter item list based on an entity being taken from
function FilterHelper.add_items_pickup_target_entity(target, items)
    if target.type == "assembling-machine" and target.get_recipe() ~= nil then
        for _, item in pairs(target.get_recipe().products) do
            items[item.name] = "item/" .. item.name
        end
    end
    if target.get_output_inventory() ~= nil then
        for item, _ in pairs(target.get_output_inventory().get_contents()) do
            items[item] = "item/" .. item
        end
    end
    if target.get_burnt_result_inventory() ~= nil then
        for item, _ in pairs(target.get_burnt_result_inventory().get_contents()) do
            items[item] = "item/" .. item
        end
    end
    if target.type == "transport-belt" then
        FilterHelper.add_items_belt(target, items)
    end
    if target.type == "splitter" then
        FilterHelper.add_items_splitter(target, items)
    end
    if target.type == "underground-belt" then
        FilterHelper.add_items_underground_belt(target, items)
    end
end

---@param entity LuaEntity
---@param items table<string, SpritePath>
---Adds to the filter item list based on an entity being given to
function FilterHelper.add_items_drop_target_entity(target, items)
    if target.type == "assembling-machine" and target.get_recipe() ~= nil then
        for _, item in pairs(target.get_recipe().ingredients) do
            items[item.name] = "item/" .. item.name
        end
    end
    if target.get_output_inventory() ~= nil then
        for item, _ in pairs(target.get_output_inventory().get_contents()) do
            items[item] = "item/" .. item
        end
    end
    if target.get_fuel_inventory() ~= nil then
        for item, _ in pairs(target.get_fuel_inventory().get_contents()) do
            items[item] = "item/" .. item
        end
    end
    if target.type == "transport-belt" then
        FilterHelper.add_items_belt(target, items)
    end
    if target.type == "splitter" then
        FilterHelper.add_items_splitter(target, items)
    end
    if target.type == "underground-belt" then
        FilterHelper.add_items_underground_belt(target, items)
    end
end

---@param entity LuaEntity
---@param items table<string, SpritePath>
---Adds to the filter item list for an inserter
function FilterHelper.add_items_inserter(entity, items)
    if entity.type == "inserter" and entity.filter_slot_count > 0 then
        local pickup_target_list = entity.surface.find_entities_filtered { position = entity.pickup_position }

        if #pickup_target_list > 0 then
            for _, target in pairs(pickup_target_list) do
                FilterHelper.add_items_pickup_target_entity(target, items)
            end
        end

        local drop_target_list = entity.surface.find_entities_filtered { position = entity.drop_position }
        if #drop_target_list > 0 then
            for _, target in pairs(drop_target_list) do
                FilterHelper.add_items_drop_target_entity(target, items)
            end
        end
    end
end

---@param entity LuaEntity
---@param items table<string, SpritePath>
---Adds to the filter item list based on the connected transport belts
function FilterHelper.add_items_transport_belt_connectable(entity, items)
    for i = 1, entity.get_max_transport_line_index() do ---@type uint
        local transport_line = entity.get_transport_line(i)
        for item, _ in pairs(transport_line.get_contents()) do
            items[item] = "item/" .. item
        end
    end
    for _, belt in pairs(entity.belt_neighbours.inputs) do
        FilterHelper.add_items_belt(belt, items, nil, 0)
    end
    for _, belt in pairs(entity.belt_neighbours.outputs) do
        FilterHelper.add_items_belt(belt, items, 0, nil)
    end
end

---@param entity LuaEntity
---@param items table<string, SpritePath>
---Adds to the filter item list for a splitter
function FilterHelper.add_items_splitter(entity, items)
    if entity.type ~= "splitter" then return end
    
    FilterHelper.add_items_transport_belt_connectable(entity, items)
end

---@param entity LuaEntity
---@param items table<string, SpritePath>
---Adds to the filter item list for a loader
function FilterHelper.add_items_loader(entity, items)
    if entity.type ~= "loader" and entity.type ~= "loader-1x1" then return end

    FilterHelper.add_items_transport_belt_connectable(entity, items)

    if entity.loader_container and entity.loader_container.valid then
        if entity.loader_type == "input" then
            FilterHelper.add_items_drop_target_entity(entity.loader_container, items)
        elseif entity.loader_type == "output" then
            FilterHelper.add_items_pickup_target_entity(entity.loader_container, items)
        end
    end
end

---@param entity LuaEntity
---@param items table <string, SpritePath>
---Adds to the filter item list based on the connected circuit signals
function FilterHelper.add_items_circuit(entity, items)
    if entity.get_control_behavior() then
        local control = entity.get_control_behavior()
        if control and (
                control.type == defines.control_behavior.type.generic_on_off
                or control.type == defines.control_behavior.type.inserter
            ) then
            local signals = entity.get_merged_signals()
            if signals then
                for _, signal in pairs(signals) do
                    local signal_id = signal.signal
                    if signal_id.name then
                        items[signal_id.name] = signal_id.type .. "/" .. signal_id.name
                    end
                end
            end
        end
    end
end

---@param entity LuaEntity
---@param items table<string, SpritePath>
---@return table<string, SpritePath>
---Adds to the filter item list for the given entity
function FilterHelper.add_items(entity, items)
    if not entity or not entity.valid then
        return {}
    end
    FilterHelper.add_items_inserter(entity, items)
    FilterHelper.add_items_splitter(entity, items)
    FilterHelper.add_items_loader(entity, items)
    --TODO have a second column for signals
    FilterHelper.add_items_circuit(entity, items)
    return items
end

script.on_init(function()
    ---@type table<number, PlayerTable>
    global.players = {}
    for _, player in pairs(game.players) do
        init_global(player.index)
    end
end)

script.on_event(defines.events.on_player_created, function(event)
    init_global(event.player_index)
end)

-- EVENT on_gui_opened
script.on_event(defines.events.on_gui_opened, function(event)
    local player_global = global.players[event.player_index]

    -- the entity that is opened
    local entity = event.entity
    if entity ~= nil then
        player_global.entity = entity
        local items = FilterHelper.add_items(entity, {})
        player_global.items = items
        local active_items = FilterHelper.get_active_items(entity)
        player_global.active_items = active_items
        if next(items) ~= nil or next(active_items) ~= nil then
            build_interface(event.player_index)
        end
    end
end)

--EVENT on_gui_closed
script.on_event(defines.events.on_gui_closed, function(event)
    local player_global = global.players[event.player_index]
    if player_global.elements.main_frame ~= nil then
        player_global.elements.main_frame.destroy()
    end
end)

--EVENT on_gui_click
script.on_event(defines.events.on_gui_click, function(event)
    local player_global = global.players[event.player_index]
    local entity = player_global.entity
    local clicked_item_name = event.element.tags.item_name
    local need_refresh = false

    if entity and type(clicked_item_name) == "string" then
        if event.element.tags.action == "fh_select_button" then
            -- if an entity only has one filter, always set it
            if entity.filter_slot_count == 1 then
                entity.set_filter(1, clicked_item_name)
                need_refresh = true
            elseif entity.filter_slot_count > 1 then
                for i = 1, entity.filter_slot_count do ---@type uint
                    if entity.get_filter(i) == nil then
                        entity.set_filter(i, clicked_item_name)
                        need_refresh = true
                        break
                    end
                end
            elseif entity.type == "splitter" then
                entity.splitter_filter = game.item_prototypes[clicked_item_name]
                if entity.splitter_output_priority == "none" then
                    entity.splitter_output_priority = "left"
                end
                need_refresh = true
            end
            if need_refresh == false then
                -- Play fail sound if filter slots are full
                entity.surface.play_sound {
                    path = 'utility/cannot_build',
                    volume_modifier = 1.0
                }
                game.get_player(event.player_index).create_local_flying_text {
                    text = "Filters full",
                    create_at_cursor = true
                }
            end
        elseif event.element.tags.action == "fh_deselect_button" then
            if entity.filter_slot_count > 0 then
                for i = 1, entity.filter_slot_count do ---@type uint
                    if entity.get_filter(i) == clicked_item_name then
                        entity.set_filter(i, nil)
                        need_refresh = true
                    end
                end
            elseif entity.type == "splitter" then
                entity.splitter_filter = nil
                need_refresh = true
            end
        end
        if need_refresh then
            close_vanilla_ui_for_rebuild(event.player_index)
        end
    end
end)

-- we need to close the ui on click and open it a tick later
-- to visually update the filter ui
-- if https://forums.factorio.com/viewtopic.php?f=7&t=106300 gets addressed,
-- this close/reopen GUI business can be removed
script.on_event(defines.events.on_tick, function(event)
    for _, player in pairs(game.players) do
        local player_global = global.players[player.index]
        if player_global.needs_reopen and player_global.reopen_tick ~= event.tick then
            reopen_vanilla(player.index)
        end
        --update my gui when vanilla filter changes
        if player_global.elements.main_frame and player_global.elements.main_frame.valid then
            local entity = player_global.entity
            local active_items = FilterHelper.get_active_items(entity)
            if #active_items ~= #player_global.active_items then
                player_global.active_items = active_items
                build_sprite_buttons(player.index)
            end
        end
    end
end)

-- TODO options for what things are considered. Chests, transport lines, etc
-- TODO handle too many ingredients
-- TODO recently used section
-- TODO burnt result calculation
