--=============================================================================
-- CACHE — valeur horodatee, expirable, invalidable
--=============================================================================
--  Regle de l'architecture : aucune donnee de carte n'est une verite
--  permanente. Une position n'est utilisable que si elle est ENCORE valide,
--  ce qui suppose trois choses qu'un simple `local pos = ...` ne donne pas :
--
--    1. une date de peremption (le monde bouge sans nous prevenir) ;
--    2. un validateur (l'entite existe-t-elle toujours, au meme endroit ?) ;
--    3. une invalidation explicite sur echec (invalidate-on-failure).
--
--  `:get()` renvoie nil des qu'une des trois conditions tombe. Un appelant
--  qui ignore le nil retombe donc en rescan, jamais sur une donnee morte.
--=============================================================================

local Cache = {}
Cache.__index = Cache

-- opts.ttl        : duree de vie en secondes (nil = pas d'expiration temporelle)
-- opts.validator  : function(value, meta) -> boolean, appele a chaque lecture
-- opts.name       : etiquette de journalisation
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

-- Valide sans consommer : utile pour decider d'un rafraichissement anticipe.
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

-- Unique lecture autorisee. Invalide au passage si la valeur est morte, pour
-- que l'entree ne soit pas re-testee a chaque frame.
function Cache:get()
    local ok, reason = self:isValid()
    if ok then return self.value, self.meta end
    if self.value ~= nil then self:invalidate(reason) end
    return nil
end

-- Lecture explicitement degradee : rend la derniere valeur connue meme
-- perimee. Reservee aux replis de dernier recours, qui doivent tracer d'ou
-- vient la donnee (voir Trust).
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
