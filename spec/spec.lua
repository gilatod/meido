local guard = require("meido.guard")
local object = require("meido.object")
local seq = require("meido.seq")

local show = object.show
local clone = object.clone
local equal = object.equal

local concat = table.concat
local gsub = string.gsub

local spec = {
    max_argument_count = 32
}

spec.get_max_argument_count = function()
    return spec.max_argument_count
end

spec.set_max_argument_count = function(count)
    spec.max_argument_count = count
end

-- auxiliary functions

local function require_description(config)
    local description = config.description
    guard.nonempty_string("config.description", description)
    return description
end

local function require_method(config, name)
    local method = config[name]
    guard.callable("config."..name, method)
    return method
end

local function require_methods(config, name)
    local methods = config[name]

    local print_name = "config."..name
    guard.table(print_name, methods)

    local elem_print_name = "elements in "..print_name
    for _, method in pairs(methods) do
        guard.callable(elem_print_name, method)
    end

    return methods
end

local function require_check_equal(config)
    local check_equal = config.check_equal
    if check_equal then
        guard.callable("config.check_equal", check_equal)
    else
        -- use object.equal
        check_equal = equal
    end
    return check_equal
end

local function require_arguments(config)
    local arguments = config.arguments
    if not arguments then
        return nil
    end
    guard.table("config.arguments", arguments)
    guard.callable("config.arguments:iter", arguments.iter)
    return arguments
end

local function format(obj)
    local res = gsub(show(obj, "\t"), "^%s", "")
    return res
end

local function format_err(err)
    local res = "[error] "..gsub(err, "([\r\n]+)", "%1\t")
    return res
end

local function format_res(res, success)
    if success then
        return format(res)
    else
        return format_err(res)
    end
end

local function foreach_arg(self, arguments, f)
    if not arguments then
        arguments = self.arguments
        if not arguments then
            error("arguments not provided")
        end
    else
        guard.table("arguments", arguments)
        guard.callable("arguments:iter", arguments.iter)
    end

    local count = 1
    local max_argument_count = spec.max_argument_count

    for arg in arguments:iter() do
        if count > max_argument_count then
            return
        end
        f(arg)
        count = count + 1
    end
end

local function err(info)
    error(concat(info), 0)
end

-- satisfy spec

local satisfy_spec = {}
satisfy_spec.__index = satisfy_spec

function satisfy_spec:get_description()
    return self.description
end

function satisfy_spec:get_type()
    return "satisfy"
end

function satisfy_spec:check(arguments)
    local method = self.method
    local description = self.description

    local function check_method(arg)
        local success, res = pcall(method, clone(arg))
        if not success or not res then
            err {
                "satisfy check failed -->",
                "\n\tdescription: ", description,
                "\n\targument: ", format(arg),
                "\n\tresult: ", format_res(res, success),
            }
        end
    end

    foreach_arg(self, arguments, check_method)
    return true
end

spec.satisfy = function(config)
    guard.table("config", config)

    local s = setmetatable({
        description = require_description(config),
        method      = require_method(config, "method"),
        arguments   = require_arguments(config)
    }, satisfy_spec)

    if config.arguments then
        s:check()
    end

    return s
end

-- identity spec

local identity_spec = {}
identity_spec.__index = identity_spec

function identity_spec:get_description()
    return self.description
end

function identity_spec:get_type()
    return "identity"
end

function identity_spec:check(arguments)
    local methods = self.methods
    local check_equal = self.check_equal
    local description = self.description

    local function check_methods(arg)
        local prev_name, method = next(methods)

        local success, prev_res =
            pcall(method, clone(arg))
            -- argument is cloned to prevent incidental
            -- modification, as for other specs
        if not success then
            err {
                "identity check failed -->",
                "\n\tdescription: ", description,
                "\n\targument: ", format(arg),
                "\n\tcurrent method: ", prev_name,
                "\n\tcurrent result: ", format_err(prev_res),
            }
        end

        for curr_name, method in next, methods, prev_name do
            local method_success, method_res =
                pcall(method, clone(arg))
            local check_success, check_res

            if method_success then
                check_success, check_res =
                    pcall(check_equal, method_res, prev_res)
            end

            if not check_success or not check_res then
                err {
                    "identity check failed -->",
                    "\n\tdescription: ", description,
                    "\n\targument: ", format(arg),
                    "\n\tprevious method: ", prev_name,
                    "\n\tprevious result: ", format(prev_res),
                    "\n\tcurrent method: ", curr_name,
                    "\n\tcurrent result: ",
                        format_res(method_res, method_success),
                    "\n\tcheck result: ", method_success and
                        format_res(check_res, check_success)
                        or "nil"
                }
            end

            prev_name = curr_name
            prev_res = method_res
        end
    end

    foreach_arg(self, arguments, check_methods)
    return true
end

spec.identity = function(config)
    guard.table("config", config)

    local s = setmetatable({
        description = require_description(config),
        methods     = require_methods(config, "methods"),
        check_equal = require_check_equal(config),
        arguments   = require_arguments(config) 
    }, identity_spec)

    if config.arguments then
        s:check()
    end

    return s
end

-- reversability spec

local reversability_spec = {}
reversability_spec.__index = reversability_spec

function reversability_spec:get_description()
    return self.description
end

function reversability_spec:get_type()
    return "reversability"
end

function reversability_spec:check(arguments)
    local mid_method = self.middle_method
    local rev_method = self.reverse_method
    local check_equal = self.check_equal
    local description = self.description

    local function check_methods(arg)
        local mid_success, mid_res =
            pcall(mid_method, clone(arg))

        if not mid_success then
            err {
                "reversability check failed -->",
                "\n\tdescription: ", description,
                "\n\targument: ", format(arg),
                "\n\tmiddle result: ", format_err(mid_res)
            }
        end

        -- do reverse

        local rev_success, rev_res =
            pcall(rev_method, clone(mid_res))
        local check_success, check_res

        if rev_success then
            check_success, check_res =
                pcall(check_equal, arg, rev_res)
        end

        if not check_success or not check_res then
            err {
                "reversability check failed -->",
                "\n\tdescription: ", description,
                "\n\targument: ", format(arg),
                "\n\tmiddle result: ", format(mid_res),
                "\n\treverse result: ",
                    format_res(rev_res, rev_success),
                "\n\tcheck result: ", rev_success and
                    format_res(check_res, check_success)
                    or "nil"
            }
        end
    end

    foreach_arg(self, arguments, check_methods)
    return true
end

spec.reversability = function(config)
    guard.table("config", config)
    
    local s = setmetatable({
        description    = require_description(config),
        middle_method  = require_method(config, "middle_method"),
        reverse_method = require_method(config, "reverse_method"),
        check_equal    = require_check_equal(config),
        arguments      = require_arguments(config) 
    }, reversability_spec)

    if config.arguments then
        s:check()
    end

    return s
end

-- idemptency spec

local idempotency_spec = {}
idempotency_spec.__index = idempotency_spec

function idempotency_spec:get_description()
    return self.description
end

function idempotency_spec:get_type()
    return "idempotency"
end

function idempotency_spec:check(arguments)
    local method = self.method
    local check_equal = self.check_equal
    local description = self.description

    local function check_method(arg)
        local fst_success, fst_res = pcall(method, clone(arg))
        if not fst_success then
            err {
                "idempotency check failed -->",
                "\n\tdescription: ", description,
                "\n\targument: ", format(arg),
                "\n\tfirst result: ", format_err(fst_res),
            }
        end

        local snd_success, snd_res = pcall(method, clone(fst_res))
        local check_success, check_res

        if snd_success then
            check_success, check_res =
                pcall(check_equal, fst_res, snd_res)
        end

        if not check_success or not check_res then
            err {
                "idempotency check failed -->",
                "\n\tdescription: ", description,
                "\n\targument: ", format(arg),
                "\n\tfirst result: ", format(fst_res),
                "\n\tsecond result: ",
                    format_res(snd_res, snd_success),
                "\n\tcheck result: ", snd_success and
                    format_res(check_res, check_success)
                    or "nil"
            }
        end
    end

    foreach_arg(self, arguments, check_method)
    return true
end

spec.idempotency = function(config)
    guard.table("config", config)
    
    local s = setmetatable({
        description = require_description(config),
        method      = require_method(config, "method"),
        check_equal = require_check_equal(config),
        arguments   = require_arguments(config)
    }, idempotency_spec)
    
    if config.arguments then
        s:check()
    end

    return s
end

-- commutativity spec

local commutativity_spec = {}
commutativity_spec.__index = commutativity_spec

function commutativity_spec:get_description()
    return self.description
end

function commutativity_spec:get_type()
    return "commutativity"
end

function commutativity_spec:check(arguments)
    local method = self.method
    local check_equal = self.check_equal
    local description = self.description

    local function check_method(arg)
        guard.table("argument", arg)
        local arg1 = arg[1]
        local arg2 = arg[2]

        local fst_success, fst_res =
            pcall(method, clone(arg1), clone(arg2))
        if not fst_success then
            err {
                "idempotency check failed -->",
                "\n\tdescription: ", description,
                "\n\targument 1: ", format(arg1),
                "\n\targument 2: ", format(arg2),
                "\n\tfirst result: ", format_err(fst_res),
            }
        end

        local snd_success, snd_res =
            pcall(method, clone(arg2), clone(arg1))
        local check_success, check_res

        if snd_success then
            check_success, check_res =
                pcall(check_equal, fst_res, snd_res)
        end
        
        if not check_success or not check_res then
            err {
                "idempotency check failed -->",
                "\n\tdescription: ", description,
                "\n\targument 1: ", format(arg1),
                "\n\targument 2: ", format(arg2),
                "\n\tfirst result: ", format(fst_res),
                "\n\tsecond result: ",
                    format_res(snd_res, snd_success),
                "\n\tcheck result: ", snd_success and
                    format_res(check_res, check_success)
                    or "nil"
            }
        end
    end

    foreach_arg(self, arguments, check_method)
    return true
end

spec.commutativity = function(config)
    guard.table("config", config)
    
    local s = setmetatable({
        description = require_description(config),
        method      = require_method(config, "method"),
        check_equal = require_check_equal(config),
        arguments   = require_arguments(config)
    }, commutativity_spec)
    
    if config.arguments then
        s:check()
    end

    return s
end

return spec