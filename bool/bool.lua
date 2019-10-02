local bool = {}

bool.all_truthy = function(...)
    for i = 1, select("#", ...) do
        if not select(i, ...) then
            return false
        end
    end
    return true
end

bool.all_falsy = function(...)
    for i = 1, select("#", ...) do
        if select(i, ...) then
            return false
        end
    end
    return true
end

bool.all_falsy = function(...)
    for i = 1, select("#", ...) do
        if select(i, ...) then
            return false
        end
    end
    return true
end

bool.xor = function(a, b)
    if a then
        return not b
    else
        return b
    end
end

bool.not_xor = function(a, b)
    if a then
        return b
    else
        return not b
    end
end

bool.to_bool = function(v)
    if v then
        return true
    else
        return false
    end
end

return bool