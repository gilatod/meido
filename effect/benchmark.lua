local folder = (...):gsub("%.[^%.]+$", "")
local effect = require(folder..".effect")

local socket = require "socket"

local yield = coroutine.yield
local resume = coroutine.resume

local max_count = 100000000

local function basic_case()
    local count = 0
    while count < max_count do
        count = count + 1
    end
end

local function coroutine_case()
    local co = coroutine.create(function()
        local count = 0
        while count < max_count do
            count = count + yield()
        end
    end)
    while resume(co, 1) do end
end

local function effect_case()
    local delay = effect.yield {"delay"}

    local delay_interpreter = {
        delay = function(resume, e, tag)
            return resume(e, 1)
        end
    }

    effect.interpret(
        {delay_interpreter},
        delay:accumulate(0, function(acc, v)
            return acc < max_count, acc + v
        end))
end

local function run(name, f)
    local t1 = socket.gettime()
    f()
    local t2 = socket.gettime()
    local delta = t2 - t1

    print(name..": "..delta)
    return delta
end

run("basic", basic_case)
local co_time = run("coroutine", coroutine_case)
local eff_time = run("effect", effect_case)

print("co / eff: "..(co_time / eff_time))