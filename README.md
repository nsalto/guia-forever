# Guía Forever

## Instalar o actualizar (Windows)

1. Hacé clic acá: **[Bajar ActualizarGuia.bat](https://github.com/nsalto/guia-forever/releases/latest/download/ActualizarGuia.bat)**
   (se descarga solo; si el navegador pregunta, elegí *Conservar*). Movelo al escritorio.
2. Doble clic. La primera vez Windows puede decir "Windows protegió tu PC": *Más información → Ejecutar de todas formas*.
3. Abrí el juego. Para actualizar más adelante: doble clic de nuevo, nada más.

Sin actualizador: [GuiaForever.zip](https://github.com/nsalto/guia-forever/releases/latest/download/GuiaForever.zip),
descomprimilo en `World of Warcraft\_forever_\Interface\AddOns`. En Mac:
[ActualizarGuia.command](https://github.com/nsalto/guia-forever/releases/latest/download/ActualizarGuia.command).

A World of Warcraft: Forever (client 1.60.x, `## Interface: 16001`) addon: a small movable window
that guides a player while leveling. In-game text is in Spanish (esMX); the deepest content is for rogues.

## Tabs

Each section is drawn as a card with an accent color; quest objectives with counts show as progress bars.
Every section title can be clicked to fold or unfold it; the choice is remembered.

- **Ahora** — on top, "Lo próximo": your next 3 stops in order, each with an [Ir] waypoint. It mixes turning in
  finished quests, the next objective of quests worth doing and picking up quests worth taking, ordered by value per
  distance from where you stand. Left out: grey quests, quests more than 2 levels over you, dungeon quests for
  dungeons you are not preparing, cloth donations, battleground quests, and quests whose items have no known source.
  When the zone runs out it names the next zone (your continent first), then the dungeon you are closest to having
  ready and the quests in your log not worth keeping. It corrects itself with the server: when a quest giver does not
  offer a quest the data expected, that quest leaves the route until you level up, and the real reward XP shown in
  the quest window is used for the ranking. Turn it off in Ajustes > Misiones.
  The **next-step bar** shows only the first of those steps, with almost no text: an icon for what to do (take, turn
  in, kill, loot, travel), an arrow that turns toward the target as you turn, the distance, a progress bar for counted
  objectives and a short name (details in the tooltip). It sets the map waypoint on its own, moves to the next step
  when you finish one (green flash and a sound), and "»" skips a step until you level up. Drag to move, right-click
  opens the guide; `/guia barra` or Ajustes > Misiones turns it on or off. Hidden inside instances. The game's
  arrow in the middle of the screen (ours: a gold arrow, the name and the meters, detail with Shift + mouse over; clicks go through it) follows the step and any [Ir]; `/guia flecha` or Ajustes turns it off. At a flight master, each flight point on the map shows how far it lands from that target, the closest one marked in green with a star.
  **Preparing a dungeon:** [Preparar] next to a dungeon you still have quests for (Ahora, Guía > Mazmorras, or
  Ajustes > Mazmorras > Preparar mazmorra). While it is set, the bar and "Lo próximo" only take you to that dungeon's
  quests and the quests before them, here first and then on other maps; when you have them all the bar says
  "¡Listo!" and where the entrance is. It ends when you walk into that dungeon, or with [Dejar].
  Then "Para hacer ya" (max 3 items: completed quests with the XP they give, new trainer abilities, unspent
  talents, full bags, low durability, capped professions), "Tu ritmo" (XP/hour, time and kills to level, quest vs kill
  XP, gold/hour, time per level), "Cerca de vos" (PvP status, enemies you saw and enemies your party reported), zone fit, dungeons for your level,
  upcoming class abilities, one rotating tip.
- **Misiones** — on top, "Tu plan": a live route for the zone you are in. Quest points come from the client's quest
  map data; objectives close to each other become one stop, stops are ordered by XP per distance from where you
  are, turn-ins are batched, with total XP and whether you level up. Below it, every quest in your log is ranked by priority (turn in / high / medium / group or later / skippable),
  with objectives, progress, direction to the objective, turn-in NPC, clickable [Ir] waypoint and [Compartir].
  In a party, each quest shows who else has it and their progress (members running the addon share it over
  addon messages, prefix `GUIAF`), plus a "share all missing quests" action.
- **Ruta** — the leveling roadmap, worked out live from the quest database and your character: the zones with the
  most quests you can take at your level, and the quests you can accept right now in your zone (level, race, class,
  faction of the giver, prerequisites done, not done yet, not in your log; world events and profession quests left
  out), grouped by NPC, closest first, with the chains each one opens and an [Ir] waypoint. The same quests show as
  "!" pins on the world map (hover: which quests; click: waypoint).
- **Grupo** — one row per party member: level and XP bar, status (offline, dead, out of range) and, for members
  running the addon, XP/hour, time to level, free bag slots, durability and professions. Then "Misiones en común"
  (each shared quest with everyone's stage) and "Hoy" (the party's XP, kills, deaths and gold this session).
- **Clase** — spec comparison by goal (leveling, level 60, PvP) for all classes, talents, rotation, gear,
  consumables and class quests.
- **Guía** — dungeons, professions and tips in foldable sections.

## Other features

- **Quest notices** — sound and on-screen line when an objective finishes, a new objective appears (Forever
  quests add objectives in sequence) or a quest is ready to turn in.
- **Reward hint** — on quest turn-in with a choice, a green check marks the best reward for your class and a coin
  marks the most valuable one to sell.
- **PvP (PvP realms)** — alert when an enemy player shows up (nameplates, target, mouseover; ~40 yd, stealthed
  players cannot be detected), class tips for rogues, optional party warning, and a list of players who likely
  killed you. Paused in sanctuaries, instances, flights and while dead.
- **Combat meter** — a small movable window with class-colored bars, fed by Blizzard's own meter
  (`C_DamageMeter`). Pick up to 4 metrics from a list to see them stacked (damage, DPS, healing, HPS,
  absorbs, damage taken, avoidable damage taken, interrupts, dispels, deaths, damage per enemy), current fight or
  total or one of the last 10 fights; a threat view for your party on your target with a high-threat warning in groups;
  hover a bar for the per-ability breakdown; R button reports the top 5 to group chat; class icons, gradient bars, percent of total, fight length, fades out of combat, lockable, 3-10 rows. Numbers hidden by the client during combat are shown raw and tidied after the fight. `/guia medidor`.
- **Auto quests** (`AutoQuest.lua`): accepts quests and turns in finished ones when you talk to the NPC; stops when a reward must be chosen or gold paid, skips grey quests; hold Shift to do it by hand. Off by default (Leatrix, Questie and RXP do the same, and two at once fight each other); turn it on in settings (Misiones).
- **Quest mob marks**: a small sword with your progress (`2/6`) over the nameplate of mobs your quests need, from the unit's own quest lines, the mob name in your objectives, and drop tables for quest items (`DataQuestDrops.lua`, 5%+ sources). No name guesses. Works with ThreatPlates too: while the marks are on, ThreatPlates' own quest icon is turned off so there is only one mark (and turned back on if you switch ours off). Optional kill reminder (off by default) names the item and its drop chance; the loot window frames the quest item.
- **Enemy nameplates** (`Nameplates.lua`): your own debuffs on each enemy (bleeds, poisons...) with the seconds left, red under 10 s; a red border when the mob is attacking you; health in %. Each part toggles in settings (Bichos). Usable objects (quest objects, chests, herbs) get the game's interact icon all around you up to 15 yd, plus a soft gold sparkle.
- **Dungeon entrances up a hill**: the arrow goes first to where the path starts (Excavation Site: the meeting stone) and then switches to the portal by itself.
- **Quest database** (`QuestDB.lua`, data in `DataQuestDB.lua` with Spanish names): giver, turn-in, prerequisite chain, quests it unlocks, objectives with the creatures and objects that give each item, and their positions on this client's map (classic coordinates corrected per zone with DataCity's Forever world coordinates). `/guia qdb <questID>` prints what it knows. Base for the quest arrow, map pins and quest detail.
- **Town and city map**: on the big map of every Alliance-friendly town and city, pins for your class trainer, weapon masters, profession trainers, bank, auction house, inn, flight and stable masters, repair vendors (what the guards point you to). Hover for who it is, click to set a waypoint. Toggle in settings or `/guia ciudad`. Data: wowforever.wclbox.com Forever database (world coordinates converted per zone, checked against classic positions to under 1% of the map).
- **Item advice** — every item tooltip ends with a verdict: keep (quest item, profession material, consumable,
  future upgrade), equip (upgrade for your class), sell (junk, useless gear) or auction (uses Auctionator prices).
- **Dungeon companion** — inside a dungeon, a card at the top of "Ahora": bosses killed / left (from encounter
  events), your quests for it and the ones you are missing (with where to pick them up), loot that suits your class
  from bosses still alive. On leaving, a run summary (time, XP, bosses, deaths). Data from ForeverDungeonJournal.
- **SOS** — `/guia sos` (or the link in "Cerca de vos", or a macro) asks your party for help with your position and
  the enemy you are fighting; friends with the addon get a clickable banner that sets a waypoint (`/guia ir`).
- **Rivals** — counts who killed you and who you killed (from the honor message), marks némesis, and lets you mark
  a target as rival (`/guia rival`); enemy alerts show that history.
- **Bag marks** — with Baganator, a corner badge on bag items: Q quest item, + upgrade to equip, M material for
  your professions, ^ upgrade for later, $ worth auctioning (each badge can be turned off).
- **Layers** — reads the layer from NPC GUIDs (zone UID field) around you, shares it with party members running
  the addon, and shows in "Ahora" whether each friend is on your layer, with steps to merge; optional banner when a
  friend is in your zone but on another layer.
- **Change layer** — an on-screen button (click to change, click again to cancel, drag to move, right click to
  hide; `/guia capa boton` shows it again), `/guia capa` (or the link in "Ahora", or a key under Esc > Options > Keybindings > Guía Forever).
  Asks other Guía users in a hidden channel; a free one in your zone on another layer invites you, the invite is
  accepted for you, and you leave the group once the NPCs around you report the new layer. If no Guía user answers
  in 8 s, a link asks for an invite in General chat. Helping others is on by default (only when you are solo, out of
  combat and outside instances; turn it off in Ajustes > PvP or with `/guia capa ayudar`). `/guia capa cancelar` stops. `/guia capa prueba` lists the Guía users online, their zone and layer, and why each one can or
  cannot help (also shown automatically when nobody offers).
- **Character snapshot** (`Companion.lua`) — on `/reload`, logout and `/guia foto`
  writes level, zone, gear, quests, professions, spellbook, action bars with their keys and group to the
  `GuiaForeverSnapshot` saved variable, so a tool outside the game can read it. Read-only.
- **Party** — quest progress shared over `PARTY` / `INSTANCE_CHAT`, "share all missing quests" action.

## Install

Copy the `GuiaForever/` folder (the repository contents) into `World of Warcraft/_forever_/Interface/AddOns/`.

**One-click update** (for players): `ActualizarGuia.bat` (Windows) or `ActualizarGuia.command` (macOS) from the
latest release; double click it. It downloads the latest release's `GuiaForever.zip`, removes the old `GuiaForever`
(and any old `GuiaForever_Data`) folder and copies the addon in. The AddOns folder is found in the usual install locations or picked once in a folder dialog, and
remembered. Each release is a new version for everyone who runs it.

Restart the game client after installing (a new addon folder is not picked up by `/reload`).

## Commands

- `/guia` — show or hide the window
- `/guia barra` — show or hide the next-step bar
- `/guia flecha` — let the on-screen waypoint arrow follow the step, or not
- `/guia meta 20` — level goal on Ahora: XP left, what your quest log covers, kills and time for the rest, zones (`/guia meta no` clears it)
- `/guia ajustes` — settings panel (also the gear button in the header), by category (General, Misiones, PvP,
  Medidor, Objetos, Mazmorras): every feature has a switch with a one-line explanation, and each category can be
  reset to its defaults
- `/guia reset` — reset position and size
- `/guia font <9-18>` — text size
- `/guia alpha <0.2-1>` — background opacity
- `/guia avisos [listas|todo|no]` — quest notices (default `listas`: ready, failed, new objective)
- `/guia sos` — ask your party for help; `/guia ir X Y` — waypoint at map coordinates (`/guia ir` alone: last SOS); `/guia rival` — mark target as rival; `/guia capa` — change layer
- `/guia pvp` — toggle enemy alerts; `/guia pvp sonido | compartir | limpiar | nombres`
- `/guia ciudad` — toggle the town and city map pins
- `/guia marcas` — quest mob marks diagnostics (target a mob first)
- `/guia qdb [questID]` — what the quest database knows about a quest, and which navigation APIs this client has

## Notes

- Reads only the player's own state through the standard API; it never acts in the game.
- Optional integration: ForeverDungeonJournal (dungeon quest data, quest-giver coordinates).
- Guide data lives in `Data.lua`, `DataClasses.lua` and `DataProfessions.lua`; generated data in `DataQuestDrops.lua`
  (including `DataRecipes.lua` and `DataQuestDB.lua`).

## Licenses

Guía Forever is free software under the GNU General Public License version 3 (`LICENSE`). The quest database comes from forever-db, World of Warcraft: Forever data read from the game client (rebuild it with `tools/build_questdb.py`). Third-party license notices are in `THIRD_PARTY_LICENSES.md`.
