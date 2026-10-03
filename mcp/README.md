# Strawberry MCP — Claude Code ↔ Roblox (Arceus X)

Un serveur MCP qui relie **Claude Code sur ton PC** au **jeu dans ton executor** (Arceus X sur MuMu).
Claude peut alors lire et piloter le jeu lui-même : exécuter du Lua, lire la console, explorer
l'arbre du jeu, lancer **Cobalt** (remote spy) et lire ses logs, charger et suivre le hub / Kaitun.

```
Claude Code ──stdio──> mcp/src/server.js ──HTTP (port 7777, token)──> bridge.lua dans Arceus X
```

## Installation rapide (recommandée)

Dans **PowerShell** (de préférence « Exécuter en tant qu'administrateur », pour ouvrir le port) :

```powershell
irm https://raw.githubusercontent.com/redslayer34/strawberry-hub/claude/repo-exploration-ez26bn/mcp/install.ps1 | iex
```

Il installe Node.js si besoin (winget), met le MCP dans `%USERPROFILE%\StrawberryMCP`, fait
`npm install`, copie `Cobalt.luau` depuis Téléchargements/Bureau s'il le trouve, ouvre le port
7777 (réseau privé), déclare le MCP dans Claude Code (`claude mcp add --scope user strawberry`)
et affiche la ligne à lancer dans Arceus X. Relancer la commande = mise à jour (token et Cobalt
gardés). Ligne Arceus X à nouveau : `npm run loader` dans `%USERPROFILE%\StrawberryMCP`.

Dans le repo cloné, `.mcp.json` déclare aussi le MCP pour Claude Code lancé à la racine du repo.

## Installation manuelle

1. Installe **Node.js 20+** : https://nodejs.org (version LTS).
2. Récupère le repo (branche `claude/repo-exploration-ez26bn`), puis dans un terminal :
   ```
   cd strawberry-hub\mcp
   npm install
   ```
3. Mets ton fichier **`Cobalt.luau`** dans le dossier `mcp\` (il n'est pas dans le repo).
   Ou indique son chemin avec la variable `COBALT_PATH`.
4. Déclare le MCP dans Claude Code :
   ```
   claude mcp add strawberry -- node C:\chemin\vers\strawberry-hub\mcp\src\server.js
   ```
   (avec Cobalt ailleurs : `claude mcp add strawberry -e COBALT_PATH=C:\...\Cobalt.luau -- node ...`)
5. Au premier lancement, **Windows demande d'autoriser Node** sur le réseau : accepte
   (réseau privé), sinon MuMu ne peut pas joindre le PC.

## Connecter le jeu

1. Dans Claude Code, demande « donne-moi le loader » (outil `get_loader`). Il répond une ligne comme :
   ```lua
   loadstring((request or http_request)({Url="http://192.168.1.20:7777/bridge.lua?token=...",Method="GET"}).Body)()
   ```
2. Exécute cette ligne dans **Arceus X**. Une notification « Strawberry MCP — Connected » apparaît.
3. `roblox_status` doit dire `connected: true`.

L'adresse est l'**IP locale du PC** (`ipconfig` → « Adresse IPv4 »). Si la première proposée ne
marche pas, redemande le loader avec la bonne : « get_loader avec l'adresse 192.168.x.x ».
Le token est créé une fois dans `mcp\.bridge-token` : garde-le pour toi.

## Outils

| Outil | Ce qu'il fait |
|---|---|
| `roblox_status` | jeu connecté ? place, mer, joueur, executor, hub/Kaitun/Cobalt chargés |
| `get_loader` | la ligne à exécuter dans Arceus X |
| `execute_lua` | exécute du Luau dans le jeu : valeurs `return`, `print`/`warn`, erreur |
| `get_console` | la console du jeu (prints, warnings, erreurs), filtrable |
| `explore` | l'arbre d'un objet (`game.Workspace.Map`, `Players.LocalPlayer.Data`…) |
| `get_properties` | propriétés et attributs d'un objet |
| `find_instances` | cherche des objets par nom et/ou classe |
| `get_script_source` | source décompilée d'un script (si l'executor a `decompile`) |
| `get_player` | position, niveau, mer, Beli, fragments, race, fruit, outils… |
| `fire_remote` | FireServer / InvokeServer sur un remote |
| `remote_spy_start` | charge **Cobalt** dans le jeu et envoie chaque appel qu'il logue au MCP |
| `remote_spy_logs` | les appels de remotes logués (filtre par nom, direction) |
| `remote_spy_clear` | vide les logs (MCP + Cobalt) |
| `hub_load` | charge Strawberry Hub ou le Kaitun (avec une config) |
| `hub_status` | ce que fait le hub / Kaitun : tâche, statut du farm, quête lue, journal de voyage |
| `hub_set_setting` | change un réglage du hub en cours |

Valeurs spéciales pour `fire_remote` : `{"$vector3":[x,y,z]}`, `{"$cframe":[x,y,z]}`,
`{"$instance":"game.Workspace.X"}`.

## Attention

- `execute_lua` exécute **n'importe quel code** dans ton client : n'ajoute ce MCP qu'à ton
  propre Claude Code, et ne partage pas le token.
- Le pont écoute sur ton réseau local (port 7777) ; seules les requêtes avec le token passent.
- Si rien ne se connecte : vérifie l'IP, le pare-feu Windows (autoriser Node), et que MuMu est
  bien en mode réseau qui voit le PC. `BRIDGE_PORT` change le port si 7777 est pris.

## Développement

`npm test` lance les tests Node (pont HTTP avec un faux client, outils, serveur réel en stdio).
Le client en jeu (`lua/bridge.lua`) est testé par `python3 tools/test.py bridge` à la racine du repo.
