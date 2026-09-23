--=============================================================================
-- DATA — game facts the game does not expose in a module
--=============================================================================
--  Everything else is read live (quests, NPCs, spawns). These few lists are
--  not available anywhere in the game data, so they are carried over from
--  the reference script, which keeps them up to date with the game.
--=============================================================================

local Data = {}

-- The CommF_ action that moves the player to each sea.
Data.TRAVEL = {
    [1] = "TravelMain",
    [2] = "TravelDressrosa",
    [3] = "TravelZou",
}

-- Material -> the mobs that drop it, and the sea they live in.
Data.MATERIALS = {
    ["Angel Wings"] = { sea = 1, mobs = { "God's Guard", "Shanda", "Royal Squad", "Royal Soldier" } },
    Ectoplasm = { sea = 2, mobs = { "Ship Deckhand", "Ship Engineer", "Ship Steward", "Ship Officer", "Cursed Captain" } },
    ["Magma Ore"] = { sea = 2, mobs = { "Lava Pirate", "Magma Ninja" } },
    ["Radioactive Material"] = { sea = 2, mobs = { "Factory Staff" } },
    ["Vampire Fang"] = { sea = 2, mobs = { "Vampire" } },
    ["Mystic Droplet"] = { sea = 2, mobs = { "Sea Soldier", "Water Fighter" } },
    Leather = { sea = 3, mobs = { "Jungle Pirate", "Musketeer Pirate" } },
    ["Scrap Metal"] = { sea = 3, mobs = { "Jungle Pirate" } },
    ["Fish Tail"] = { sea = 3, mobs = { "Fishman Raider", "Fishman Captain" } },
    ["Mini Tusk"] = { sea = 3, mobs = { "Mythological Pirate" } },
    Gunpowder = { sea = 3, mobs = { "Pistol Billionaire" } },
    ["Demonic Wisp"] = { sea = 3, mobs = { "Demonic Soul" } },
    ["Dragon Scale"] = { sea = 3, mobs = { "Dragon Crew Archer", "Dragon Crew Warrior" } },
    ["Conjured Cocoa"] = { sea = 3, mobs = { "Cocoa Warrior", "Chocolate Bar Battler" } },
    Bones = { sea = 3, mobs = { "Reborn Skeleton", "Demonic Soul", "Living Zombie", "Posessed Mummy" } },
}

function Data.materialNames()
    local names = {}
    for name in pairs(Data.MATERIALS) do names[#names + 1] = name end
    table.sort(names)
    return names
end

-- Sea 3, Haunted Castle.
Data.BONE_MOBS = { "Reborn Skeleton", "Living Zombie", "Demonic Soul", "Posessed Mummy" }

-- Sea 3, Cake Land: killing these makes Cake Prince (then Dough King) spawn.
Data.CAKE_MOBS = { "Cookie Crafter", "Cake Guard", "Baking Staff", "Head Baker" }
Data.CAKE_BOSSES = { "Cake Prince", "Dough King" }

Data.BOSSES = {
    "Gorilla King", "Bobby", "The Saw", "Yeti", "Mob Leader", "Vice Admiral",
    "Saber Expert", "Warden", "Chief Warden", "Swan", "Magma Admiral",
    "Fishman Lord", "Wysper", "Thunder God", "Cyborg", "Ice Admiral", "Diamond",
    "Jeremy", "Orbitus", "Don Swan", "Smoke Admiral", "Awakened Ice Admiral",
    "Tide Keeper", "Stone", "Island Empress", "Kilo Admiral", "Captain Elephant",
    "Beautiful Pirate", "Longma", "Cake Queen", "GreyBeard", "Order",
    "Cursed Captain", "Darkbeard", "Soul Reaper", "rip_indra True Form",
    "Mihawk", "Cake Prince", "Dough King",
}

Data.SKILL_KEYS = { "Z", "X", "C", "V", "F" }

return Data
