require("util")

local fh_util = {}

function fh_util.make_item_id(name, quality)
    return name .. "|" .. quality
end

function fh_util.add_item_to_table(table, name, quality)
    if not name then
        return
    end
    local quality_name
    if quality then
        quality_name = type(quality) == "string" and quality or quality.name
    else
        quality_name = prototypes.quality.normal.name
    end
    local name_name = type(name) == "string" and name or name.name
    table[fh_util.make_item_id(name_name, quality_name)] = { name = name_name, quality = quality_name }
    end

function fh_util.is_same_item(item1, item2)
    return item1 and item2 and item1.name == item2.name and item1.quality == item2.quality
end

return fh_util
