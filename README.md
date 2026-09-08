# Strawberry Hub

Script Blox Fruits — auto farm, combat, matériaux, téléport, shop, anti-détection.
Interface native (aucune dépendance externe), pensée mobile.

## Loader

Colle ceci dans ton exécuteur :

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/redslayer34/strawberry-hub/main/StrawberryHub.lua"))()
```

## Développement

`StrawberryHub.lua` est un **artefact de build**, pas la source. Ne l'édite pas :
tes modifications seraient écrasées au prochain packaging.

```
src/                      la source
├── main.lua              point d'entrée du hub
├── uidemo.lua            point d'entrée de la démo UI
├── Runtime/Legacy.lua    runtime historique (shop, téléport, moteur de combat)
├── AutomationCore/       l'architecture d'automatisation
└── UI/                   la bibliothèque d'interface
tools/
├── pack.py               bundle src/ puis produit une distribution
├── unpack.py             opération inverse, pour inspecter un ancien build
├── test.py               lance les suites de tests hors du jeu
├── stubs.lua             environnement Roblox minimal
├── uistubs.lua           types et services nécessaires à la UI
├── tests.lua             assertions AutomationCore
└── uitests.lua           assertions UI
dist/StrawberryUI.lua     bibliothèque UI seule, lisible et autonome
```

```bash
python3 tools/test.py     # 262 assertions, sans Roblox
python3 tools/test.py ui  # une seule suite
python3 tools/pack.py     # régénère StrawberryHub.lua
```

Chaque fichier sous `src/` devient un module adressé par son chemin pointé
(`src/AutomationCore/Log.lua` → `AutomationCore.Log`), résolu par un `require`
embarqué dans le bundle. Le bundler n'embarque que les modules réellement
atteignables depuis le point d'entrée, et échoue au build si un `require`
désigne un module inexistant.

## AutomationCore

Le farm ne repose plus sur une table de CFrame codés en dur. Il détecte l'état
réel du jeu à chaque tour, sur chaque serveur.

```
AutomationCore
├── Perception          SeaDetector · IslandDetector · QuestDetector
│                       QuestGiverResolver · EnemyScanner · SpawnClusterResolver
├── Movement            TravelController · QuestTravel · TargetTravel · SafeCombatAnchor
├── Combat              TargetValidator · BringController · AttackController
│                       CombatPositionController
├── Farming             QuestFarm · BossFarm · MasteryFarm · MaterialFarm
│                       ServerHop · SpecialFarm · RoutePlanner · TargetedFarm
├── Recovery            RecoveryController
└── SpecialObjectives   CDKController
```

### Hiérarchie de confiance

Toute information est classée par fiabilité. Une ancienne coordonnée n'est
jamais une vérité : c'est le dernier recours, et il est tracé comme tel.

| Niveau | Source | Exemple |
|---|---|---|
| 1 | état réel de la quête | `Defeat 8 Desert Bandits` lu dans l'UI |
| 2 | entité présente | le mob existe dans `workspace.Enemies` |
| 3 | identité d'un PNJ | nom, invite d'interaction, étiquette |
| 4 | cluster de spawn détecté | le paquet de mobs calculé maintenant |
| 5 | mémoire de CE serveur | donnée apprise pendant la session |
| 6 | coordonnée figée | la table historique, en dernier recours |

### Règle absolue sur les cibles

La quête active est la seule source de vérité. `TargetValidator` applique dix
contrôles, dont une **égalité stricte de formes canoniques** — jamais de
`string.find`, jamais de correspondance partielle.

La normalisation est permissive (`Desert Bandits` → `desert bandit`,
`Fishmen Warriors` → `fishman warrior`) mais elle ne sert qu'à produire une
forme comparable. `Bandit` ne correspond pas à `Desert Bandit`, et
`Desert Bandit Chief` non plus.

Un boss n'entre jamais dans un bring ordinaire : il faut que la quête active
le désigne explicitement.

Le flux de sélection est imposé :

```
QuestDetector → TargetSelector → TargetValidator → BringController
```

`BringController` ne décide de rien — il reçoit une liste déjà filtrée.

### Bring

Les mobs sont répartis sur des emplacements distincts autour d'une ancre
recalculée régulièrement, jamais empilés sur un même CFrame. L'emplacement
d'un mob mort est rendu au suivant.

Un mob trop éloigné n'est pas téléporté à travers la carte : c'est le joueur
qui se rapproche (`PullLimit`), puis la zone est rescannée.

Toute position candidate est validée avant usage : sous la carte, dans l'eau,
dans un obstacle, ou trop loin de la zone de spawn sont refusées.

### Machine à états

Chaque état déclare son entrée, son timeout, sa condition de succès, sa
condition d'échec et son état suivant. Aucun état ne peut bloquer le farm
indéfiniment.

```
IDLE → CHECK_REQUIREMENTS → DETECT_SEA → DETECT_ISLAND → DETECT_QUEST
     → FIND_QUEST_GIVER → TRAVEL_TO_QUEST → ACCEPT_QUEST
     → SCAN_TARGETS → ACTIVATE_SPAWN → BUILD_TARGET_GROUP
     → BRING_TARGETS → ATTACK → CHECK_PROGRESS → TURN_IN
     → RECOVERY · SERVER_HOP · SPECIAL_OBJECTIVE
```

### Récupération

Échelle d'escalade, toujours dans cet ordre : rescan local → recalcul des
données → reprise de l'état courant → retour à la détection → changement de
serveur **en dernier recours seulement**.

### CDK

`CDKController` est totalement indépendant de `QuestFarm` ; les deux se
branchent sur le même core par l'interface d'objectif spécial. Il détecte
l'épreuve **réellement active** plutôt que de supposer un ordre figé, ce qui
permet de reprendre un puzzle déjà entamé.

Pré-requis vérifiés avant démarrage : niveau 2200+, Yama et Tushita obtenues,
maîtrise 350+ sur chacune.

> Les noms d'instances candidats du puzzle (table `SIGNALS`) sont à confirmer
> serveur en main. C'est volontairement une table de données : corriger un nom
> ne demande de toucher à aucun algorithme.

### Journal

Une catégorie par sous-système, coupable indépendamment :

```
[Quest] Target = Desert Bandit
[Quest] Progress = 3/8
[Target] Found 6 valid targets
[Bring] Building group of 5
[Combat] Started
[Quest] Complete
```

## Bibliothèque UI

Interface sombre et compacte, sans dépendance externe. Utilisable seule :

```lua
loadstring(game:HttpGet(".../dist/StrawberryUI.lua"))()
```

Ou reconstruite depuis la source :

```bash
python3 tools/pack.py --entry uidemo --bundle-only dist/StrawberryUI.lua
```

```
UI
├── Theme            palette centrale, applicable à chaud
├── Utility          fabrique d'instances, Maid, animations
├── Input            clic / survol / drag, souris et tactile
├── Window           barre de titre, sidebar, contenu, overlay
├── Tab              onglet de sidebar + page
├── Section          titre + pile de composants
├── Notification     pile en haut à droite
└── Components       Row · Button · Toggle · Dropdown · Slider · Label · Divider
```

### API

```lua
local UI = loadstring(game:HttpGet(".../dist/StrawberryUI.lua"))()

local Window = UI:CreateWindow({ Title = "Blox Fruits", Subtitle = "v1" })
local Tab     = Window:CreateTab({ Name = "Farm", Icon = "rbxassetid://..." })
local Section = Tab:CreateSection({ Name = "Auto Farm" })

Section:CreateToggle({ Name = "Auto Farm", Default = false,
    Callback = function(v) print(v) end })

Section:CreateDropdown({ Name = "Mode", Values = { "Level", "Boss" },
    Default = "Level", Callback = function(v) print(v) end })

Section:CreateSlider({ Name = "Distance", Min = 5, Max = 100,
    Default = 20, Rounding = 0, Callback = function(v) print(v) end })

Section:CreateButton({ Name = "Start", Arrow = true,
    Callback = function() print("go") end })
```

| Objet | Fonctions publiques |
|---|---|
| `UI` | `CreateWindow` `Notify` `SetTheme` `GetTheme` `ResetTheme` `ClearNotifications` `Destroy` |
| `Window` | `CreateTab` `SelectTab` `GetTab` `Show` `Hide` `Toggle` `IsVisible` `Close` `ToggleMinimize` `IsMinimized` `SetTitle` `SetSubtitle` `SetSize` `SetPosition` `Destroy` |
| `Tab` | `CreateSection` `Show` `Hide` `IsActive` `SetName` `Destroy` |
| `Section` | `CreateButton` `CreateToggle` `CreateDropdown` `CreateSlider` `CreateLabel` `CreateDivider` `SetName` `Destroy` |
| `Button` | `SetText` `SetDescription` `SetCallback` `Destroy` |
| `Toggle` | `SetValue` `GetValue` `SetCallback` `SetText` `Destroy` |
| `Dropdown` | `SetValues` `SetValue` `GetValue` `GetValues` `Refresh` `Open` `Close` `Toggle` `IsOpen` `SetCallback` `Destroy` |
| `Slider` | `SetValue` `GetValue` `SetMin` `SetMax` `SetCallback` `SetText` `Destroy` |
| `Label` | `SetText` `GetText` `Destroy` |

`UI:Notify({ Title, Content, Duration })` empile les notifications en haut à
droite ; elles ne se superposent pas.

`UI:SetTheme({ Accent = ... })` fusionne la palette et **repeint sans
reconstruire** : les toggles gardent leur valeur, l'onglet actif reste actif,
la fenêtre ne bouge pas. La fusion est partielle — passer une seule clé ne
vide pas le reste.

### Choix notables

**Aucune boucle.** Le drag et le slider n'ouvrent leurs connexions de suivi
qu'au moment de l'appui et les referment au relâchement. Au repos, une fenêtre
ne coûte qu'une connexion `InputBegan` sur sa barre de titre — pas de
`RenderStepped`.

**Les menus déroulants vivent dans une couche à part.** Enfant de la section,
un menu serait rogné par le `ScrollingFrame`. Ici la position est calculée en
coordonnées écran, bornée, et le menu s'ouvre vers le haut s'il n'y a pas la
place en bas.

**Changer d'onglet ne reconstruit rien** — juste `Visible`. C'est ce qui
préserve l'état des composants et la position de défilement.

**Le Maid rend `Destroy()` fiable.** Chaque composant y dépose ses instances,
ses connexions et son peintre de thème. `Window:Destroy()` libère toute la
descendance ; `UI:Destroy()` ne laisse aucun peintre ni aucune connexion
d'entrée.

**Tactile de plein droit.** Souris et doigt passent par les mêmes chemins ; la
zone de saisie du slider occupe toute la hauteur de la ligne, pas les 4 pixels
de la barre visible.

**Responsive** par un `UIScale` unique piloté par la taille du viewport (borné
à 0.62), sidebar à 25 % avec plancher et plafond en pixels.

### Dépendances

Aucune. Uniquement `TweenService`, `UserInputService` et `Players`. `gethui()`
est utilisé s'il existe, avec repli sur `PlayerGui`.

## Avertissement

Automatisation contraire aux conditions d'utilisation de Roblox / Blox Fruits.
Risque de bannissement du compte. Utilisation à tes propres risques.
