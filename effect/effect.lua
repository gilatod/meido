local guard = require("meido.guard")
local meta = require("meido.meta")

local unpack = table.unpack

local effect = {}
effect.__index = effect
effect.__newindex = function()
    error("effect object is read-only")
end

local DELAYED = meta.ungrowable {}
effect.DELAYED = DELAYED

local CLOSURE_TAG = meta.ungrowable {}
local SPLIT = meta.ungrowable {}

local function yield(...)
    return setmetatable({...}, effect)
end

local function closure(f)
    return setmetatable({CLOSURE_TAG, f}, effect)
end

effect.yield = yield
effect.closure = closure

effect.split = function(...)
    return yield {SPLIT, ...}
end

local function raw_interpret(interpreters, resumer_cache, stack, e)
    local resume

    local function apply(e, from, v)
        local to = #e - 1
        for i = from, to do
            local entry = e[i]
            if type(entry) == "table" then
                local top = #stack
                stack[top+1] = e -- effect table
                stack[top+2] = i -- index
                e = entry
                to = #entry - 1
                i = 2
            else
                v = entry(v)
                if getmetatable(v) == effect then
                    -- 'execute' expanded manually
                    local tag = v[1]
                    if tag == CLOSURE_TAG then
                        return apply(v, 2, nil)
                    end
                    local tag_head = tag[1]
                    local resumer = resumer_cache[tag_head]
                    if not resumer then
                        for i = 1, #interpreters do
                            resumer = interpreters[i][tag_head]
                            if resumer then break end
                        end
                        if resumer then
                            resumer_cache[tag_head] = resumer
                        else
                            error("unknown yield: "..tostring(tag_head))
                        end
                    end
                    
                    local top = #stack
                    stack[top+1] = e -- effect table
                    stack[top+2] = i -- index
                    return resumer(resume, v, tag)
                end
            end
        end

        v = e[#e](v)
        if getmetatable(v) == effect then
            -- 'execute' expanded manually
            local tag = v[1]
            if tag == CLOSURE_TAG then
                return apply(v, 2, nil)
            end
            local tag_head = tag[1]
            local resumer = resumer_cache[tag_head]
            if not resumer then
                for i = 1, #interpreters do
                    resumer = interpreters[i][tag_head]
                    if resumer then break end
                end
                if resumer then
                    resumer_cache[tag_head] = resumer
                else
                    error("unknown yield: "..tostring(tag_head))
                end
            end
            return resumer(resume, v, tag)
        else
            local top = #stack
            if top > 0 then
                local eff_i = top - 1
                local e = stack[eff_i] -- effect table
                local i = stack[top]   -- index
                stack[eff_i] = nil
                stack[top] = nil
                return apply(e, i + 1, v)
            else
                return v
            end
        end
    end

    resume = function(e, yield_res)
        if #e == 1 then
            return yield_res
        else
            return apply(e, 2, yield_res)
        end
    end

    -- execute
    local tag = e[1]
    if tag == CLOSURE_TAG then
        return apply(e, 2, nil)
    end
    local tag_head = tag[1]
    local resumer = resumer_cache[tag_head]
    if not resumer then
        for i = 1, #interpreters do
            resumer = interpreters[i][tag_head]
            if resumer then break end
        end
        if resumer then
            resumer_cache[tag_head] = resumer
        else
            error("unknown yield: "..tostring(tag_head))
        end
    end

    return resumer(resume, e, tag)
end

effect.interpret = function(interpreters, e)
    if getmetatable(e) ~= effect then
        return e
    end

    guard.table("interpreters", interpreters)
    for i = 1, #interpreters do
        guard.table("interpreter", interpreters[i])
    end

    local resumer_cache
    resumer_cache = {
        [SPLIT] = function(resume, e, tag)
            local resumed, result
            local function do_resume(e, yield_res)
                if resumed then return end
                resumed = true
                result = resume(e, yield_res)
                return result
            end
            for i = 2, #tag do
                local creator = tag[i]
                guard.callable("child effect creator", creator)

                local child_e = creator(do_resume, e)

                if getmetatable(child_e) == effect then
                    local stack = {}
                    raw_interpret(
                        interpreters, resumer_cache, stack, child_e)
                    if resumed then
                        return result
                    end
                end
            end
            return DELAYED
        end
    }

    local stack = {}
    return raw_interpret(
        interpreters, resumer_cache, stack, e)
end

local function map(e, f)
    if getmetatable(e) == effect then
        local tag = e[1]
        if #e > 1 then
            return yield(tag, e, f)
        else
            return yield(tag, f)
        end
    else
        return f(fst)
    end
end

effect.map = function(e, f)
    guard.callable("f", f)
    return map(e, f)
end

effect.append = function(e1, e2)
    return map(e1, function() return e2 end)
end

effect.chain = function(e, ...)
    local len = select("#", ...)
    if len == 0 then
        error("no function provided")
    end
    for i = 1, len do
        if getmetatable(e) == effect then
            local tag = e[1]
            if #e > 1 then
                return yield(tag, e, select(i, ...))
            else
                return yield(tag, select(i, ...))
            end
        else
            e = select(i, ...)(e)
        end
    end
    return e
end

effect.forever = function(e)
    local continue
    local function run()
        return continue
    end
    continue = map(e, run)
    return continue
end

effect.replicate = function(e, count)
    guard.positive("count", count)

    return map(e, function(v)
        local res = {v}
        local i = 1
        local continue

        local function run()
            if i > count then
                return res
            end
            res[i] = v
            i = i + 1
            return continue
        end

        continue = map(e, run)
        return continue
    end)
end

effect.replicate_until = function(e, predicate)
    guard.callable("predicate", predicate)

    return map(e, function(v)
        local res = {v}
        local i = 1
        local continue

        local function run(v)
            if predicate(v) then
                return res
            end
            res[i] = v
            i = i + 1
            return continue
        end

        continue = map(e, run)
        return continue
    end)
end

effect.loop = function(e, count)
    guard.positive("count", count)

    return map(e, function(v)
        local i = 1
        local continue

        local function run()
            if i > count then return end
            i = i + 1
            return continue
        end

        continue = map(e, run)
        return continue
    end)
end

effect.loop_until = function(e, predicate)
    guard.callable("predicate", predicate)

    local continue

    local function run(v)
        if predicate(v) then return v end
        return continue
    end

    continue = map(e, run)
    return continue
end

effect.accumulate = function(e, initial, f)
    guard.callable("f", f)

    return map(e, function(v)
        local ctn, acc = f(initial, v)
        if not ctn then return acc end

        local continue

        local function run(v)
            ctn, acc = f(acc, v)
            if ctn then
                return continue
            else
                return acc
            end
        end

        continue = map(e, run)
        return continue
    end)
end

effect.apply = function(tf, ...)
    local ts = {...}
    return map(tf, function(f)
        local collect
        local len = #ts
        local args = {}
        local i = 1

        local function continue(v)
            args[i] = v
            i = i + 1
            return collect()
        end

        collect = function()
            while i <= len do
                local e = ts[i]
                if getmetatable(e) == effect then
                    local tag = e[1]
                    if #e > 1 then
                        return yield(tag, e, continue)
                    else
                        return yield(tag, continue)
                    end
                else
                    args[i] = e
                end
                i = i + 1
            end
            return f(unpack(args))
        end
        return collect(1)
    end)
end

local function sequence_iter(gen, param, state)
    guard.callable("gen", gen)

    return closure(function()
        local iterate
        local res = {}
        local state

        local function continue(v)
            res[#res+1] = v
            return iterate()
        end

        iterate = function()
            local e
            while true do
                state, e = gen(param, state)
                if not state then break end
                if getmetatable(e) == effect then
                    local tag = e[1]
                    if #e > 1 then
                        return yield(tag, e, continue)
                    else
                        return yield(tag, continue)
                    end
                else
                    res[#res+1] = e
                end
            end
            return res
        end

        return iterate()
    end)
end

effect.sequence_iter = sequence_iter
effect.sequence = function(iterable)
    return sequence_iter(pairs(iterable))
end

local function simple_sequence_iter(gen, param, state)
    guard.callable("gen", gen)

    return closure(function()
        local state
        local function iterate()
            local e
            while true do
                state, e = gen(param, state)
                if not state then break end
                if getmetatable(e) == effect then
                    local tag = e[1]
                    if #e > 1 then
                        return yield(tag, e, iterate)
                    else
                        return yield(tag, iterate)
                    end
                end
            end
        end
        return iterate()
    end)
end

effect.simple_sequence_iter = simple_sequence_iter
effect.simple_sequence = function(iterable)
    return simple_sequence_iter(pairs(iterable))
end

local function traverse_iter(gen, param, state, f)
    guard.callable("gen", gen)
    guard.callable("f", f)

    return closure(function()
        local iterate
        local state = state
        local res = {}

        local function continue(v)
            res[#res+1] = v
            return iterate()
        end

        iterate = function()
            local e
            while true do
                ::skip::
                state, e = gen(param, state)
                if not state then break end
                if getmetatable(e) ~= effect then
                    e = f(e)
                    if getmetatable(e) ~= effect then
                        res[#res+1] = e
                        goto skip
                    end
                end

                local tag = e[1]
                if #e > 1 then
                    return yield(tag, e, f, continue)
                else
                    return yield(tag, f, continue)
                end
            end
            return res
        end
        return iterate()
    end)
end

effect.traverse_iter = traverse_iter
effect.traverse = function(iterable, f)
    local gen, param, state = pairs(iterable)
    return traverse_iter(gen, param, state, f)
end

local function simple_traverse_iter(gen, param, state, f)
    guard.callable("gen", gen)
    guard.callable("f", f)

    return closure(function()
        local state = state

        local function iterate()
            local e
            while true do
                ::skip::
                state, e = gen(param, state)
                if not state then break end
                if getmetatable(e) ~= effect then
                    e = f(e)
                    if getmetatable(e) ~= effect then
                        goto skip
                    end
                end

                local tag = e[1]
                if #e > 1 then
                    return yield(tag, e, f, iterate)
                else
                    return yield(tag, f, iterate)
                end
            end
        end
        return iterate()
    end)
end

effect.simple_traverse_iter = simple_traverse_iter
effect.simple_traverse = function(iterable, f)
    local gen, param, state = pairs(iterable)
    return traverse_iter(gen, param, state, f)
end

local function fold_iter(initial, gen, param, state, f)
    guard.callable("gen", gen)
    guard.callable("f", f)

    return closure(function()
        local iterate
        local acc = initial
        local state = state

        local function accumulator(v)
            return f(acc, v)
        end

        local function continue(new_acc)
            acc = new_acc
            return iterate()
        end

        iterate = function()
            local e
            while true do
                state, e = gen(param, state)
                if not state then break end
                if getmetatable(e) == effect then
                    local tag = e[1]
                    if #e > 1 then
                        return yield(tag, e, accumulator, continue)
                    else
                        return yield(tag, accumulator, continue)
                    end
                else
                    local e_ = f(acc, e)
                    if getmetatable(e_) == effect then
                        local tag = e_[1]
                        if #e_ > 1 then
                            return yield(tag, e_, continue)
                        else
                            return yield(tag, continue)
                        end
                    else
                        acc = e_
                    end
                end
            end
            return acc
        end
        return iterate()
    end)
end

effect.fold_iter = fold_iter
effect.fold = function(initial, iterable, f)
    local gen, param, state = pairs(iterable)
    return fold_iter(initial, gen, param, state, f)
end

local function reduce_iter(gen, param, state, f)
    local state, initial = gen(param, state)
    assert(state ~= nil, "empty iterator")
    return fold_iter(initial, gen, param, state, f)
end

effect.reduce_iter = reduce_iter
effect.reduce = function(iterable, f)
    local gen, param, state = pairs(iterable)
    return reduce_iter(gen, param, state, f)
end

local function fold_until_iter(initial, gen, param, state, predicate, f)
    guard.callable("gen", gen)
    guard.callable("predicate", predicate)
    guard.callable("f", f)

    return closure(function()
        local iterate
        local acc = initial
        local state = state

        local function accumulator(v)
            return f(acc, v)
        end

        local function continue(new_acc)
            acc = new_acc
            return iterate()
        end

        iterate = function()
            local e
            while true do
                if predicate(acc) then
                    return acc
                end
                state, e = gen(param, state)
                if not state then break end
                if getmetatable(e) == effect then
                    local tag = e[1]
                    if #e > 1 then
                        return yield(tag, e, accumulator, continue)
                    else
                        return yield(tag, accumulator, continue)
                    end
                else
                    local e_ = f(acc, e)
                    if getmetatable(e_) == effect then
                        local tag = e_[1]
                        if #e_ > 1 then
                            return yield(tag, e_, continue)
                        else
                            return yield(tag, continue)
                        end
                    else
                        acc = e_
                    end
                end
            end
            return acc
        end
        return iterate()
    end)
end

effect.fold_until_iter = fold_until_iter
effect.fold_until = function(initial, iterable, predicate, f)
    local gen, param, state = pairs(iterable)
    return fold_until_iter(initial, gen, param, state, f)
end

local function reduce_until_iter(gen, param, state, predicate, f)
    local state, initial = gen(param, state)
    assert(state ~= nil, "empty iterator")
    return fold_until_iter(initial, gen, param, state, predicate, f)
end

effect.reduce_until_iter = reduce_until_iter
effect.reduce_until = function(iterable, predicate, f)
    local gen, param, state = pairs(iterable)
    return reduce_until_iter(gen, param, state, predicate, f)
end

-- operators

function effect:__unm()
    return map(self, function(v)
        return -v
    end)
end

local function binary_op(name, f)
    effect[name] = function(self, other)
        if getmetatable(other) == effect then
            return map(self, function(a)
                return map(other, function(b)
                    return f(a, b)
                end)
            end)
        else
            return map(self, function(v)
                return f(v, other)
            end)
        end
    end
end

binary_op("__add", function(a, b) return a + b end)
binary_op("__sub", function(a, b) return a - b end)
binary_op("__mul", function(a, b) return a * b end)
binary_op("__div", function(a, b) return a / b end)
binary_op("__pow", function(a, b) return a ^ b end)
binary_op("__concat", function(a, b) return a .. b end)

return effect