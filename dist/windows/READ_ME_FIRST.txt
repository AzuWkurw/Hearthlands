Hearthlands v{VERSION}, build {BUILD} ({DATE}) for Windows (64-bit)
=============================================================

To play: double-click Hearthlands.exe. Nothing needs installing.
The version and build number are shown at the top of the game window. CHANGELOG.md lists what's new.

Windows may show "Windows protected your PC" the first time, because the game is not
code-signed. Click "More info", then "Run anyway".

Needs a graphics card with OpenGL 3.3 (almost any PC from the last ten years). Vulkan is preferred:
the first start tests it once in a small extra window and switches to it if it works.

Your saves, custom textures and mods live in:
  %APPDATA%\Godot\app_userdata\Hearthlands\
    saves\      saved games (saves from builds 4 to {BUILD} still load)
    textures\   your replacement PNG textures (use "Export defaults" in game to start)
    data\       mod JSON files (resources.json, buildings.json, techs.json, needs.json)
    mods\       script mods (.gd); tick them under Settings > Game features
In game, "Textures and mods" > "Open mod folder" opens it for you.

Controls: drag to pan, wheel to zoom, right click or Esc cancels, Space pauses,
1-4 set speed, R research (R turns a building's entrance while placing it), G diplomacy, F5 quick save, F9 quick load, F2 production statistics, F4 climate, F6 random events, E event log, B building places, F3 performance overlay, P problems list, Q copy the selected building, Ctrl+Z undo, I next idle building, F7 traffic map, 5 for 16x speed.
The event log window can be dragged by its title and resized from its edges.
Seasons, biomes and weather change how fast farms, fishers and builders work; people need fur coats
in the cold and linen clothes in the heat (furrier, flax farm, linen weaver).
Diseases break out and spread: prevent them with bathhouses and wells, cure them with medicine
(herb garden, apothecary, infirmary). Random events happen every few minutes. Tools come in four
qualities, by the toolsmith's skill, and wear out.
Every store keeps its own goods (click a store to see them). Carriers bring workshops their raw materials
and construction sites their materials from the nearest store that has them. People live in homes,
workers' lodges, training buildings and the headquarters, and walk to their jobs.
Fog of war: train scouts at a scout lodge, man watch towers with them, or use Scout on the toolbar.
Ore is hidden until a geologist surveys the mountain: Geologist on the toolbar. Hunters need real game.
Buildings keep the look of the age they were built in; select one and press Renovate to update it.
Soldiers come in six kinds, one per age, each fighting its own way: Military group > "Soldier kinds".
Drag the title of the building info box to move it.
Settings > Game features switches optional features on or off ("Classic rules" turns them all off).
Toolbar along the bottom: building groups, Road, Pave, Remove road, Flag, Auto roads, Demolish, Scout, Geologist.
Each building has an entrance (flag); roads join it only there. With Auto roads off you lay each new
building's road yourself, starting at its entrance. Events with a Go button move the camera there.
Buildings come in sizes, as in The Settlers: small (1 tile), medium (2), large (3 x 2, flat ground) and
mines, with a free tile all round. The Sites button (or B) marks where each size fits.
Select a building: High / Normal / Low / Paused set its priority (Page Up, Page Down, P). Delete demolishes (it asks first).
Settings (button on the top bar, or F10): Vulkan or OpenGL renderer, window or fullscreen, resolution,
interface size, VSync, frame-rate limit, animations, sound on/off and volumes. Switching the renderer restarts the game and
continues your game. If the game ever fails to start after choosing Vulkan, double-click
"Start in OpenGL safe mode.bat", then choose OpenGL in Settings.
Click a building and use "Move work area" to send woodcutters, quarries etc. elsewhere (up to 6 tiles).
Click a resource in Stores, or a deposit on the map, to see its info.
