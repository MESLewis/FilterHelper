local styles = data.raw["gui-style"].default

--TODO use styling mod
styles["fh_content_frame"] = {
    type = "frame_style",
    parent = "inside_shallow_frame_with_padding",
    vertically_stretchable = "on"
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