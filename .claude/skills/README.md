# Claude Code skills for Hearthlands

Claude Code loads these automatically when a task matches their description. `.claude/.gdignore`
keeps Godot from importing anything in this folder, and the export presets never include it.

| Skill | What it is for | Source | License |
|---|---|---|---|
| `hearthlands-localization` | Translating `data/lang_*.json`, Polish count forms, placeholder checks | Written for this project | Same as the game |
| `godot-gdscript-patterns` | GDScript patterns: signals, state machines, scenes, performance | [wshobson/agents](https://github.com/wshobson/agents/tree/91ff753/plugins/game-development/skills/godot-gdscript-patterns) @ `91ff753` | MIT |
| `godot-best-practices` | Typed GDScript, autoloads, save/load, project structure | [jwynia/agent-skills](https://github.com/jwynia/agent-skills/tree/e02ec7e/skills/tech/game-development/godot/godot-best-practices) @ `e02ec7e` | MIT (per its SKILL.md) |
| `godot` | `.tscn` / `.tres` file formats, pitfalls, two local validators | [bfollington/terma](https://github.com/bfollington/terma/tree/ccaf04c/plugins/tsal/skills/godot) @ `ccaf04c` | CC BY-SA 4.0, see `godot/LICENSE` |

The three outside skills are copied unchanged. Before adding them they were checked for network
calls, credential access, hooks, permission settings, obfuscated code and hidden instructions: they
are Markdown plus two Python scripts (`godot/scripts/validate_*.py`) that only read the file they are
given.

Notes:
- The examples are for Godot 4.x in general. Hearthlands is on 4.3; where a skill names a newer
  version (the GUT test addon note in `godot`), check it against 4.3.
- Example save code in two skills uses a placeholder encryption key (`"your_secret_key_here"`). Do
  not copy it into the game.
- To update an outside skill, re-copy it from its repository and check the diff for the same things.
