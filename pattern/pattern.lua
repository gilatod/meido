local guard = require("meido.guard")
local meta = require("meido.meta")
local object = require("meido.object")
local array = require("meido.array")

local clear = array.clear
local readonly = meta.readonly
local format = string.format
local concat = table.concat
local insert = table.insert
local math_type = math.type

if math_type == nil then
    math_type = function(n)
        if type(n) ~= "number" then
            return nil
        end
        local _, f = math.modf(n)
        return f == 0
            and "integer" or "float"
    end
end

local EMPTY_TABLE = readonly {}
local ID_FUNC = function(...) return ... end

local NO_DEFAULT = readonly {}
local FAILED_PATTERN_INDEX = readonly {}

local pattern = setmetatable({}, {
    __call = function(self, category, default, desc_func, match_func)
        guard.nonempty_string("category", category)
        guard.callable("desc_func", desc_func)
        guard.callable("match_func", match_func)

        local t = {
            category = category,
            default = default,
            desc_func = desc_func,
            match_func = match_func
        }

        if default == NO_DEFAULT then
            -- override pattern:get_default
            function t:get_default()
                error("no default")
            end
        elseif not match_func(default) then
            error("invalid default value")
        end

        return setmetatable(t, self)
    end
})
pattern.__index = pattern

function pattern:has_default()
    return self.default ~= NO_DEFAULT
end

function pattern:get_default()
    return self.default
end

function pattern:__tostring()
    return self.desc_func()
end

function pattern:get_description()
    return self.desc_func()
end

function pattern:match(value, collection, stack)
    if stack then
        stack[#stack+1] = {self, value}
        local res = self.match_func(value, collection, stack)
        if res then stack[#stack] = nil end
        return res
    else
        return self.match_func(value, collection)
    end
end

-- basic patterns

local function basic_pattern(type_name, default)
    return pattern("basic", default,
        function() return type_name end,
        function(v) return type(v) == type_name end)
end

pattern.NIL      = basic_pattern("nil", nil)
pattern.STRING   = basic_pattern("string", "")
pattern.NUMBER   = basic_pattern("number", 0)
pattern.TABLE    = basic_pattern("table", EMPTY_TABLE)
pattern.FUNCTION = basic_pattern("function", ID_FUNC)
pattern.BOOLEAN  = basic_pattern("boolean", false)

pattern.ANY = pattern("basic", nil,
    function() return "any" end,
    function(v) return true end)

pattern.VOID = pattern("basic", NO_DEFAULT,
    function() return "void" end,
    function(v) return false end)

pattern.NON_NIL = pattern("basic", false,
    function() return "non_nil" end,
    function(v) return v ~= nil end)

pattern.TRUTHY = pattern("basic", true,
    function() return "truthy" end,
    function(v) return v end)

pattern.FALSY = pattern("basic", false,
    function() return "falsy" end,
    function(v) return not v end)

pattern.value = function(value)
    local pat = pattern("value", value,
        function()
            if type(value) == "string" then
                return format("\"%s\"", value)
            else
                return tostring(value)
            end
        end,
        function(v)
            return v == value
        end)

    function pat:get_value()
        return value
    end

    return pat
end

pattern.collect = function(index)
    local pat = pattern("collect", NO_DEFAULT,
        function() return "@"..tostring(index) end,
        function(v, c)
            if type(c) == "table" then
                c[index] = v
            end
            return true
        end)
    
    function pat:get_index()
        return index
    end

    return pat
end

-- combinators

pattern.no_default = function(pat)
    assert(getmetatable(pat) == pattern,
        "invalid pattern")

    local new_pat = pattern("no_default", NO_DEFAULT,
        function()
            return format("no_default[%s]",
                pat:get_description())
        end,
        function(v, c, s) return pat:match(v, c, s) end)
    
    function new_pat:get_raw_pattern()
        return pat
    end

    return new_pat
end

pattern.named = function(name, pat)
    guard.nonempty_string("name", name)
    assert(getmetatable(pat) == pattern,
        "invalid pattern")
    
    local new_pat = pattern("named", pat.default,
        function() return name end,
        function(v, c, s) return pat:match(v, c, s) end)
    
    function new_pat:get_raw_pattern()
        return pat
    end

    return new_pat
end

pattern.union = function(...)
    local subpats = readonly {...}
    if #subpats == 0 then
        error("no subpattern provided")
    end

    for i = 1, #subpats do
        local subpat = subpats[i]
        if getmetatable(subpat) ~= pattern then
            error("invalid subpattern at index #"..i)
        end
    end

    local default = NO_DEFAULT

    for i = 1, #subpats do
        local subpat = subpats[i]
        if subpat:has_default() then
            default = subpat:get_default()
            break
        end
    end

    local pat = pattern(
        "union", default,
        function()
            local res = {}
            for i = 1, #subpats do
                res[#res+1] = subpats[i]:get_description()
                res[#res+1] = " | "
            end
            res[#res] = nil
            return concat(res)
        end,
        function(v, c, s)
            for i = 1, #subpats do
                if subpats[i]:match(v, c, s) then
                    return true
                end
            end
            return false
        end)
    
    function pat:get_subpatterns()
        return subpats
    end

    return pat
end

pattern.intersect = function(...)
    local subpats = readonly {...}
    if #subpats == 0 then
        error("no subpattern provided")
    end

    for i = 1, #subpats do
        local subpat = subpats[i]
        if getmetatable(subpat) ~= pattern then
            error("invalid subpattern at index #"..i)
        end
    end

    local default
    
    for i = 1, #subpats do
        default = subpats[i].default
        if default == NO_DEFAULT then
            goto skip
        end
        for j = 1, #subpats do
            if i ~= j
                and not subpats[j]:match(default) then
                default = NO_DEFAULT
                break
            end
        end
        ::skip::
    end
    
    local pat = pattern(
        "intersect", default,
        function()
            local res = {}
            for i = 1, #subpats do
                res[#res+1] = subpats[i]:get_description()
                res[#res+1] = " & "
            end
            res[#res] = nil
            return concat(res)
        end,
        function(v, c, s)
            for i = 1, #subpats do
                if not subpats[i]:match(v, c, s) then
                    return false
                end
            end
            return true
        end)
    
    function pat:get_subpatterns()
        return subpats
    end

    return pat
end

pattern.recurse = function(name, pattern_creator)
    guard.nonempty_string("name", name)
    guard.callable("pattern_creator", pattern_creator)

    local pat

    local hook_pat = pattern("recursion", NO_DEFAULT,
        function() return name end,
        function(v, c, s)
            return pat:match(v, c, s)
        end)

    pat = pattern_creator(hook_pat)
    assert(getmetatable(pat) == pattern,
        "invalid pattern creator")

    return pattern("recurse", pat.default,
        function()
            return format("%s : %s",
                name, pat:get_description())
        end,
        function(v, c, s)
            return pat:match(v, c, s)
        end)
end

-- nilable patterns

local function nilable_pattern(type_name)
    return pattern("nilable", nil,
        function() return type_name.."?" end,
        function(v) return v == nil or type(v) == type_name end)
end

pattern.STRING_OR_NIL   = nilable_pattern("string")
pattern.NUMBER_OR_NIL   = nilable_pattern("number")
pattern.TABLE_OR_NIL    = nilable_pattern("table")
pattern.FUNCTION_OR_NIL = nilable_pattern("function")
pattern.BOOLEAN_OR_NIL  = nilable_pattern("boolean")

-- numeric patterns

pattern.NONNEGATIVE_NUMBER = pattern("numeric", 0,
    function() return "nonnegative_number" end,
    function(v) return type(v) == "number" and v >= 0 end)

pattern.NONPOSITIVE_NUMBER = pattern("numeric", 0,
    function() return "nonpositive_number" end,
    function(v) return type(v) == "number" and v <= 0 end)

pattern.NORMALIZED_NUMBER = pattern("numeric", 0,
    function() return "normalized_number" end,
    function(v) return type(v) == "number" and v >= 0 and v <= 1 end)

pattern.INTEGER = pattern("numeric", 0,
    function() return "integer" end,
    function(v) return math_type(v) == "integer" end)

pattern.INTEGER_OR_NIL = pattern("numeric", nil,
    function() return "integer?" end,
    function(v) return v == nil or math_type(v) == "integer" end)

pattern.POSITIVE_INTEGER = pattern("numeric", 1,
    function() return "positive_integer" end,
    function(v) return math_type(v) == "integer" and v > 0 end)

pattern.NONPOSITIVE_INTEGER = pattern("numeric", 0,
    function() return "nonpositive_integer" end,
    function(v) return math_type(v) == "integer" and v <= 0 end)

pattern.NEGATIVE_INTEGER = pattern("numeric", -1,
    function() return "negative_integer" end,
    function(v) return math_type(v) == "integer" and v < 0 end)

pattern.NONNEGATIVE_INTEGER = pattern("numeric", 0,
    function() return "nonnegative_integer" end,
    function(v) return math_type(v) == "integer" and v >= 0 end)

pattern.EVEN_INTEGER = pattern("numeric", 0,
    function() return "even_integer" end,
    function(v) return v % 2 == 0 end)

pattern.ODD_INTEGER = pattern("numeric", 1,
    function() return "odd_integer" end,
    function(v) return v % 2 == 1 end)

pattern.POSITIVE_EVEN_INTEGER = pattern("numeric", 2,
    function() return "positive_even_integer" end,
    function(v) return v > 0 and v % 2 == 0 end)

pattern.POSITIVE_ODD_INTEGER = pattern("numeric", 1,
    function() return "positive_odd_integer" end,
    function(v) return v > 0 and v % 2 == 1 end)

pattern.NEGATIVE_EVEN_INTEGER = pattern("numeric", -2,
    function() return "negative_even_integer" end,
    function(v) return v < 0 and v % 2 == 0 end)

pattern.NEGATIVE_ODD_INTEGER = pattern("numeric", -1,
    function() return "negative_odd_integer" end,
    function(v) return v < 0 and v % 2 == 1 end)

pattern.NONNEGATIVE_EVEN_INTEGER = pattern("numeric", 0,
    function() return "nonnegative_even_integer" end,
    function(v) return v >= 0 and v % 2 == 0 end)

pattern.range = function(min_value, max_value)
    guard.non_nil("min_value", min_value)
    guard.non_nil("max_value", max_value)

    local pat = pattern("range", min_value,
        function()
            return format("[%s ~ %s]", min_value, max_value)
        end,
        function(v, c)
            local succ, res = pcall(function()
                return min_value <= v and v <= max_value
            end)
            return succ, res
        end)

    function pat:get_min()
        return min_value
    end

    function pat:get_max()
        return max_value
    end

    return pat
end

-- string patterns

pattern.NONEMPTY_STRING = pattern("string", "NIL",
    function() return "nonempty_string" end,
    function(v) return type(v) == "string" and #v > 0 end)

pattern.regex = function(regex)
    guard.string("regex", regex)

    local pat = pattern("string", "",
        function()
            return format("/%s/", regex)
        end,
        function(v)
            return type(v) == "string" and find(regex, v)
        end)
    
    function pat:get_regex()
        return regex
    end

    return pat
end

-- callable patterns

pattern.CALLABLE = pattern("callable", ID_FUNC,
    function() return "callable" end,
    function(v)
        if type(v) == "function" then
            return true
        end
        local mt = getmetatable(v)
        return type(mt) == "table" and mt.__call
    end)

pattern.CALLABLE_OR_NIL = pattern("callable", nil,
    function() return "callable?" end,
    function(v)
        if not v or type(v) == "function" then
            return true
        end
        local mt = getmetatable(v)
        return type(mt) == "table" and mt.__call
    end)

-- meta patterns

pattern.meta = function(name, metatable)
    guard.nonempty_string("name", name)
    guard.table("metatable", metatable)

    local pat = pattern("meta", nil,
        function()
            return "%"..name
        end,
        function(v)
            return v == nil or getmetatable(v) == metatable
        end)
    
    function pat:get_metatable()
        return metatable
    end

    return pat
end

-- enum patterns

pattern.enum = function(items)
    guard.table("items", items)

    local item_arr = {}
    local item_map = {}

    for i = 1, #items do
        local item = items[i]
        if item_map[item] then
            error("duplicate item found: "..tostring(item))
        end
        item_arr[i] = item
        item_map[item] = i
    end

    readonly(item_arr)

    local pat = pattern("enum", items[1],
        function()
            local res = {"("}
            for i = 1, #item_arr do
                local item = item_arr[i]
                if type(item) == "string" then
                    res[#res+1] = "\""
                    res[#res+1] = item
                    res[#res+1] = "\""
                else
                    res[#res+1] = tostring(item)
                end
                res[#res+1] = " | "
            end
            res[#res] = ")"
            return concat(res)
        end,
        function(v)
            return item_map[v]
        end)
    
    function pat:get_items()
        return item_arr
    end

    return pat
end

-- table patterns

pattern.array = function(element_pattern)
    assert(getmetatable(element_pattern) == pattern,
        "invalid element_pattern")
    
    local pat = pattern("array", EMPTY_TABLE,
        function()
            return format("{%s}",
                element_pattern:get_description())
        end,
        function(v, c, s)
            if type(v) ~= "table" then
                return false
            end
            for i = 1, #v do
                if not element_pattern:match(v[i], c, s) then
                    return false
                end
            end
            return true
        end)
    
    function pat:get_element_pattern()
        return element_pattern
    end

    return pat
end

pattern.map = function(key_pattern, value_pattern)
    assert(getmetatable(key_pattern) == pattern,
        "invalid key_pattern")
    assert(getmetatable(value_pattern) == pattern,
        "invalid value_pattern")
    
    local pat = pattern("map", EMPTY_TABLE,
        function()
            return format("{%s => %s}",
                key_pattern:get_description(),
                value_pattern:get_description())
        end,
        function(v, c, s)
            if type(v) ~= "table" then
                return false
            end
            for key, value in pairs(v) do
                if not key_pattern:match(key, c, s)
                    or not value_pattern:match(value, c, s) then
                    return false
                end
            end
            return true
        end)
    
    function pat:get_key_pattern()
        return key_pattern
    end

    function pat:get_value_pattern()
        return value_pattern
    end

    return pat
end

pattern.tuple = function(...)
    local subpats = readonly {...}
    if #subpats == 0 then
        error("no subpattern provided")
    end

    local default

    for i = 1, #subpats do
        local subpat = subpats[i]
        if getmetatable(subpat) ~= pattern then
            error("invalid subpattern at index #"..i)
        end
        if not subpat:has_default() then
            default = NO_DEFAULT
        end
    end

    if default ~= NO_DEFAULT then
        default = {}
        for i = 1, #subpats do
            default[i] = subpats[i]:get_default()
        end
        readonly(default)
    end

    local pat = pattern("tuple", default,
        function()
            local res = {"("}
            for i = 1, #subpats do
                res[#res+1] = subpats[i]:get_description()
                res[#res+1] = ", "
            end
            res[#res] = ")"
            return concat(res)
        end,
        function(v, c, s)
            if type(v) ~= "table" then
                return false
            end
            for i = 1, #subpats do
                if not subpats[i]:match(v[i], c, s) then
                    return false
                end
            end
            return true
        end)
    
    function pat:get_subpatterns()
        return subpats
    end

    return pat
end

pattern.table = function(entries)
    guard.table("entries", entries)
    
    local entries_cpy = {}
    local default

    for key, value_pat in pairs(entries) do
        if getmetatable(value_pat) ~= pattern then
            error("invalid entry at index #"..i)
        end

        entries_cpy[key] = value_pat

        if not value_pat:has_default() then
            default = NO_DEFAULT
        end
    end

    readonly(entries_cpy)

    if default ~= NO_DEFAULT then
        default = {}
        for key, value_pat in pairs(entires) do
            default[key] = value_pat:get_default()
        end
        readonly(default)
    end

    local pat = pattern("table", default,
        function()
            local res = {"{"}
            for key, value_pat in pairs(entries_cpy) do
                res[#res+1] = tostring(key)
                res[#res+1] = " = "
                res[#res+1] = value_pat:get_description()
                res[#res+1] = ", "
            end
            res[#res] = "}"
            return concat(res)
        end,
        function(v, c, s)
            if type(v) ~= "table" then
                return false
            end

            for key, value_pat in pairs(entries_cpy) do
                local value = v[key]
                if value then
                    if not value_pat:match(value, c, s) then
                        return false
                    end
                elseif not value_pat:has_default() then
                    return false
                end
            end
            return true
        end)
    
    function pat:get_entries()
        return entries_cpy
    end

    return pat
end

pattern.loop = function(...)
    local subpats = readonly {...}
    if #subpats == 0 then
        error("no subpattern provided")
    end

    for i = 1, #subpats do
        local subpat = subpats[i]
        if getmetatable(subpat) ~= pattern then
            error("invalid subpattern at index #"..i)
        end
        if subpat:match(nil) then
            error("pattern that matches nil cannot be used in loop")
        end
    end

    local pat = pattern("loop", EMPTY_TABLE,
        function()
            local res = {"loop {"}
            for i = 1, #subpats do
                res[#res+1] = subpats[i]:get_description()
                res[#res+1] = ", "
            end
            res[#res] = "}"
            return concat(res)
        end,
        function(v, c, s)
            if type(v) ~= "table" then
                return false
            end
            local i = 1
            while i <= #v do
                for j = 1, #subpats do
                    local subpat = subpats[j]
                    if not subpat:match(v[i], c, s) then
                        return false
                    end
                    i = i + 1
                end
            end
            return true
        end)
    
    function pat:get_subpatterns()
        return subpats
    end

    return pat
end

return pattern