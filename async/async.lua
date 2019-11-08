local guard = require("meido.guard")
local meta = require("meido.meta")

local coroutine_create = coroutine.create
local coroutine_running = coroutine.running
local coroutine_yield = coroutine.yield
local coroutine_resume = coroutine.resume

local remove = table.remove

local async = {}

-- cancellation token

local cancellation_token = {}
cancellation_token.__index = cancellation_token

function cancellation_token:notify(callback)
    guard.callable("callback", callback)

    local on_cancelled = self.on_cancelled
    on_cancelled[#on_cancelled+1] = callback
end

function cancellation_token:unnotify(callback)
    guard.callable("callback", callback)

    local on_cancelled = self.on_cancelled
    for i = 1, #on_cancelled do
        if on_cancelled[i] == callback then
            remove(on_cancelled, i)
            return true
        end
    end

    return false
end

function cancellation_token:link_to(other_token)
    assert(getmetatable(other_token) == cancellation_token,
        "other_token must be cancellation token")

    other_token:notify(function()
        self:cancel()
    end)
end

local function is_cancelled_false()
    return false
end

local function is_cancelled_true()
    return true
end

function cancellation_token:cancel()
    if self.is_cancelled == is_cancelled_true then
        return
    end
    self.is_cancelled = is_cancelled_true

    local on_cancelled = self.on_cancelled
    for i = 1, #on_cancelled do
        on_cancelled[i]()
        on_cancelled[i] = nil
    end
end

local cancelled_token = setmetatable({
    on_cancelled = meta.ungrowable {},
    is_cancelled = is_cancelled_true
}, cancellation_token)

async.cancellation_token = function(cancelled)
    if cancelled then
        return cancelled_token
    end
    local t = {
        on_cancelled = {},
        is_cancelled = is_cancelled_false
    }
    return setmetatable(t, cancellation_token)
end

-- methods

local function current_coroutine()
    return assert(coroutine_running(),
        "should be run in coroutine")
end

local function safe_resume(co, ...)
    local success, err =
        coroutine_resume(co, ...)
    if not success then
        error(err, 0)
    end
end

async.current_coroutine = current_coroutine
async.safe_resume = safe_resume

async.spawner = function(f)
    return function(...)
        local co = coroutine_create(f)
        safe_resume(co, ...)
        return co
    end
end

async.run = function(f, ...)
    local co = coroutine_create(f)
    safe_resume(co, ...)
    return co
end

async.forever = function(f, ...)
    local co = coroutine_create(function()
        while true do
            f()
        end
    end)
    safe_resume(co, ...)
    return co
end

async.all = function(fs)
    guard.table("fs", fs)

    local fs_count = #fs
    for i = 1, fs_count do
        local f = fs[i]
        guard.callable("element in fs", f)
    end

    local co = current_coroutine()
    local results = {}
    local resumed = false

    for i = 1, #fs do
        local f = fs[i]
        local f_co = coroutine_create(function()
            local res, err = f()

            if resumed then
                return -- ignored
            elseif not res then
                safe_resume(co, nil, err)
            else
                local count = #results + 1
                results[count] = res
                if count ~= fs_count then
                    return
                end
                safe_resume(co, results)
            end

            resumed = true
        end)
        safe_resume(f_co)
    end

    return coroutine_yield()
end

async.any = function(fs)
    guard.table("fs", fs)

    local fs_count = #fs
    for i = 1, fs_count do
        local f = fs[i]
        guard.callable("element in fs", f)
    end

    local co = current_coroutine()
    local resumed = false

    for i = 1, #fs do
        local f = fs[i]
        local f_co = coroutine_create(function()
            local res, err = f()

            if resumed then
                return -- ignored
            end

            safe_resume(co, res, err)
            resuemd = true
        end)
        safe_resume(f_co)
    end

    return coroutine_yield()
end

return async