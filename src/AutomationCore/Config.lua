--=============================================================================
-- CONFIG — reglages de l'AutomationCore
--=============================================================================
--  Tout nombre ajustable vit ici. Aucune constante magique dans les modules :
--  regler le comportement ne doit jamais demander de relire un algorithme.
--=============================================================================

return {
    -- Cadence de la boucle de perception. Le scan complet du Workspace est
    -- cher : on l'espace, et on le resserre pendant le combat ou l'etat
    -- change vite.
    Perception = {
        IdleInterval = 2.0,        -- s entre deux tours hors combat
        CombatInterval = 0.4,      -- s entre deux tours en combat
        QuestPollInterval = 0.5,   -- s entre deux lectures de l'etat de quete
        MaxScanPerTick = 400,      -- instances inspectees par tour, au maximum
    },

    Quest = {
        -- Motifs de lecture de l'objectif, essayes dans l'ordre. Deplacer un
        -- motif ou en ajouter un ne demande pas de toucher au code.
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
        StaleAfter = 6,            -- s sans lecture reussie avant de douter
    },

    Targets = {
        ScanRadius = 1500,         -- rayon de collecte des cibles candidates
        -- Un mob dont la vie max depasse ce seuil est traite comme un boss et
        -- exclu, sauf si la quete active le designe explicitement.
        BossHealthThreshold = 20000,
        MinHealth = 1,
        -- Une cible hors de la region de spawn retenue est ignoree : c'est ce
        -- qui empeche d'aspirer les mobs de la zone voisine.
        RegionSlack = 1.6,         -- multiplicateur du rayon de region
    },

    Cluster = {
        Radius = 140,              -- rayon de regroupement d'un paquet de mobs
        MinSize = 1,               -- taille minimale d'un groupe retenu
        DistanceWeight = 0.6,      -- poids de l'eloignement dans le score
        DensityWeight = 1.0,       -- poids de la densite dans le score
        RefreshInterval = 8,       -- s entre deux recalculs de region
    },

    Bring = {
        -- Rayon de collecte. Au-dela, on ne teleporte pas le mob a travers la
        -- carte : on rapproche le JOUEUR (voir PullLimit).
        Radius = 260,
        PullLimit = 400,           -- distance au-dela de laquelle on voyage
        Height = 12,               -- hauteur du point de combat sous le joueur
        Interval = 0.1,            -- s entre deux repositionnements
        SlotSpacing = 7,           -- distance entre deux emplacements de mob
        MaxTargets = 6,            -- emplacements disponibles autour de l'ancre
        DeadZone = 5,              -- en deca, on ne retouche pas le mob
        AnchorRefresh = 1.5,       -- s avant recalcul du point d'ancrage
    },

    Anchor = {
        Height = 18,               -- hauteur de vol au-dessus du sol
        ProbeDepth = 400,          -- portee du rayon de sondage vers le bas
        MinGroundClearance = 6,    -- garde au sol minimale
        WaterLevel = 2,            -- Y en dessous duquel on considere l'eau
        MaxDriftFromRegion = 220,  -- eloignement max du centre de region
    },

    Travel = {
        ArriveDistance = 12,       -- distance a laquelle on se considere arrive
        QuestGiverDistance = 8,    -- distance d'interaction avec un donneur
        StuckDistance = 4,         -- deplacement minimal attendu par controle
        StuckWindow = 3,           -- s d'immobilite avant de declarer un blocage
        FarEntranceDistance = 10000, -- au-dela : passage par requestEntrance
    },

    Combat = {
        EngageTimeout = 8,         -- s sans degat avant d'abandonner une cible
        AttackDelay = 0.1,
        ReacquireDelay = 0.25,
    },

    Recovery = {
        MaxLocalAttempts = 3,      -- rescans locaux avant d'escalader
        MaxRedetects = 2,          -- redetections completes avant server hop
        Cooldown = 1.5,            -- s entre deux tentatives
        HopAfterFailures = 6,      -- echecs cumules avant changement de serveur
    },

    CDK = {
        MinLevel = 2200,
        MinYamaMastery = 350,
        MinTushitaMastery = 350,
        TrialTimeout = 120,        -- s par epreuve avant recuperation
        ScanInterval = 2,
    },

    Boss = {
        SearchRadius = 3000,
        RespawnPoll = 10,          -- s entre deux verifications de respawn
        KillConfirmDelay = 1.5,
    },
}
