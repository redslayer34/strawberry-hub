--=============================================================================
-- CACHE — a timestamped value that can expire and be invalidated
--=============================================================================
--  Architectural rule: no map data is ever a permanent truth. A position may
--  only be used if it is STILL valid, which needs three things a plain
--  `local pos = ...` does not give you:
--
--    1. an expiry (the world moves without telling us);
--    2. a validator (does the entity still exist, in the same place?);
--    3. explicit invalidation on failure (invalidate-on-failure).
--
--  `:get()` returns nil as soon as any of the three fails. A caller that
--  ignores the nil therefore falls back to rescanning, never to dead data.
--=============================================================================

local Cache = {}
Cache.__index = Cache

-- opts.ttl        : lifetime in seconds (nil = no time-based expiry)
-- opts.validator  : function(value, meta) -> boolean, called on every read
-- opts.name       : label for logging
function Cache.new(opts)
    opts = opts or {}
    return setmetatable({
        name = opts.name or "cache",
        ttl = opts.ttl,
        validator = opts.validator,
        value = nil,
        meta = nil,
        stamp = nil,
        invalidations = 0,
        lastReason = nil,
    }, Cache)
end

function Cache:set(value, meta)
    self.value = value
    self.meta = meta
    self.stamp = os.clock()
    return value
end

function Cache:age()
    if not self.stamp then return math.huge end
    return os.clock() - self.stamp
end

-- Validates without consuming: useful to decide on an early refresh.
function Cache:isValid()
    if self.value == nil then return false, "empty" end
    if self.ttl and self:age() > self.ttl then return false, "expired" end
    if self.validator then
        local ok, result = pcall(self.validator, self.value, self.meta)
        if not ok then return false, "validator error" end
        if not result then return false, "invalid" end
    end
    return true
end

-- The only sanctioned read. Invalidates on the way out if the value is dead,
-- so the entry is not re-tested on every frame.
function Cache:get()
    local ok, reason = self:isValid()
    if ok then return self.value, self.meta end
    if self.value ~= nil then self:invalidate(reason) end
    return nil
end

-- Explicitly degraded read: returns the last known value even when stale.
-- Reserved for last-resort fallbacks, which must record where the data came
-- from (see Trust).
function Cache:peek()
    return self.value, self.meta, self:age()
end

function Cache:invalidate(reason)
    if self.value == nil then return end
    self.value = nil
    self.meta = nil
    self.stamp = nil
    self.invalidations = self.invalidations + 1
    self.lastReason = reason or "manual"
end

function Cache:refreshStamp()
    if self.value ~= nil then self.stamp = os.clock() end
end

return Cache
