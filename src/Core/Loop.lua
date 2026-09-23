--=============================================================================
-- LOOP — named background loops that can all be stopped at once
--=============================================================================
--  Every repeating job in the hub runs through here. Starting a loop under a
--  name that is already running replaces it, an error inside one iteration
--  is reported (at most every few seconds) without killing the loop, and
--  Loop.stopAll() is what makes Unload actually stop everything.
--=============================================================================

local Loop = {}

local WARN_EVERY = 5

local running = {}

function Loop.start(name, interval, fn)
    Loop.stop(name)

    local token = { alive = true }
    running[name] = token

    task.spawn(function()
        local lastWarn = -math.huge
        while token.alive do
            local ok, err = pcall(fn)
            if not ok then
                local now = os.clock()
                if now - lastWarn >= WARN_EVERY then
                    lastWarn = now
                    warn("[Strawberry Hub] " .. name .. ": " .. tostring(err))
                end
            end
            if not token.alive then break end
            -- A function interval is re-read every iteration, so a delay
            -- slider takes effect without restarting the loop.
            if type(interval) == "function" then
                task.wait(interval())
            else
                task.wait(interval)
            end
        end
    end)

    return token
end

function Loop.stop(name)
    local token = running[name]
    if token then
        token.alive = false
        running[name] = nil
    end
end

function Loop.stopAll()
    for name in pairs(running) do
        Loop.stop(name)
    end
end

function Loop.isRunning(name)
    return running[name] ~= nil
end

return Loop
