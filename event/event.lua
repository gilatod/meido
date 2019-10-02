local remove = table.remove

local event = {}
event.__index = event 

event.trigger = function(t, name, ...)
    local e = t[name]
    if e then
        for handler, _ in next, e do
            handler(t, ...)
        end
    end
end

event.trigger_abortable = function(t, name, should_abort, ...)
    local e = t[name]
    if e then
        for handler, _ in next, e do
            local res = handler(t, ...)
            if should_abort(res) then
                return
            end
        end
        return true
    end
end

event.notify = function(t, name, f)
    local e = t[name]
    if not e then
        t[name] = {
            [f] = true
        }
    elseif type(e) == "table" then
        e[f] = true
    else
        error("invalid event")
    end
end

event.unnotify = function(t, name, f)
    local e = t[name]
    if type(e) == "table" then
        e[f] = nil
    end
end

return event