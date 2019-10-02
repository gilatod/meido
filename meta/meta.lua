local guard = require("meido.guard")
local meta = {}

local readonly_meta = {
    __metatable = "readonly",
    __newindex = function()
        error("this table is read-only", 2)
    end
}

meta.readonly = function(t)
    guard.table("t", t)
    if getmetatable(t) == "readonly" then
        return t
    end
    return setmetatable(t, readonly_meta)
end

meta.accessor = function(t)
    guard.table("t", t)
    return setmetatable({}, {
        __metatable = "readonly",
        __index = function(t, k)
            return t[k]
        end,
        __newindex = function()
            error("this table is read-only", 2)
        end
    })
end

meta.writeonly = function(t, on_write)
    guard.callable("on_write", on_write)
    return setmetatable(t, {
        __metatable = "writeonly",
        __index = function()
            error("this table is write-only", 2)
        end,
        __newindex = function(t, k, v)
            on_write(t, k, v)
        end
    })
end

return meta