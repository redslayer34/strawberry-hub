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

-- Fighting styles: the CommF_ call(s) that buy them, the teacher NPC to
-- stand next to (`at`: where it stands in each sea, the Teddy Kaitun's
-- table, for when the NPC is not loaded), the names the inventory may list them under (the game
-- keeps the old internal names for the first styles, Vxeze's MeleeInfo) and
-- the sea their teacher is in.
Data.FIGHTING_STYLES = {
    { name = "Black Leg", npc = "Dark Step Teacher", calls = { { "BuyBlackLeg" } },
        inv = { "Black Leg", "Dark Step" }, sea = 1,
        at = { Vector3.new(-985.919, 13.782, 3989.196), Vector3.new(-4754.082, 35.072, -4846.347),
            Vector3.new(-5046.673, 371.554, -3181.369) } },
    { name = "Electro", npc = "Mad Scientist", calls = { { "BuyElectro" } },
        inv = { "Electro", "Electric" }, sea = 1,
        at = { Vector3.new(-5386.988, 13.553, -2146.912), Vector3.new(-4867.061, 35.072, -4764.177),
            Vector3.new(-4992.725, 314.546, -3197.635) } },
    { name = "Fishman Karate", npc = "Water Kung-fu Teacher", calls = { { "BuyFishmanKarate" } },
        inv = { "Fishman Karate", "Water Kung Fu" }, sea = 1,
        at = { Vector3.new(61580.652, 18.901, 985.204), Vector3.new(-4957.67, 35.071, -4665.6),
            Vector3.new(-5023.662, 371.343, -3192.383) } },
    { name = "Dragon Claw", npc = "Sabi", calls = { { "BlackbeardReward", "DragonClaw", "1" }, { "BlackbeardReward", "DragonClaw", "2" } },
        inv = { "Dragon Claw", "Dragon Breath" }, sea = 2 },
    { name = "Superhuman", npc = "Martial Arts Master", calls = { { "BuySuperhuman" } },
        inv = { "Superhuman" }, sea = 2,
        at = { [2] = Vector3.new(1378.382, 247.458, -5191.358), [3] = Vector3.new(-5004.467, 371.343, -3196.912) } },
    { name = "Death Step", npc = "Phoeyu, the Reformed", calls = { { "BuyDeathStep" } },
        inv = { "Death Step" }, sea = 2,
        at = { [2] = Vector3.new(6356.018, 297.667, -6761.593), [3] = Vector3.new(-4995.035, 314.546, -3222.354) } },
    { name = "Sharkman Karate", npc = "Sharkman Teacher", calls = { { "BuySharkmanKarate" } },
        inv = { "Sharkman Karate" }, sea = 2,
        at = { [2] = Vector3.new(-2600.607, 238.877, -10314.496), [3] = Vector3.new(-4972.77, 314.546, -3219.336) } },
    { name = "Electric Claw", npc = "Previous Hero", calls = { { "BuyElectricClaw" } },
        inv = { "Electric Claw" }, sea = 3, at = { [3] = Vector3.new(-10371.693, 331.684, -10127.267) } },
    { name = "Dragon Talon", npc = "Uzoth", calls = { { "BuyDragonTalon" } },
        inv = { "Dragon Talon" }, sea = 3, at = { [3] = Vector3.new(5663.318, 1211.308, 865.413) } },
    { name = "Godhuman", npc = "Ancient Monk", calls = { { "BuyGodhuman" } },
        inv = { "Godhuman", "God Human" }, sea = 3, at = { [3] = Vector3.new(-13775.168, 334.652, -9882.374) } },
    { name = "Sanguine Art", npc = "Shafi", calls = { { "BuySanguineArt" } },
        inv = { "Sanguine Art", "SanguineArt" }, sea = 3 },
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

-- Codes (most give 2x experience for a while): Banana's list and the Teddy
-- Kaitun's, without duplicates. Expired ones are only refused.
Data.CODES = {
    "EASTEREXP", "BANEXPLOIT", "NOMOREHACKS", "WildDares", "BossBuild", "GetPranked", "EARN_FRUITS",
    "Sub2UncleKizaru", "FIGHT4FRUIT", "kittgaming", "TRIPLEABUSE", "Sub2CaptainMaui", "Sub2Fer999",
    "Enyu_is_Pro", "Magicbus", "JCWK", "Starcodeheo", "Bluxxy", "SUB2GAMERROBOT_EXP1",
    "Sub2NoobMaster123", "Sub2Daigrock", "Axiore", "TantaiGaming", "StrawHatMaine",
    "Sub2OfficialNoobie", "TheGreatAce", "SEATROLLIN", "24NOADMIN", "ADMIN_TROLL", "NEWTROLL",
    "SECRET_ADMIN", "staffbattle", "NOEXPLOIT", "NOOB2ADMIN", "CODESLIDE", "fruitconcepts",
    "GAMERROBOT_YT", "FUDD10", "fudd10_v2", "BIGNEWS", "UPD16", "3BVISITS", "ADMINGIVEAWAY",
    "GAMER_ROBOT_1M", "15B_BESTBROTHERS", "DEVSCOOKING", "krazydares", "KITT_RESET",
    "SUB2GAMERROBOT_RESET1", "NOMOREHACK", "GIFTING_HOURS",
}

-- Where each quest mob lives (Teddy Kaitun's table): the level farm goes
-- there when no spawn point is streamed in. The quest giver is no good for
-- that: the Shandas' giver stands on the lower Skylands while they live on
-- the Upper Skylands, so waiting above it never loaded them.
Data.MOB_SPOTS = {
    Bandit = Vector3.new(1137.2, 12.7, 1594.2),
    Trainee = Vector3.new(-2722.6, 31.8, 2090),
    Monkey = Vector3.new(-1592.6, 27.7, 137.2),
    Gorilla = Vector3.new(-1313.4, 18.2, -548.4),
    ["The Gorilla King"] = Vector3.new(-1193.9, 10.7, -549.8),
    Pirate = Vector3.new(-1140.6, 22.4, 3975.8),
    Brute = Vector3.new(-1203.8, 28.4, 4369.7),
    Bobby = Vector3.new(-1120.5, 54.7, 4121.2),
    Chef = Vector3.new(-1120.5, 54.7, 4121.2),
    ["Desert Bandit"] = Vector3.new(923.7, 7.6, 4514),
    ["Desert Officer"] = Vector3.new(1572.9, 14.4, 4159),
    ["Snow Bandit"] = Vector3.new(1418, 76.7, -1437),
    Snowman = Vector3.new(1197, 96.1, -1603),
    Yeti = Vector3.new(1185, 106, -1518),
    ["Chief Petty Officer"] = Vector3.new(-4809.4, 12.6, 4302.2),
    ["Vice Admiral"] = Vector3.new(-5010.8, 15.1, 4383.7),
    Greybeard = Vector3.new(-4953.1, 13.9, 4159.8),
    ["Sky Bandit"] = Vector3.new(-5091.6, 280.7, -1019.2),
    ["Dark Master"] = Vector3.new(-5292.5, 504.9, -350.8),
    Prisoner = Vector3.new(5271.6, 7.1, 467.9),
    ["Dangerous Prisoner"] = Vector3.new(5278.3, 16.1, 875.1),
    ["Ruthless Prisoner"] = Vector3.new(5330, 25, 777),
    Warden = Vector3.new(5623.2, 1.4, 733.8),
    ["Chief Warden"] = Vector3.new(5230, 10, 750),
    Swan = Vector3.new(5230, 10, 750),
    ["Toga Warrior"] = Vector3.new(-1745.1, 10.2, -2705),
    Gladiator = Vector3.new(-1175.4, 11.6, -3213.7),
    ["Military Soldier"] = Vector3.new(-5409.1, 17.1, 8499.2),
    ["Military Spy"] = Vector3.new(-5841.6, 76.9, 8772.9),
    ["Magma General"] = Vector3.new(-5625.7, 55.4, 8623),
    ["Magma Admiral"] = Vector3.new(-5625.7, 55.4, 8623),
    ["Fishman Warrior"] = Vector3.new(60792.9, 24.2, 1361.5),
    ["Fishman Commando"] = Vector3.new(61928.2, 24.6, 1331.1),
    ["Fishman Lord"] = Vector3.new(61352.9, 67.2, 1029.1),
    ["God's Guard"] = Vector3.new(-4240.6, 1088.9, -403.7),
    Shanda = Vector3.new(-5975.6, 5469.5, 1800),
    ["Royal Squad"] = Vector3.new(-6798.3, 5551.9, 1213.8),
    ["Royal Soldier"] = Vector3.new(-7064.4, 5541.1, 939.4),
    ["Sky Warlord"] = Vector3.new(-6271.6, 5472.8, 1887.8),
    Wysper = Vector3.new(-6271.6, 5472.8, 1887.8),
    ["Lightning God"] = Vector3.new(-7125.4, 5596.1, 111.5),
    ["Thunder God"] = Vector3.new(-7125.4, 5596.1, 111.5),
    ["Galley Pirate"] = Vector3.new(5571.6, 78.4, 4009.8),
    ["Galley Captain"] = Vector3.new(5409.5, 77.7, 4687),
    Cyborg = Vector3.new(6252.4, 9.3, 4941.4),
    ["Saber Expert"] = Vector3.new(-1527.2, 34.1, -33.2),
    ["The Saw"] = Vector3.new(-690, 15, 1580),
    ["Mob Boss"] = Vector3.new(-2880.7, 6.7, 5430.9),
    Raider = Vector3.new(-628, 52, 2043),
    Mercenary = Vector3.new(-853, 52, 1756),
    Diamond = Vector3.new(-1583, 198, -12),
    ["Swan Pirate"] = Vector3.new(882, 121, 1216),
    ["Factory Staff"] = Vector3.new(295, 73, -56),
    Jeremy = Vector3.new(2316, 449, 787),
    ["Marine Lieutenant"] = Vector3.new(-2726, 73, -2982),
    ["Marine Captain"] = Vector3.new(-1980, 73, -3326),
    Orbitus = Vector3.new(-2116, 73, -3173),
    Fajita = Vector3.new(-2116, 73, -3173),
    Zombie = Vector3.new(-5654, 8, -737),
    Vampire = Vector3.new(-6022, 6, -1303),
    ["Snow Trooper"] = Vector3.new(530, 402, -5347),
    ["Winter Warrior"] = Vector3.new(1178, 430, -5189),
    ["Awakened Ice Admiral"] = Vector3.new(5662, 28, -5983),
    ["Lab Subordinate"] = Vector3.new(-5829, 16, -4445),
    ["Horned Warrior"] = Vector3.new(-6390, 16, -5811),
    ["Smoke Admiral"] = Vector3.new(-5078, 24, -5352),
    ["Magma Ninja"] = Vector3.new(-5459, 22, -5420),
    ["Lava Pirate"] = Vector3.new(-5377, 18, -5126),
    ["Ship Deckhand"] = Vector3.new(1198, 126, 32988),
    ["Ship Engineer"] = Vector3.new(917, 44, 32785),
    ["Ship Steward"] = Vector3.new(916, 130, 33418),
    ["Ship Officer"] = Vector3.new(917, 181, 33355),
    ["Cursed Captain"] = Vector3.new(902, 125, 33072),
    ["Arctic Warrior"] = Vector3.new(6038, 28, -6231),
    ["Snow Lurker"] = Vector3.new(5561, 42, -6812),
    ["Sea Soldier"] = Vector3.new(-3022, 16, -9797),
    ["Water Fighter"] = Vector3.new(-3385, 239, -10542),
    ["Tide Keeper"] = Vector3.new(-3800, 77, -11475),
    ["Don Swan"] = Vector3.new(2284, 15, 804),
    ["Pirate Millionaire"] = Vector3.new(-373, 75, 5550),
    ["Pistol Billionaire"] = Vector3.new(-469, 74, 5904),
    Stone = Vector3.new(-1049, 40, 6791),
    ["Dragon Crew Warrior"] = Vector3.new(6526, 378, 16),
    ["Dragon Crew Archer"] = Vector3.new(6563, 148, -712),
    ["Island Empress"] = Vector3.new(5700, 602, 199),
    ["Female Islander"] = Vector3.new(4692, 745, 800),
    ["Giant Islander"] = Vector3.new(4800, 600, -200),
    ["Kilo Admiral"] = Vector3.new(2889, 74, -7233),
    ["Captain Elephant"] = Vector3.new(-13393, 319, -8423),
    ["Beautiful Pirate"] = Vector3.new(5311, 160, 129),
    ["Marine Commodore"] = Vector3.new(-4800, 330, -2700),
    ["Marine Rear Admiral"] = Vector3.new(-5026, 324, -2996),
    ["Fishman Raider"] = Vector3.new(-10919, 332, -8698),
    ["Fishman Captain"] = Vector3.new(-10993, 332, -8940),
    ["Forest Pirate"] = Vector3.new(-13274, 332, -7926),
    ["Mythological Pirate"] = Vector3.new(-13545, 470, -6917),
    ["Jungle Pirate"] = Vector3.new(-12107, 332, -10665),
    ["Musketeer Pirate"] = Vector3.new(-13290, 397, -9763),
    ["Reborn Skeleton"] = Vector3.new(-8737, 143, 6035),
    ["Living Zombie"] = Vector3.new(-10150, 140, 5930),
    ["Demonic Soul"] = Vector3.new(-9501, 172, 6036),
    ["Posessed Mummy"] = Vector3.new(-9500, 6, 6100),
    ["Soul Reaper"] = Vector3.new(-9522, 316, 6752),
    ["Peanut Scout"] = Vector3.new(-2124, 38, -10194),
    ["Peanut President"] = Vector3.new(-2124, 38, -10194),
    ["Ice Cream Chef"] = Vector3.new(-641, 65, -10719),
    ["Ice Cream Commander"] = Vector3.new(-852, 66, -10932),
    ["Cookie Crafter"] = Vector3.new(-2365, 38, -12099),
    ["Cake Guard"] = Vector3.new(-1591, 38, -12297),
    ["Baking Staff"] = Vector3.new(-1907, 38, -12866),
    ["Head Baker"] = Vector3.new(-1926, 38, -12850),
    ["Cocoa Warrior"] = Vector3.new(233, 75, -12498),
    ["Chocolate Bar Battler"] = Vector3.new(233, 75, -12498),
    ["Sweet Thief"] = Vector3.new(71, 77, -12632),
    ["Candy Rebel"] = Vector3.new(134, 77, -12795),
    ["Candy Pirate"] = Vector3.new(-1345, 16, -14360),
    ["Snow Demon"] = Vector3.new(-1345, 16, -14360),
    ["Cake Prince"] = Vector3.new(-2103, 70, -12165),
    ["Dough King"] = Vector3.new(-2103, 70, -12165),
    Rip_indra = Vector3.new(-5333, 316, -2673),
    ["Isle Outlaw"] = Vector3.new(-16168, 9, 438),
    ["Island Boy"] = Vector3.new(-16450, 9, 748),
    ["Sun-kissed Warrior"] = Vector3.new(-16350, 9, 1000),
    ["Isle Champion"] = Vector3.new(-16529, 108, 749),
}

return Data
