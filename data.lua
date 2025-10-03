local styles = data.raw["gui-style"].default

--TODO use styling mod
styles["fh_content_frame"] = {
    type = "frame_style",
    parent = "frame",
}

styles["fh_deep_frame"] = {
    type = "frame_style",
    parent = "slot_button_deep_frame",
    vertically_stretchable = "on",
    horizontally_stretchable = "on"
    -- top_margin = 16,
    -- left_margin = 8,
    -- right_margin = 8,
    -- bottom_margin = 4
}

-- in order to override the logic for an entity just add their name pointing to a remote interface in your own mod:
-- data.raw["mod-data"]["fh_add_items_drop_target_entity"].data["assembling-machine-3"] = {"interface", "function"}
data:extend{
    {
        type = "mod-data",
        name = "fh_add_items_drop_target_entity",
        data = {},
    },
    {
        type = "mod-data",
        name = "fh_add_items_pickup_target_entity",
        data = {},
    },
}
-- in your remote interface you will receive the entity and an empty array of items for your convenience,
-- the array of items should always be returned, items are allowed to be in several formats.
-- (see fh_util for details, most notably: item_name, {name = "name"} & prototypes)
-- note: your mod becomes responsible for ALL suggestions for that entity, like burn results and spoilage.
