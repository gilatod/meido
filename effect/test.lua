local folder = (...):gsub("%.[^%.]+$", "")
local effect = require(folder..".effect")

local test_command_1 = effect.yield {"test_command_1"}
local test_command_2 = effect.yield {"test_command_2"}

local test_command_3 = effect.yield {"test_command_3"}
local test_command_4 = effect.yield {"test_command_4"}

local test_interpreter_1 = {
    test_command_1 = function(resume, e, tag)
        return resume(e, "1")
    end,
    test_command_2 = function(resume, e, tag)
        return resume(e, "2")
    end
}

local test_interpreter_2 = {
    test_command_3 = function(resume, e, tag)
        return resume(e, "3")
    end,
    test_command_4 = function(resume, e, tag)
        return resume(e, "4")
    end
}

local function interpret(e)
    return effect.interpret(
        {test_interpreter_1, test_interpreter_2}, e)
end

local test = test_command_1:map(
    function(v) return v.."_pass" end)
assert(interpret(test) == "1_pass")

local test = test_command_1:chain(
    function(v) return v.."_pass" end,
    function(v)
        return test_command_2:map(
            function(v_) return v.."_"..v_ end)
    end,
    function(v)
        return test_command_3:map(
            function(v_) return v.."_"..v_ end)
    end)
assert(interpret(test) == "1_pass_2_3")

local test = effect.replicate(test_command_3, 3)
assert(table.concat(interpret(test)) == "333")

local test = effect.apply(
    test_command_4:map(function(v)
        return function(a, b)
            return a..b..v
        end
    end),
    test_command_1,
    test_command_2)
assert(interpret(test) == "124")

local i = 1
local test = test_command_1:replicate_until(function()
    if i > 4 then
        return true
    end
    i = i + 1
    return false
end)
assert(table.concat(interpret(test)) == "1111")

local test = effect.split(
    function(resume, e)
        return test_command_1:map(function(v)
            if v == "2" then
                return resume(e, "1 OK")
            end
        end)
    end,
    function(resume, e)
        return test_command_2:map(function(v)
            if v == "2" then
                return resume(e, "2 OK")
            end
        end)
    end):map(function(v)
        return v.."."
    end)
assert(interpret(test) == "2 OK.")

local test = test_command_4:accumulate("", function(acc, v)
    acc = acc..v
    return #acc < 4, acc
end)
assert(interpret(test) == "4444")

local commands = {
    test_command_1,
    test_command_2,
    test_command_3,
    test_command_4
}

local test = effect.sequence(commands)
assert(table.concat(interpret(test)) == "1234")

local test = effect.traverse(
    commands,
    function(v)
        return test_command_1:map(function(s)
            return s..v
        end)
    end)
assert(table.concat(interpret(test)) == "11121314")

local test = effect.fold(
    "0", commands,
    function(acc, v)
        return acc..","..v
    end)
assert(interpret(test) == "0,1,2,3,4")

local test = effect.reduce(
    commands,
    function(acc, v)
        return acc..","..v
    end)
assert(interpret(test) == "1,2,3,4")

local test =
    test_command_1..test_command_2..
    test_command_3..test_command_4
assert(interpret(test) == "1234")

print("[effect] all test passed")