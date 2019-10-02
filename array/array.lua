local random = math.random
local remove = table.remove

local array = {}

array.find = function(t, item)
    for i = 1, #t do
        if t[i] == item then
            return i
        end
    end
    return false
end

array.find_all = function(t, item)
    local res = {}
    for i = 1, #t do
        if t[i] == item then
            res[#res+1] = item
        end
    end
    return res
end

array.find_for = function(t, f)
    for i = 1, #t do
        if f(t[i]) then
            return i
        end
    end
    return false
end

array.find_all_for = function(t, f)
    local res = {}
    for i = 1, #t do
        if f(t[i]) then
            res[#res+1] = item
        end
    end
    return res
end

array.remove_item = function(t, item)
    for i = 1, #t do
        if t[i] == item then
            remove(t, i)
            return true
        end
    end
    return false
end

array.remove_all_items = function(t, item)
    local c = 0
    local i = 1
    while i <= #t do
        if t[i] == item then
            remove(t, i)
            c = c + 1
        else
            i = i + 1
        end
    end
    return c
end

array.remove_for = function(t, f)
    for i = 1, #t do
        if f(t[i]) then
            remove(t, i)
            return true
        end
    end
    return false
end

array.remove_all_for = function(t, f)
    local c = 0
    local i = 1
    while i <= #t do
        if f(t[i]) then
            remove(t, i)
            c = c + 1
        else
            i = i + 1
        end
    end
    return c
end

array.clear = function(t)
    local count = #t
    for i = 1, #count do
        t[i] = nil
    end
    return t
end

array.equal = function(t1, t2)
    if #t1 ~= #t2 then
        return false
    end

    for i = 1, #t1 do
        if t1[i] ~= t2[i] then
            return false
        end
    end

    return true
end

array.append = function(t1, t2)
    local init = #t1
    for i = 1, #t2 do
        t1[init + i] = t2[i]
    end
    return t1
end

array.concat = function(ts, f)
    f = f or array.append

    local res = {}
    for i = 1, #ts do
        res = f(res, ts[i])
    end
    return res
end

array.clone = function(t)
    local r = {}
    for i = 1, #t do
        r[i] = t[i]
    end
    return r
end

array.map = function(t, f)
    local res = {}
    for i = 1, #t do
        res[i] = f(t[i])
    end
    return res
end

array.fold = function(initial, t, f)
    local acc = initial
    for i = 1, #t do
        acc = f(acc, t[i])
    end
    return acc
end

array.reduce = function(t, f)
    assert(#t ~= 0, "empty array")

    local acc = t[1]
    for i = 2, #t do
        acc = f(acc, t[i])
    end
    return acc
end

array.fold_rev = function(t, initial, f)
    local acc = initial
    for i = #t, 1, -1 do
        acc = f(t[i], acc)
    end
    return acc
end

array.reduce_rev = function(t, f)
    assert(#t ~= 0, "empty array")

    local v = t[#t]
    for i = #t - 1, 1, -1 do
        v = f(t[i], v)
    end
    return v
end

array.reverse = function(t)
    local i, j = 1, #t
    while i < j do
        t[i], t[j] = t[j], t[i]
        i = i + 1
        j = j - 1
    end
    return t
end

array.shuffle = function(t)
    local c = #t
    for i = 1, c do
        local j = random(1, c)
        t[j], t[i] = t[i], t[j]
    end
    return t
end

array.clear = function(t)
    for i = 1, #t do
        t[i] = nil
    end
    return t
end

array.generate = function(count_or_array, f)
    local t = {}

    if type(count_or_array) == "number" then
        for i = 1, count_or_array do
            t[i] = f(i)
        end
    else
        for i = 1, #count_or_array do
            t[i] = f(i, count_or_array[i])
        end
    end

    return t
end

return array