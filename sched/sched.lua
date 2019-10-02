local guard = require("meido.guard")
local array = require("meido.array")
local event = require("meido.event")
local async = require("meido.async")

local array_clear = array.clear
local etrigger = event.trigger
local current_coroutine = async.current_coroutine
local safe_resume = async.safe_resume

local remove = table.remove
local coroutine_yield = coroutine.yield

local sched = {}
sched.__index = sched

setmetatable(sched, {
    __call = function(self)
        local t = {
            signals = {},
            table_pool = {}
        }
        return setmetatable(t, self)
    end
})

function sched:notify(signal, callback)
    guard.non_nil("signal", signal)
    guard.callable("callback", callback)

    local signals = self.signals
    local callbacks = signals[signal]

    if not callbacks then
        local pool = self.table_pool
        if #pool == 0 then
            callbacks = {}
        else
            callbacks = pool[#pool]
            pool[#pool] = nil
        end
        signals[signal] = callbacks
    end

    callbacks[#callbacks+1] = callback
end

local function assert_not_locked(callbacks)
    if callbacks.lock then
        error("signal callbacks are locked", 2)
    end
end

function sched:unnotify(signal, callback)
    local signals = self.signals
    local callbacks = signals[signal]
    if not callbacks then return end

    assert_not_locked(callbacks)

    for i = 1, #callbacks do
        if callbacks[i] == callback then
            remove(callbacks, i)
            if #callbacks == 0 then
                local pool = self.table_pool
                pool[#pool+1] = callbacks
                signals[signal] = nil
            end
            return true
        end
    end
end

function sched:unnotify_all(signal)
    local signals = self.signals
    local pool = self.table_pool

    if signal then
        local callbacks = signals[signal]
        if callbacks then
            assert_not_locked(callbacks)
            pool[#pool+1] = array_clear(callbacks)
            signals[signal] = nil
        end
    else
        for signal, callbacks in pairs(signals) do
            assert_not_locked(callbacks)
            pool[#pool+1] = array_clear(callbacks)
            signals[signal] = nil
        end
    end
end

function sched:get_callback_count(signal)
    local callbacks = self.signals[signal]
    return callbacks and #callbacks or 0
end

function sched:iter_monitored_signals()
    local signals = self.signals
    local signal
    return function()
        signal = next(signals, signal)
        return signal
    end
end

local remove_tables = {}

function sched:trigger_silent(signal, ...)
    local signals = self.signals
    local callbacks = signals[signal]
    if not callbacks then return end

    if callbacks.lock then
        error("signal is being triggered")
        return
    end
    callbacks.lock = true

    local remove_table
    local remove_count = 0

    local rt_count = #remove_tables
    if rt_count > 0 then
        remove_table = remove_tables[rt_count]
        remove_tables[rt_count] = nil
    else
        remove_table = {}
    end

    local callback_i = 1
    local callback_error

    local success, err = pcall(function(...)
        local count = #callbacks
        while callback_i <= count do
            local callback = callbacks[callback_i]
            if callback(signal, ...) then
                remove_count = remove_count + 1
                remove_table[remove_count] = callback_i
            end
            callback_i = callback_i + 1
        end
    end, ...)

    if not success then
        callback_error = err
        remove_count = remove_count + 1
        remove_table[remove_count] = callback_i
    end

    callbacks.lock = nil

    if remove_count == 0 then
        remove_tables[#remove_tables + 1] = remove_table
        return
    end

    local callback_count = #callbacks

    if remove_count == callback_count then
        local pool = self.table_pool
        pool[#pool+1] = array_clear(callbacks)
        signals[signal] = nil
    else
        for i = 1, remove_count - 1 do
            local from = remove_table[i] + 1
            local to = remove_table[i+1] - 1
            for j = from, to do
                callbacks[j - i] = callbacks[j]
            end
        end

        local last_start = remove_table[remove_count] + 1
        for i = last_start, callback_count do
            callbacks[i - remove_count] = callbacks[i]
        end

        local clear_start = callback_count - remove_count + 1
        for i = clear_start, callback_count do
            callbacks[i] = nil
        end
    end

    remove_tables[#remove_tables + 1] = remove_table

    if callback_error then
        error(callback_error, 0)
    end
end

function sched:trigger(signal, ...)
    self:trigger_silent(signal, ...)
    etrigger(self, "on_trigger", signal, ...)
end

function sched:wait(signal)
    local co = current_coroutine()

    self:notify(signal, function(_, ...)
        safe_resume(co, ...)
        return true
    end)

    return coroutine_yield()
end

function sched:skip(signal)
    local co = current_coroutine()

    self:notify(signal, function()
        safe_resume(co)
        return true
    end)

    coroutine_yield()
end

function sched:wait_many(signal, count)
    guard.positive("count", count)

    local co = current_coroutine()
    local res = {}
    local counter = 0

    self:notify(signal, function(_, a1, a2, ...)
        if not a2 then
            -- no arg or one arg
            res[#res+1] = a1
        else
            res[#res+1] = {a1, a2, ...}
        end
        counter = counter + 1

        if counter >= count then
            safe_resume(co, res)
            return true
        end
    end)

    return coroutine_yield()
end

function sched:skip_many(signal, count)
    guard.positive("count", count)

    local co = current_coroutine()
    local counter = 0

    self:notify(signal, function()
        counter = counter + 1

        if counter >= count then
            safe_resume(co)
            return true
        end
    end)

    coroutine_yield()
end

function sched:wait_until(signal, predicate)
    guard.callable("predicate", predicate)

    local co = current_coroutine()
    local res = {}

    self:notify(signal, function(_, a1, a2, ...)
        if predicate(a1, a2, ...) then
            safe_resume(co, res)
            return true
        end
        if not a2 then
            -- no arg or one arg
            res[#res+1] = a1
        else
            res[#res+1] = {a1, a2, ...}
        end
    end)

    return coroutine_yield()
end

function sched:skip_until(signal, predicate)
    guard.callable("predicate", predicate)

    local co = current_coroutine()

    self:notify(signal, function(_, ...)
        if predicate(...) then
            safe_resume(co, ...)
            return true
        end
    end)

    return coroutine_yield()
end

function sched:skip_for(signal, value)
    local co = current_coroutine()
    local initial

    self:notify(signal, function(_, v) 
        initial = v

        self:notify(signal, function(_, v) 
            if v - initial > value then
                safe_resume(co)
                return true
            end
        end)

        return true
    end)

    return coroutine_yield()
end

function sched:select(spec)
    for signal, handler in pairs(spec) do
        guard.callable("handler", handler)
    end

    local co = current_coroutine()

    local callback
    callback = function(curr_signal, ...)
        for signal in pairs(spec) do
            if signal ~= curr_signal then
                self:unnotify(signal, callback)
            end
        end
        safe_resume(co, spec[curr_signal](...))
        return true
    end

    for signal in pairs(spec) do
        self:notify(signal, callback)
    end

    return coroutine_yield()
end

return sched