local guard = require("meido.guard")
local array = require("meido.array")

local remove_item = array.remove_item

local temp_cbs = setmetatable({}, {
    __mode = "v"
})

return function(t, name)
    guard.table("t", t)

    local cbs_name = name.."_cbs"

    t["on_"..name] = function(self, callback)
        guard.callable("callback", callback)
        local cbs = self[cbs_name]
        if not cbs then
            cbs = {}
            self[cbs_name] = cbs
        end
        cbs[#cbs+1] = callback
    end

    t["unlisten_"..name] = function(self, callback)
        local cbs = self[cbs_name]
        if not cbs then return end
        if remove_item(cbs, callback) then
            if #cbs == 0 then
                self[cbs_name] = nil
            end
        end
    end

    return function(sender, ...)
        local cbs = sender[cbs_name]
        if not cbs then return end

        local len = #cbs
        for i = 1, len do
            temp_cbs[i] = cbs[i]
        end

        for i = 1, len do
            temp_cbs[i](sender, ...)
        end
    end
end