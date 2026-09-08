--=============================================================================
-- CONFIG — AutomationCore settings
--=============================================================================
--  Every tunable number lives here. No magic constants in the modules: tuning
--  behaviour must never require reading an algorithm first.
--=============================================================================

return {
    -- Perception loop pacing. A full Workspace scan is expensive: it is spaced
    -- out, and tightened during combat when state changes fast.
    Perception = {
        IdleInterval = 2.0,        -- s between passes outside combat
        CombatInterval = 0.4,      -- s between passes during combat
        QuestPollInterval = 0.5,   -- s between quest-state reads
        MaxScanPerTick = 400,      -- instances inspected per pass, at most
    },

    Quest = {
        -- Objective patterns, tried in order. Moving or adding one does not
        -- mean touching the code.
        Patterns = {
            "^%s*Defeat%s+(%d+)%s+(.+)$",
            "^%s*Kill%s+(%d+)%s+(.+)$",
            "^%s*Eliminate%s+(%d+)%s+(.+)$",
            "^%s*Vaincre%s+(%d+)%s+(.+)$",
        },
        ProgressPatterns = {
            "%[(%d+)%s*/%s*(%d+)%]",
            "(%d+)%s*/%s*(%d+)",
        },
        StaleAfter = 6,            -- s without a successful read before doubting
    },

    Targets = {
        ScanRadius = 1500,         -- radius for collecting candidate targets
        -- A mob whose max health exceeds this is treated as a boss and
        -- excluded, unless the active quest names it explicitly.
        BossHealthThreshold = 20000,
        MinHealth = 1,
        -- A target outside the chosen spawn region is ignored: this is what
        -- stops the neighbouring zone's mobs from being pulled in.
        RegionSlack = 1.6,         -- multiplier on the region radius
    },

    Cluster = {
        Radius = 140,              -- grouping radius for a pack of mobs
        MinSize = 1,               -- smallest group kept
        DistanceWeight = 0.6,      -- weight of distance in the score
        DensityWeight = 1.0,       -- weight of density in the score
        RefreshInterval = 8,       -- s between region recomputations
    },

    Bring = {
        -- Collection radius. Beyond it the mob is not teleported across the
        -- map: the PLAYER moves instead (see PullLimit).
        Radius = 260,
        PullLimit = 400,           -- distance past which we travel instead
        Height = 12,               -- height of the combat point below the player
        Interval = 0.1,            -- s between repositionings
        SlotSpacing = 7,           -- distance between two mob slots
        MaxTargets = 6,            -- slots available around the anchor
        DeadZone = 5,              -- inside this, the mob is left alone
        AnchorRefresh = 1.5,       -- s before the anchor is recomputed
    },

    Anchor = {
        Height = 18,               -- flight height above the ground
        ProbeDepth = 400,          -- reach of the downward probe ray
        MinGroundClearance = 6,    -- minimum clearance above ground
        WaterLevel = 2,            -- Y below which we consider it water
        MaxDriftFromRegion = 220,  -- max drift from the region centre
    },

    Travel = {
        ArriveDistance = 12,       -- distance at which we count as arrived
        QuestGiverDistance = 8,    -- interaction distance with a giver
        StuckDistance = 4,         -- minimum expected progress per check
        StuckWindow = 3,           -- s without progress before declaring a block
        FarEntranceDistance = 10000, -- beyond this: go through requestEntrance
    },

    Combat = {
        EngageTimeout = 8,         -- s without damage before dropping a target
        AttackDelay = 0.1,
        ReacquireDelay = 0.25,
    },

    Recovery = {
        MaxLocalAttempts = 3,      -- local rescans before escalating
        MaxRedetects = 2,          -- full re-detections before a server hop
        Cooldown = 1.5,            -- s between attempts
        HopAfterFailures = 6,      -- cumulative failures before hopping
    },

    CDK = {
        MinLevel = 2200,
        MinYamaMastery = 350,
        MinTushitaMastery = 350,
        TrialTimeout = 120,        -- s per trial before recovery
        ScanInterval = 2,
    },

    Boss = {
        SearchRadius = 3000,
        RespawnPoll = 10,          -- s between respawn checks
        KillConfirmDelay = 1.5,
    },
}
