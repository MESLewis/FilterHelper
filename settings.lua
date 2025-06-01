data:extend {
    {
        type = "bool-setting",
        name = "fh-set-filter-on-inserter",
        setting_type = "runtime-global",
        default_value = true,
        order = "a",
    },
    {
        type = "string-setting",
        name = "fh-default-item-on-splitter",
        allow_blank = true,
        auto_trim = true,
        setting_type = "runtime-global",
        default_value = "deconstruction-planner",
        order = "b",
    },
}
