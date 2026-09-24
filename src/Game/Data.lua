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

-- Sea 3, Tiki Outpost: the Tyrant of the Skies' island.
Data.TYRANT_MOBS = { "Isle Champion", "Serpent Hunter", "Skull Slayer", "Sun-kissed Warrior" }
Data.TYRANT = "Tyrant of the Skies"
-- They drop the Conjured Cocoa the Sweet Chalice needs (Dough King's summon).
Data.COCOA_MOBS = { "Cocoa Warrior", "Chocolate Bar Battler" }

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

-- Island positions per sea (x, y, z), used when an island's marker in
-- workspace._WorldOrigin.Locations has not streamed in.
Data.ISLANDS = {
    [1] = {
        ["Start Island"] = { 1071.3, 16.3, 1426.9 },
        ["Marine Start"] = { -2573.3, 6.9, 2047.0 },
        ["Middle Town"] = { -655.8, 7.9, 1436.7 },
        ["Jungle"] = { -1249.8, 11.9, 341.4 },
        ["Pirate Village"] = { -1122.3, 4.8, 3855.9 },
        ["Desert"] = { 1094.1, 6.5, 4192.9 },
        ["Frozen Village"] = { 1198.0, 27.0, -1211.7 },
        ["MarineFord"] = { -4505.4, 20.7, 4260.6 },
        ["Colosseum"] = { -1428.4, 7.4, -3014.4 },
        ["Sky 1st Floor"] = { -4970.2, 717.7, -2622.4 },
        ["Sky 2st Floor"] = { -4813.0, 903.7, -1912.7 },
        ["Sky 3st Floor"] = { -7952.3, 5545.5, -320.7 },
        ["Prison"] = { 4854.2, 5.7, 740.2 },
        ["Magma Village"] = { -5231.8, 8.6, 8467.9 },
        ["UndeyWater City"] = { 61163.9, 11.8, 1819.8 },
        ["Fountain City"] = { 5132.7, 4.5, 4037.9 },
        ["House Cyborg's"] = { 6262.7, 71.3, 3998.2 },
        ["Shank's Room"] = { -1442.2, 29.9, -28.4 },
        ["Mob Island"] = { -2850.2, 7.4, 5355.0 },
    },
    [2] = {
        ["First Spot"] = { 82.9, 18.1, 2835.0 },
        ["Flamingo Mansion"] = { -390.1, 331.9, 673.5 },
        ["Flamingo Room"] = { 2302.2, 15.2, 663.8 },
        ["Green bit"] = { -2372.1, 73.0, -3166.5 },
        ["Cafe"] = { -385.3, 73.0, 297.4 },
        ["Factroy"] = { 430.4, 210.0, -432.5 },
        ["Colosseum"] = { -1836.6, 44.6, 1360.3 },
        ["Ghost Island"] = { -5571.8, 195.2, -795.4 },
        ["Ghost Island 2nd"] = { -5931.8, 5.2, -1189.7 },
        ["Snow Mountain"] = { 1384.7, 453.6, -4990.1 },
        ["Hot and Cold"] = { -6027.0, 14.7, -5072.0 },
        ["Magma Side"] = { -5478.4, 16.0, -5246.9 },
        ["Cursed Ship"] = { 902.1, 124.8, 33071.8 },
        ["Frosted Island"] = { 5400.4, 28.2, -6237.0 },
        ["Forgotten Island"] = { -3043.3, 238.9, -10191.6 },
        ["Usoapp Island"] = { 4748.8, 8.4, 2849.6 },
        ["Raids Low"] = { -5555.0, 329.1, -5930.3 },
        ["Minisky"] = { -260.4, 49325.7, -35259.3 },
    },
    [3] = {
        ["Port Town"] = { -287.0, 30.0, 5388.0 },
        ["Hydar Island"] = { 3399.3, 72.4, 1573.0 },
        ["Room Enma/Yama & Secret Temple"] = { 5247.0, 7.0, 1097.0 },
        ["House Hydar Island"] = { 5245.0, 602.0, 251.0 },
        ["Great Tree"] = { 2443.0, 36.0, -6573.0 },
        ["Castle on the sea"] = { -5500.0, 314.0, -2855.0 },
        ["Mansion"] = { -12548.0, 337.0, -7481.0 },
        ["Floating Turtle"] = { -10016.0, 332.0, -8326.0 },
        ["Haunted Castle"] = { -9509.3, 142.1, 5535.2 },
        ["Peanut Island"] = { -2131.0, 38.0, -10106.0 },
        ["Ice Cream Island"] = { -950.0, 59.0, -10907.0 },
        ["CakeLoaf"] = { -1762.0, 38.0, -11878.0 },
        ["Tiki"] = { -16204.1, 9.1, 479.2 },
    },
}

-- Fighting styles: the CommF_ call(s) that buy them and the teacher NPC to
-- stand next to.
Data.FIGHTING_STYLES = {
    { name = "Black Leg", npc = "Dark Step Teacher", calls = { { "BuyBlackLeg" } } },
    { name = "Electro", npc = "Mad Scientist", calls = { { "BuyElectro" } } },
    { name = "Fishman Karate", npc = "Water Kung-fu Teacher", calls = { { "BuyFishmanKarate" } } },
    { name = "Dragon Claw", npc = "Sabi", calls = { { "BlackbeardReward", "DragonClaw", "1" }, { "BlackbeardReward", "DragonClaw", "2" } } },
    { name = "Superhuman", npc = "Martial Arts Master", calls = { { "BuySuperhuman" } } },
    { name = "Death Step", npc = "Phoeyu, the Reformed", calls = { { "BuyDeathStep" } } },
    { name = "Sharkman Karate", npc = "Sharkman Teacher", calls = { { "BuySharkmanKarate" } } },
    { name = "Electric Claw", npc = "Previous Hero", calls = { { "BuyElectricClaw" } } },
    { name = "Dragon Talon", npc = "Uzoth", calls = { { "BuyDragonTalon" } } },
    { name = "Godhuman", npc = "Ancient Monk", calls = { { "BuyGodhuman" } } },
    { name = "Sanguine Art", npc = "Shafi", calls = { { "BuySanguineArt" } } },
}

function Data.fightingStyleNames()
    local names = {}
    for _, style in ipairs(Data.FIGHTING_STYLES) do names[#names + 1] = style.name end
    return names
end

function Data.fightingStyle(name)
    for _, style in ipairs(Data.FIGHTING_STYLES) do
        if style.name == name then return style end
    end
    return nil
end

Data.STATS = { "Melee", "Defense", "Sword", "Gun", "Demon Fruit" }
Data.STAT_MAX = 2800

Data.ELITE_HUNTERS = { "Deandre", "Urban", "Diablo" }

-- Lighting moon textures: full moon, and the night before it.
Data.MOON_FULL = "http://www.roblox.com/asset/?id=9709149431"
Data.MOON_NEXT = "http://www.roblox.com/asset/?id=9709149052"

Data.CODES = {
    "EASTEREXP", "BANEXPLOIT", "NOMOREHACKS", "WildDares",
    "BossBuild", "GetPranked", "EARN_FRUITS", "Sub2UncleKizaru",
    "FIGHT4FRUIT", "kittgaming", "TRIPLEABUSE", "Sub2CaptainMaui",
    "Sub2Fer999", "Enyu_is_Pro", "Magicbus", "JCWK",
    "Starcodeheo", "Bluxxy", "SUB2GAMERROBOT_EXP1", "Sub2NoobMaster123",
    "Sub2Daigrock", "Axiore", "TantaiGaming", "StrawHatMaine",
    "Sub2OfficialNoobie", "TheGreatAce", "SEATROLLIN", "24NOADMIN",
    "ADMIN_TROLL", "NEWTROLL", "SECRET_ADMIN", "staffbattle",
    "NOEXPLOIT", "NOOB2ADMIN", "CODESLIDE", "fruitconcepts",
}

return Data
