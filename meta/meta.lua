local guard = require("meido.guard")
local meta = {}

local ungrowable_meta = {
    __metatable = "ungrowable",
    __newindex = function()
        error("this table is ungrowable", 2)
    end
}

meta.ungrowable = function(t)
    guard.table("t", t)
    local mt = getmetatable(t)
    if mt == "ungrowable" then
        return t
    elseif mt then
        error("table has another metatable")
    end
    return setmetatable(t, ungrowable_meta)
end

meta.readonly = function(t)
    guard.table("t", t)
    return setmetatable({}, {
        __metatable = "readonly",
        __index = function(t, k)
            return t[k]
        end,
        __newindex = function()
            error("this table is read-only", 2)
        end,
        __pairs = function() return pairs(t) end,
        __ipairs = function() return ipairs(t) end
    })
end

meta.writeonly = function(t, write)
    guard.table("t", t)
    guard.callable("write", write)
    return setmetatable({}, {
        __metatable = "writeonly",
        __index = function()
            error("this table is write-only", 2)
        end,
        __newindex = function(t, k, v)
            write(t, k, v)
        end
    })
end

return meta