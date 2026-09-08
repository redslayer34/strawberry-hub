--=============================================================================
-- LOG — categorised journal for the AutomationCore
--=============================================================================
--  One output point, one category per subsystem. A category can be silenced
--  without touching the code that emits it, which is what stops `print` calls
--  from being added and then commented out again.
--
--  A ring buffer keeps the last lines even for silenced categories: when the
--  farm goes wrong the history is already there, without having had to turn
--  logging on before the problem happened.
--=============================================================================

local Log = {}

Log.TAGS = {
    "Core", "Quest", "Island", "Sea", "QuestGiver", "Target", "Bring",
    "Combat", "Travel", "Mastery", "Material", "Boss", "CDK", "Recovery",
    "ServerHop", "State", "Perception",
}

local HISTORY_LIMIT = 200

local enabled = true
local muted = {}            -- tag -> true : category silenced
local history = {}          -- ring buffer of recent lines
local cursor = 0
local sink = nil            -- optional destination (UI, file)
local lastLine = {}         -- tag -> last line, for repeat suppression
local repeats = {}          -- tag -> consecutive repeat count

function Log.setEnabled(value) enabled = value and true or false end
function Log.isEnabled() return enabled end

function Log.mute(tag, value)
    muted[tag] = value and true or nil
end

function Log.setSink(fn) sink = fn end

-- Concatenates while tolerating nil arguments in the middle: a log call must
-- never raise inside a farming path.
local function join(...)
    local n = select("#", ...)
    local parts = table.create and table.create(n) or {}
    for i = 1, n do
        local v = select(i, ...)
        parts[i] = tostring(v)
    end
    return table.concat(parts, " ")
end

function Log.write(tag, ...)
    local text = join(...)
    local line = "[" .. tag .. "] " .. text

    cursor = cursor + 1
    history[(cursor - 1) % HISTORY_LIMIT + 1] = { tag = tag, text = text, clock = os.clock() }

    if not enabled or muted[tag] then return end

    -- A looping state machine emits the same line hundreds of times a minute.
    -- Only changes are printed, with a counter.
    if lastLine[tag] == text then
        repeats[tag] = (repeats[tag] or 0) + 1
        if repeats[tag] % 50 ~= 0 then return end
        line = line .. "  (x" .. repeats[tag] .. ")"
    else
        lastLine[tag] = text
        repeats[tag] = 0
    end

    if sink then
        pcall(sink, tag, text)
    else
        print("[Strawberry]" .. line)
    end
end

-- Shorthands: Log.Quest("Target =", name) reads better than Log.write("Quest", ...)
for _, tag in ipairs(Log.TAGS) do
    Log[tag] = function(...) Log.write(tag, ...) end
end

-- Buffered lines, oldest first.
function Log.history()
    local out = {}
    local n = math.min(cursor, HISTORY_LIMIT)
    for i = 1, n do
        local idx = (cursor - n + i - 1) % HISTORY_LIMIT + 1
        out[i] = history[idx]
    end
    return out
end

function Log.clear()
    table.clear(history)
    table.clear(lastLine)
    table.clear(repeats)
    cursor = 0
end

return Log
