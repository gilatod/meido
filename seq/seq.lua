local guard = require("meido.guard")

local random = math.random
local char = string.char
local concat = table.concat
local unpack = table.unpack or unpack
local mininteger = math.mininteger
local maxinteger = math.maxinteger

local seq = {}
seq.__index = seq

setmetatable(seq, {
    __call = function(_, t)
        return seq.array_values(t)
    end
})

local function new(iter_gen)
    local t = {iter = iter_gen}
    return setmetatable(t, seq)
end

local function new_simple(iter)
    local t = {
        iter = function()
            return iter
        end
    }
    return setmetatable(t, seq)
end

-- methods

function seq:to_array(count)
    local res = {}

    if count then
        guard.number("count", count)

        local curr = 1
        for v in self:iter() do
            if curr > count then
                break
            end
            res[#res+1] = v
            curr = curr + 1
        end
    else
        for v in self:iter() do
            res[#res+1] = v
        end
    end

    return res
end

function seq:first()
    local iter = self:iter()
    return iter()
end

function seq:last()
    local res
    local iter = self:iter()

    while true do
        local new_res = iter()
        if new_res == nil then
            return res
        end
        res = new_res
    end
end

local function raw_fold(iter, acc, f)
    while true do
        local v = iter()
        if v == nil then
            return acc
        end
        acc = f(acc, v)
    end
end

function seq:fold(initial, f)
    guard.callable("f", f)

    local iter = self:iter()
    return raw_fold(iter, initial, f)
end

function seq:reduce(f)
    guard.callable("f", f)

    local iter = self:iter()
    local initial = iter()

    if initial == nil then
        error("empty sequence")
    end

    return raw_fold(iter, initial, f)
end

function seq:map(f)
    guard.callable("f", f)

    return new(function()
        local iter = self:iter()
        return function()
            local v = iter()
            if v == nil then return nil end
            return f(v)
        end
    end)
end

function seq:concat()
    return new(function()
        local iter = self:iter()
        local curr_seq_iter

        return function()
            local res

            while true do
                if curr_seq_iter then
                    res = curr_seq_iter()
                    if res ~= nil then break end
                end
                local curr_seq = iter()
                if curr_seq == nil then
                    return nil
                end
                curr_seq_iter = curr_seq:iter()
            end

            return res
        end
    end)
end

function seq:flat_map(f)
    guard.callable("f", f)

    return new(function()
        local iter = self:iter()
        local curr_seq_iter

        return function()
            local res

            while true do
                if curr_seq_iter then
                    res = curr_seq_iter()
                    if res ~= nil then break end
                end
                local curr_seq = iter()
                if curr_seq == nil then
                    return nil
                end
                curr_seq_iter = curr_seq:iter()
            end

            return f(res)
        end
    end)
end

function seq:take(count)
    guard.number("count", count)

    return new(function()
        local iter = self:iter()
        local curr = 1

        return function()
            if curr > count then
                return nil
            end
            curr = curr + 1
            return iter()
        end
    end)
end

function seq:drop(count)
    guard.number("count", count)

    return new(function()
        local iter = self:iter()

        for i = 1, count do
            if iter() == nil then
                break
            end
        end

        return iter
    end)
end

local function raw_scan(iter, acc, f)
    return function()
        local v = iter()
        if v == nil then return nil end
        acc = f(acc, v)
        return acc
    end
end

function seq:scan(initial, f)
    guard.callable("f", f)

    return new(function()
        local iter = self:iter()
        return raw_scan(iter, initial, f)
    end)
end

function seq:scan1(f)
    guard.callable("f", f)

    return new(function()
        local iter = self:iter()

        local initial = iter()
        if initial == nil then
            error("empty sequence")
        end

        return raw_scan(iter, initial, f)
    end)
end

seq.combine = function(seqs, combiner)
    guard.table("seqs", seqs)
    if #seqs < 2 then
        error("at least 2 sequences are required")
    end
    for i = 1, #seqs do
        guard.callable("sequence:iter", seqs[i].iter)
    end

    if combiner then
        guard.callable("combiner", combiner)
    else
        combiner = function(...)
            return {...}
        end
    end

    if #seqs == 2 then
        local seq1 = seqs[1]
        local seq2 = seqs[2]
        return new(function()
            local iter1 = seq1:iter()
            local iter2 = seq2:iter()
            return function()
                local res1 = iter1()
                if res1 == nil then return nil end
                local res2 = iter2()
                if res2 == nil then return nil end
                return combiner(res1, res2)
            end
        end)
    elseif #seqs == 3 then
        local seq1 = seqs[1]
        local seq2 = seqs[2]
        local seq3 = seqs[3]
        return new(function()
            local iter1 = seq1:iter()
            local iter2 = seq2:iter()
            local iter3 = seq3:iter()
            return function()
                local res1 = iter1()
                if res1 == nil then return nil end
                local res2 = iter2()
                if res2 == nil then return nil end
                local res3 = iter3()
                if res3 == nil then return nil end
                return combiner(res1, res2, res3)
            end
        end)
    else
        return new(function()
            local cache = {}
            local iters = {}
            for i = 1, #seqs do
                iters[i] = seqs[i]:iter()
            end
            return function()
                for i = 1, #iters do
                    local res = iters[i]()
                    if res == nil then
                        return nil
                    end
                    cache[i] = res
                end
                return combiner(unpack(cache))
            end
        end)
    end
end

-- creators

local none_seq = new(function()
    return function()
        return nil
    end
end)

seq.none = function()
    return none_seq
end

seq.single = function(v)
    return new(function()
        local produced
        return function()
            if produced then
                return nil
            end
            produced = true
            return v
        end
    end)
end

seq.replicate = function(v, count)
    if not count then
        local iter = function()
            return v
        end
        return new(function()
            return iter
        end)
    end

    return new(function()
        local curr = 1
        return function()
            if curr > count then
                return nil
            end
            curr = curr + 1
            return v
        end
    end)
end

seq.generate = function(f_or_initial, f)
    if f then
        guard.callable("f", f)

        local initial = f_or_initial
        return new(function()
            local v = initial
            return function()
                v = f(v)
                return v
            end
        end)
    else
        f = f_or_initial
        guard.callable("f", f)

        return new(function()
            return f
        end)
    end
end

seq.pairs = function(t)
    guard.table("t", t)

    return new(function()
        local finished, k, v
        return function()
            if finished then return nil end

            k, v = next(t, k)
            if not k then
                finished = true
                return nil
            end
            return {k, v}
        end
    end)
end

seq.keys = function(t)
    guard.table("t", t)

    return new(function()
        local finished, k
        return function()
            if finished then return nil end

            k = next(t, k)
            if not k then
                finished = true
                return nil
            end
            return k
        end
    end)
end

seq.values = function(t)
    guard.table("t", t)

    return new(function()
        local finished, k, v
        return function()
            if finished then return nil end

            k, v = next(t, k)
            if not k then
                finished = true
                return nil
            end
            return v
        end
    end)
end

seq.array_values = function(t)
    guard.table("t", t)

    return new(function()
        local i = 0
        return function()
            if i >= #t then
                return nil
            end
            i = i + 1
            return t[i]
        end
    end)
end

seq.indices = function()
    return new(function()
        local i = 0
        return function()
            i = i + 1
            return i
        end
    end)
end

seq.random = function(t)
    guard.table("t", t)

    local iter = function()
        return t[random(1, #t)]
    end

    return new(function() return iter end)
end

seq.range = function(from, to, step)
    guard.can_add("from", from)
    guard.can_lt("from", from)

    step = step or 1
    guard.can_lt("step", step)

    if step > 0 then
        return new(function()
            local curr = from
            return function()
                if curr > to then
                    return nil
                end

                local res = curr
                curr = curr + step
                return res
            end
        end)
    else
        return new(function()
            local curr = from
            return function()
                if curr < to then
                    return nil
                end

                local res = curr
                curr = curr + step
                return res
            end
        end)
    end
end

local simple_number_seq = new_simple(function()
    return random()
end)

seq.numbers = function(min, max)
    if not min and not max then
        return simple_number_seq
    end

    guard.number("min", min)
    guard.number("max", max)

    local diff = max - diff
    local iter = function()
        return min + random(diff) * diff
    end

    return new(function() return iter end)
end

local half_min = math.floor(mininteger / 2)
local half_max = math.floor(maxinteger / 2) - 1
local simple_integer_seq = new_simple(function()
    return random(half_min, half_max)
end)

seq.integers = function(min, max)
    if not min and not max then
        return simple_integer_seq
    end

    guard.integer("min", min)
    guard.integer("max", max)

    local iter = function()
        return random(min, max)
    end

    return new(function() return iter end)
end

local pos_integer_seq = new_simple(function()
    return random(1, maxinteger)
end)

local neg_integer_seq = new_simple(function()
    return random(mininteger, -1)
end)

seq.positive_integers = function()
    return pos_integer_seq
end

seq.negative_integers = function()
    return neg_integer_seq
end

seq.strings = function(
    min_len, max_len, chars_or_min_byte, max_byte)
    guard.number("min_len", min_len)
    guard.number("max_len", max_len)

    chars_or_min_byte = chars_or_min_byte or 33
    max_byte = max_byte or 126

    local iter

    local t = type(chars_or_min_byte) 
    local buffer = {}

    if t == "string" then
        local chars = chars_or_min_byte
        local chars_len = #chars
        iter = function()
            local len = random(min_len, max_len)
            for i = 1, len do
                local pos = random(1, chars_len)
                buffer[i] = chars:byte(pos)
            end
            for i = len + 1, #buffer do
                buffer[i] = nil
            end
            return char(unpack(buffer))
        end
    elseif t == "number" then
        local min_byte = chars_or_min_byte
        guard.number("max_byte", max_byte)

        iter = function()
            local len = random(min_len, max_len)
            for i = 1, len do
                buffer[i] = random(min_byte, max_byte)
            end
            for i = len + 1, #buffer do
                buffer[i] = nil
            end
            return char(unpack(buffer))
        end
    else
        error("argument #3 must be string or number")
    end

    return new(function() return iter end)
end

return seq