local object = require("meido.object")

local math_type = math.type

local guard = {}

local __error = error
local function error(...)
    print(debug.traceback())
    __error(...)
end

local function inspect(v)
    if not guard.inspect_enabled then
        return ""
    end
    return ", got "..object.show(v)
end

guard.set_inspect_enabled = function(enabled)
    guard.inspect_enabled = enabled
end

guard.is_inspect_enabled = function()
    return guard.inspect_enabled
end

-- relational guards

guard.equal = function(name, v, other)
    if v ~= other then
        error(name.." is expected to be "..
            tostring(other)..inspect(v))
    end
end

guard.non_equal = function(name, v, other)
    if v == other then
        error(name.." cannot be "..
            tostring(other))
    end
end

guard.greater = function(name, v, comparand)
    guard.non_nil(name, v)
    if v <= comparand then
        error(name.." must be greater than "..
            comparand..inspect(v))
    end
end

guard.greater_or_equal = function(name, v, comparand)
    guard.non_nil(name, v)
    if v < comparand then
        error(name.." must be greater or equal to "..
            comparand..inspect(v))
    end
end

guard.less = function(name, v, comparand)
    guard.non_nil(name, v)
    if v >= comparand then
        error(name.." must be less than "..
            comparand..inspect(v))
    end
end

guard.less_or_equal = function(name, v, comparand)
    guard.non_nil(name, v)
    if v > comparand then
        error(name.." must be less or equal to "..
            comparand..inspect(v))
    end
end

-- type guards

local function create_type_guard(expected_type)
    return function(name, v)
        local t = type(v)
        if t ~= expected_type then
            error(name.." must be "..expected_type..inspect(v))
        end
    end
end

guard.string  = create_type_guard("string")
guard.number  = create_type_guard("number")
guard.func    = create_type_guard("function")
guard.table   = create_type_guard("table")
guard.boolean = create_type_guard("boolean")

-- nil guards

guard.is_nil = function(name, v)
    if v ~= nil then
        error(name.." must be nil"..inspect(v))
    end
end

guard.non_nil = function(name, v)
    if v == nil then
        error(name.." cannot be nil")
    end
end

-- string guards

guard.empty_string = function(name, v)
    guard.string(name, v)
    if v ~= "" then
        error(name.." must be empty string"..inspect(v))
    end
end

guard.nonempty_string = function(name, v)
    guard.string(name, v)
    if v == "" then
        error(name.." must be non-empty string")
    end
end

-- number guards

guard.integer = function(name, v)
    if math_type(v) ~= "integer" then
        error(name.." must be integer"..inspect(v))
    end
end

guard.float = function(name, v)
    if math_type(v) ~= "float" then
        error(name.." must be float"..inspect(v))
    end
end

guard.zero = function(name, v)
    guard.number(name, v)
    if v ~= 0 then
        error(name.." must be zero"..inspect(v))
    end
end

guard.non_zero = function(name, v)
    guard.number(name, v)
    if v == 0 then
        error(name.." must be non-zero")
    end
end

guard.finite = function(name, v)
    guard.number(name, v)
    if v == math.huge then
        error(name.." must be finite number")
    end
end

guard.positive = function(name, v)
    guard.number(name, v)
    if v <= 0 then
        error(name.." must be positive number"..inspect(v))
    end
end

guard.zero_or_positive = function(name, v)
    guard.number(name, v)
    if v < 0 then
        error(name.." must be zero or positive"..inspect(v))
    end
end

guard.negative = function(name, v)
    guard.number(name, v)
    if v >= 0 then
        error(name.." must be negative number"..inspect(v))
    end
end

guard.zero_or_negative = function(name, v)
    guard.number(name, v)
    if v > 0 then
        error(name.." must be zero or negative"..inspect(v))
    end
end

guard.odd = function(name, v)
    guard.number(name, v)
    if v % 2 == 0 then
        error(name.." must be odd number"..inspect(v))
    end
end

guard.even = function(name, v)
    guard.number(name, v)
    if v % 2 == 1 then
        error(name.." must be even number"..inspect(v))
    end
end

-- table guards

local function create_table_guard(raw_type, metamethod, info)
    return function(name, v)
        local t = type(v)

        if t == raw_type then
            return
        elseif t == "table" then
            local meta = getmetatable(v)
            if meta and type(meta[metamethod]) == "function" then
                return
            end
        end

        error(name.." must "..info..inspect(v))
    end
end

guard.callable   = create_table_guard("function", "__call", "be callable")
guard.concatable = create_table_guard("string", "__concat", "be concatable")
guard.can_add    = create_table_guard("number", "__add", "support addition")
guard.can_sub    = create_table_guard("number", "__sub", "support subtraction")
guard.can_mul    = create_table_guard("number", "__mul", "support multiplication")
guard.can_div    = create_table_guard("number", "__div", "support division")
guard.can_mod    = create_table_guard("number", "__mod", "support modulus")
guard.can_unm    = create_table_guard("number", "__unm", "support negation")
guard.can_pow    = create_table_guard("number", "__pow", "support exponentiation")
guard.can_lt     = create_table_guard("number", "__lt", "support less-than operator")
guard.can_le     = create_table_guard("number", "__le", "support less-or-equal operator")
guard.can_idiv   = create_table_guard("number", "__idiv", "support floor division operator")
guard.can_band   = create_table_guard("number", "__band", "support bitwise AND operator")
guard.can_bor    = create_table_guard("number", "__bor", "support bitwise OR operator")
guard.can_bxor   = create_table_guard("number", "__bxor", "support bitwise XOR operator")
guard.can_bnot   = create_table_guard("number", "__bnot", "support bitwise NOT operator")
guard.can_shl    = create_table_guard("number", "__shl", "support bitwise left shift operator")
guard.can_shr    = create_table_guard("number", "__shl", "support bitwise right shift operator")

-- boolean guards

guard.truthy = function(name, v)
    if not v then
        error(name.." must be truthy"..inspect(v))
    end
end

guard.falsy = function(name, v)
    if v then
        error(name.." must be falsy"..inspect(v))
    end
end

guard.is_true = function(name, v)
    if v ~= true then
        error(name.." must be true"..inspect(v))
    end
end

guard.is_false = function(name, v)
    if v ~= false then
        error(name.." must be false"..inspect(v))
    end
end

-- error guards

guard.no_error = function(func, ...)
    local success, err = pcall(func, ...)
    if not success then
        error("unexpected error: "..err)
    end
end

guard.match_error = function(pattern, func, ...)
    local success, err = pcall(func, ...)
    if success then
        error("no error")
    end
    assert(string.match(err, pattern), "error does not match: "..err)
end

return guard