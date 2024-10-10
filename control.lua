local get_filter_updater = require("filter_updaters")

local function contains(table, val)
    for i = 1, #table do
        if table[i] == val then
            return true
        end
    end
    return false
end

local function get_player_global(player_index)
    local player_global = global.players[player_index]
    if player_global and player_global.player and player_global.player.valid then
        return player_global
    end
end

local function build_sprite_buttons(player_global)
    local button_table = player_global.elements.button_table
    button_table.clear()

    local items = player_global.items
    local active_items = player_global.active_items
    local updater = player_global.entity.valid and get_filter_updater(player_global.entity)
    local button_description = updater and updater.button_description
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
                tooltip = { "fh.button-tooltip", game.item_prototypes[name].localised_name, button_description },
                style = button_style,
                mouse_button_filter = { "left", "right", "middle" },
            }
        end
    end
end

local buttons_per_column = 7 -- the maximum number of sprite-buttons per column in the gui
local max_columns = 10 -- the maximum number of columns to use for the gui

local function build_interface(player_global)
    if player_global.elements.main_frame then
        player_global.elements.main_frame.destroy()
    end

    local guis_table = {
        ["splitter"] = defines.relative_gui_type.splitter_gui,
        ["logistic-container"] = defines.relative_gui_type.container_gui,
        ["loader"] = defines.relative_gui_type.loader_gui,
        ["loader-1x1"] = defines.relative_gui_type.loader_gui,
        ["car"] = defines.relative_gui_type.car_gui,
        ["cargo-wagon"] = defines.relative_gui_type.container_gui,
        ["spider-vehicle"] = defines.relative_gui_type.spider_vehicle_gui,
    }
    local relative_gui_type = guis_table[player_global.entity.type] or defines.relative_gui_type.inserter_gui

    local anchor = {
        gui = relative_gui_type,
        position = defines.relative_gui_position.right
    }

    ---@type LuaGuiElement
    local main_frame = player_global.player.gui.relative.add {
        type = "frame",
        name = "main_frame",
        anchor = anchor,
        style = "fh_content_frame"
    }
    -- limit the height of the relative gui to fit 10 buttons per column
    -- if there are too many buttons, the scroll-pane allows them to be scrolled
    -- to be visible
    main_frame.style.maximal_height = buttons_per_column * 44
    main_frame.style.horizontally_stretchable = false

    player_global.elements.main_frame = main_frame

    ---@type LuaGuiElement
    local content_frame = main_frame.add {
        type = "scroll-pane",
        name = "content_frame",
        direction = "vertical",
    }
    content_frame.style.top_margin = 8

    ---@type LuaGuiElement
    local button_frame = content_frame.add {
        type = "frame",
        name = "button_frame",
        direction = "vertical",
        style = "fh_deep_frame"
    }

    -- use multiple columns if there are lots of buttons so its less
    -- likely to require the scroll pane for large amounts of found
    -- items to filter
    -- the scroll bar may still appear because the number of columns
    -- is capped to prevent the relative gui taking up too much horizontal space
    local items = player_global.items
    local item_count = 0
    for _ in pairs(items) do
        item_count = item_count + 1
    end
    local columns = math.ceil(item_count / buttons_per_column)
    columns = math.min(columns, max_columns)
    columns = math.max(columns, 1)

    ---@type LuaGuiElement
    local button_table = button_frame.add {
        type = "table",
        name = "button_table",
        column_count = columns,
        style = "filter_slot_table"
    }
    player_global.elements.button_table = button_table
    build_sprite_buttons(player_global)
end

local function close_vanilla_ui_for_rebuild(player_global)
    -- close gui to be reopened next tick to refresh ui
    local player = player_global.player
    player_global.needs_reopen = true
    player_global.reopen = player.opened
    player_global.reopen_tick = game.tick
    player.opened = nil
end

local function reopen_vanilla(player_global)
    player_global.player.opened = player_global.reopen
    player_global.needs_reopen = false
    player_global.reopen = nil
end

---@param player LuaPlayer
local function init_global(player)
    ---@class PlayerTable
    global.players[player.index] = {
        player = player,
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

    local updater = get_filter_updater(entity)
    --TODO handle circuits
    return updater and updater.get_active_items() or {}
end

---@param entity LuaEntity
---@param items table<string, SpritePath>
---@param upstream uint?
---@param downstream uint?
---Adds to the filter item list for a transport belt
function FilterHelper.add_items_belt(entity, items, upstream, downstream)
    --TODO user config for this
    upstream = upstream or 10 -- number of belts upstream (inputs) of this belt to check for filter items
    downstream = downstream or 10 -- number of belts downstream (outputs) of this belt to check for filter items

    if entity.type == "transport-belt" then
        for i = 1, entity.get_max_transport_line_index() do
            ---@type uint
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
    if entity.type ~= "underground-belt" then
        return
    end

    FilterHelper.add_items_transport_belt_connectable(entity, items)
end

---@param entity LuaEntity
---@param items table<string, SpritePath>
---Adds to the filter item list based on an entity being interacted with
function FilterHelper.add_items_interact_target_entity(target, items)
    if target.type == "transport-belt" then
        FilterHelper.add_items_belt(target, items)
    end
    if target.type == "splitter" then
        FilterHelper.add_items_transport_belt_connectable(target, items)
    end
    if target.type == "underground-belt" then
        FilterHelper.add_items_transport_belt_connectable(target, items)
    end
    if target.type == "loader" or target.type == "loader-1x1" then
        FilterHelper.add_items_transport_belt_connectable(target, items)
    end
end

---@param entity LuaEntity
---@param items table<string, SpritePath>
---Adds to the filter item list based on the result of burning fuel the entity burns
function FilterHelper.add_items_burnt_results_entity(entity, items)
    if not (entity.burner and entity.burner.valid) then
        return
    end

    local fuel_categories = entity.burner.fuel_categories
    for fuel_category, _ in pairs(fuel_categories) do
        for _, item_prototype in pairs(game.item_prototypes) do
            if item_prototype.fuel_category == fuel_category then
                local burnt_result_prototype = item_prototype.burnt_result
                if burnt_result_prototype then
                    items[burnt_result_prototype.name] = "item/" .. burnt_result_prototype.name
                end
            end
        end
    end
end

---@param items table<string, SpritePath>
---Adds to the filter item list based on the result of rocket launches
---Because any rocket silo can launch any item, it's not possible to filter
---this to a specific launch recipe (i.e. satellite -> space science or space science -> fish)
function FilterHelper.add_items_rocket_launch_products_entity(items)
    for _, item_prototype in pairs(game.item_prototypes) do
        if item_prototype.rocket_launch_products then
            for _, rocket_launch_product_prototype in pairs(item_prototype.rocket_launch_products) do
                items[rocket_launch_product_prototype.name] = "item/" .. rocket_launch_product_prototype.name
            end
        end
    end
end

---@param entity LuaEntity
---@param items table<string, SpritePath>
---Adds to the filter item list based on an entity being taken from
function FilterHelper.add_items_pickup_target_entity(target, items)
    if target.type == "assembling-machine" and target.get_recipe() ~= nil then
        for _, product in pairs(target.get_recipe().products) do
            if product.type == "item" then
                items[product.name] = "item/" .. product.name
            end
        end
    end
    if target.type == "rocket-silo" then
        FilterHelper.add_items_rocket_launch_products_entity(items)
    end
    if target.get_output_inventory() ~= nil then
        for item, _ in pairs(target.get_output_inventory().get_contents()) do
            items[item] = "item/" .. item
        end
    end
    FilterHelper.add_items_burnt_results_entity(target, items)
    FilterHelper.add_items_interact_target_entity(target, items)
end

---@param entity LuaEntity
---@param items table<string, SpritePath>
---Adds to the filter item list based on the fuel the entity burns
function FilterHelper.add_items_fuel_entity(entity, items)
    if not (entity.burner and entity.burner.valid) then
        return
    end

    local fuel_categories = entity.burner.fuel_categories
    for fuel_category, _ in pairs(fuel_categories) do
        for item_prototype_name, item_prototype in pairs(game.item_prototypes) do
            if item_prototype.fuel_category == fuel_category then
                items[item_prototype_name] = "item/" .. item_prototype_name
            end
        end
    end
end

---@param entity LuaEntity
---@param items table<string, SpritePath>
---Adds to the filter item list based on an entity being given to
function FilterHelper.add_items_drop_target_entity(target, items)
    if (target.type == "assembling-machine" or target.type == "rocket-silo") and target.get_recipe() ~= nil then
        for _, ingredient in pairs(target.get_recipe().ingredients) do
            if ingredient.type == "item" then
                items[ingredient.name] = "item/" .. ingredient.name
            end
        end
    end
    FilterHelper.add_items_fuel_entity(target, items)
    FilterHelper.add_items_interact_target_entity(target, items)
end

---@param entity LuaEntity
---@param items table<string, SpritePath>
---@param ignore_slots boolean?
---Adds to the filter item list for an inserter
function FilterHelper.add_items_inserter(entity, items, ignore_slots)
    if entity.type == "inserter" and (ignore_slots or entity.filter_slot_count > 0) then
        local pickup_target_list = entity.surface.find_entities_filtered { position = entity.pickup_position }

        if #pickup_target_list > 0 then
            for _, target in pairs(pickup_target_list) do
                if not target.prototype.has_flag("no-automated-item-removal") then
                    FilterHelper.add_items_pickup_target_entity(target, items)
                end
            end
        end

        local drop_target_list = entity.surface.find_entities_filtered { position = entity.drop_position }
        if #drop_target_list > 0 then
            for _, target in pairs(drop_target_list) do
                if not target.prototype.has_flag("no-automated-item-insertion") then
                    FilterHelper.add_items_drop_target_entity(target, items)
                end
            end
        end
    end
end

---@param entity LuaEntity
---@param items table<string, SpritePath>
---Adds to the filter item list based on the connected transport belts
function FilterHelper.add_items_transport_belt_connectable(entity, items)
    for i = 1, entity.get_max_transport_line_index() do
        ---@type uint
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
    if entity.type ~= "splitter" then
        return
    end

    FilterHelper.add_items_transport_belt_connectable(entity, items)
end

---@param entity LuaEntity
---@param items table<string, SpritePath>
---Adds to the filter item list for a loader
function FilterHelper.add_items_loader(entity, items)
    if entity.type ~= "loader" and entity.type ~= "loader-1x1" then
        return
    end

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
                    if signal_id.name and signal_id.type == "item" then
                        items[signal_id.name] = signal_id.type .. "/" .. signal_id.name
                    end
                end
            end
        end
    end
end

---@param entity LuaEntity
---@param items table <string, SpritePath>
function FilterHelper.add_items_chest(entity, items)
    if entity.type == "container" or entity.type == "logistic-container" then
        -- contents
        for item, _ in pairs(entity.get_output_inventory().get_contents()) do
            items[item] = "item/" .. item
        end

        -- relevant inserters
        local bb = entity.bounding_box
        local distance = 3
        local area = { { bb.left_top.x - distance, bb.left_top.y - distance }, { bb.right_bottom.x + distance, bb.right_bottom.y + distance } }

        for _, inserter in pairs(entity.surface.find_entities_filtered { type = "inserter", area = area }) do
            if inserter.pickup_target == entity or inserter.drop_target == entity then
                FilterHelper.add_items_inserter(inserter, items, true)
            end
        end
    end
end

---@param entity LuaEntity
---@param items table <string, SpritePath>
function FilterHelper.add_items_vehicle(entity, items)
    -- contents
    if contains({ "car", "cargo-wagon", "spider-vehicle" }, entity.type) then
        for _, inventory_type in pairs { defines.inventory.car_trunk, defines.inventory.cargo_wagon, defines.inventory.spider_trunk } do
            local inventory = entity.get_inventory(inventory_type)
            if inventory then
                for item, _ in pairs(inventory.get_contents()) do
                    items[item] = "item/" .. item
                end
                return
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
    FilterHelper.add_items_chest(entity, items)
    FilterHelper.add_items_vehicle(entity, items)
    return items
end

local function update_ui(player_global, check_items)
    if not player_global.entity then
        return
    end

    local interface_open = player_global.elements.main_frame and player_global.elements.main_frame.valid
    local update_interface = false

    if check_items or interface_open then
        local old_active_item_count = #player_global.active_items
        player_global.active_items = FilterHelper.get_active_items(player_global.entity)
        for _, item in pairs(player_global.active_items) do
            player_global.items[item] = "item/" .. item
        end
        if #player_global.active_items ~= old_active_item_count then
            update_interface = true
        end
    end
    if check_items then
        local old_item_count = table_size(player_global.items)
        FilterHelper.add_items(player_global.entity, player_global.items)
        if table_size(player_global.items) > old_item_count then
            update_interface = true
        end
    end
    if not interface_open and (next(player_global.items) or next(player_global.active_items)) then
        update_interface = true
    end

    if update_interface then
        if interface_open then
            build_sprite_buttons(player_global)
        else
            build_interface(player_global)
        end
    end
end

script.on_init(function()
    ---@type table<number, PlayerTable>
    global.players = {}
    for _, player in pairs(game.players) do
        init_global(player)
    end
end)

script.on_event(defines.events.on_player_created, function(event)
    init_global(game.get_player(event.player_index))
end)

script.on_event(defines.events.on_pre_player_removed, function(event)
    global.players[event.player_index] = nil
end)

-- EVENT on_gui_opened
script.on_event(defines.events.on_gui_opened, function(event)
    -- the entity that is opened
    local player_global = get_player_global(event.player_index)
    if player_global and event.entity then
        player_global.entity = event.entity
        update_ui(player_global, true)
    end
end)

--EVENT on_gui_closed
script.on_event(defines.events.on_gui_closed, function(event)
    local player_global = global.players[event.player_index]
    if player_global.elements.main_frame then
        player_global.elements.main_frame.destroy()
    end
    player_global.entity = nil
    if not player_global.needs_reopen then
        player_global.items = {}
        player_global.active_items = {}
    end
end)

--EVENT on_gui_click
script.on_event(defines.events.on_gui_click, function(event)
    local player_global = get_player_global(event.player_index)
    if not player_global then
        return
    end

    local entity = player_global.entity
    local clicked_item_name = event.element.tags.item_name
    local action = event.element.tags.action

    if entity and type(clicked_item_name) == "string" and (action == "fh_select_button" or action == "fh_deselect_button") then
        local updater = get_filter_updater(entity)
        if not updater then
            return
        end
        local command
        if event.button == defines.mouse_button_type.left then
            command = updater.add
        elseif event.button == defines.mouse_button_type.right then
            command = updater.remove
        elseif event.button == defines.mouse_button_type.middle then
            local player = player_global.player
            player.clear_cursor()
            player.cursor_ghost = clicked_item_name
            return
        else
            return
        end

        local need_refresh, fail_message = command(clicked_item_name, { alt = event.alt, control = event.control, shift = event.shift })
        if need_refresh then
            close_vanilla_ui_for_rebuild(player_global)
        end
        if fail_message then
            -- Play fail sound if filter slots are full or empty
            entity.surface.play_sound { path = "utility/cannot_build", volume_modifier = 1.0 }
            player_global.player.create_local_flying_text { text = fail_message, create_at_cursor = true }
        end
    end
end)

-- we need to close the ui on click and open it a tick later
-- to visually update the filter ui
-- if https://forums.factorio.com/viewtopic.php?f=7&t=106300 gets addressed,
-- this close/reopen GUI business can be removed
script.on_event(defines.events.on_tick, function(event)
    for _, player in pairs(game.players) do
        local player_global = get_player_global(player.index)
        if player_global then
            if player_global.needs_reopen and player_global.reopen_tick ~= event.tick then
                reopen_vanilla(player_global)
            end
            update_ui(player_global, event.tick % 60 == 0)
        end
    end
end)

-- TODO options for what things are considered. Chests, transport lines, etc
-- TODO recently used section
