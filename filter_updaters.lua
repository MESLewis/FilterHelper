local updaters = {}

updaters.one_filter_updater = {
    condition = function(entity)
        return entity.filter_slot_count == 1 and entity.type ~= "infinity-container"
    end,
    get_active_items = function(entity)
        return { entity.get_filter(1) }
    end,
    add = function(entity, clicked_item_name)
        entity.set_filter(1, clicked_item_name)
        return true
    end,
    remove = function(entity, clicked_item_name)
        entity.set_filter(1, nil)
        return true
    end,
}

updaters.many_filters_updater = {
    condition = function(entity)
        return entity.filter_slot_count > 1
    end,
    get_active_items = function(entity)
        local active_items = {}
        for i = 1, entity.filter_slot_count do
            table.insert(active_items, entity.get_filter(i))
        end
        return active_items
    end,
    add = function(entity, clicked_item_name)
        local found_slot
        for i = 1, entity.filter_slot_count do
            local found_filter = entity.get_filter(i)
            if found_filter then
                if found_filter == clicked_item_name then
                    return false, { "fh.filters-full" }
                end
            elseif not found_slot then
                found_slot = i
            end
        end
        if found_slot then
            entity.set_filter(found_slot, clicked_item_name)
            return true
        end
        return false, { "fh.filters-full" }
    end,
    remove = function(entity, clicked_item_name)
        for i = 1, entity.filter_slot_count do
            if entity.get_filter(i) == clicked_item_name then
                entity.set_filter(i, nil)
                return true
            end
        end
        return false, { "fh.filters-empty" }
    end,
}

updaters.splitter_filter_updater = {
    condition = function(entity)
        return entity.type == "splitter"
    end,
    get_active_items = function(entity)
        return entity.splitter_filter and { entity.splitter_filter.name } or {}
    end,
    add = function(entity, clicked_item_name)
        entity.splitter_filter = game.item_prototypes[clicked_item_name]
        if entity.splitter_output_priority == "none" then
            entity.splitter_output_priority = "left"
        end
        return true
    end,
    remove = function(entity, clicked_item_name)
        entity.splitter_filter = nil
        return true
    end,
}

return function(entity)
    for _, updater in pairs(updaters) do
        if updater.condition(entity) then
            return {
                get_active_items = function()
                    return updater.get_active_items(entity)
                end,
                add = function(clicked_item_name)
                    return updater.add(entity, clicked_item_name)
                end,
                remove = function(clicked_item_name)
                    return updater.remove(entity, clicked_item_name)
                end,
            }
        end
    end
end
