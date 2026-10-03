# Shared project skill library

Six existing user-installed skills were copied here with their supporting files on 3 October 2026. `copy-manifest.json` records source paths and SHA-256 hashes; each copied file was compared with its source.

This is a shared reference folder. Copying here does not automatically register skills with Codex, Claude Code, Antigravity, or OpenCode. Give an agent the relevant SKILL.md path in its task prompt. The project's `.agents` directory is read-only in the current environment; no agent-specific discovery configuration was changed.

| Skill | Use in this project |
| --- | --- |
| [ponytail](ponytail/SKILL.md) | Keep implementation focused on the current playable chapter; use engine features before custom frameworks. |
| [verify-claims](verify-claims/SKILL.md) | Check Godot APIs against the pinned engine and distinguish executed checks from assumptions. |
| [correctness-review](correctness-review/SKILL.md) | Review progression, interaction, pause, scene changes, and save/load changes. |
| [diagnosing-bugs](diagnosing-bugs/SKILL.md) | Reproduce bugs and performance problems before fixing them. |
| [test-quality](test-quality/SKILL.md) | Check whether tests catch broken puzzle prerequisites, duplicated evidence, and incorrect restoration of saves. |
| [tech-writing](tech-writing/SKILL.md) | Maintain setup, export, design, and handoff documentation. |

Load only the skill relevant to the task. These copies are unchanged references, not an instruction to run every workflow on every edit. Some expect `.claude/CLAUDE.md` or existing hooks; those do not currently exist here. Use the actual project documents for context and report absent tooling instead of assuming it is installed. User instructions and host permission rules take precedence.

## Installed Godot skills

[wshobson/agents: godot-gdscript-patterns](https://www.skills.sh/wshobson/agents/godot-gdscript-patterns) is a community-maintained Godot 4 reference, not an official Godot skill. The directory displayed 16.3K installs and 40.2K repository stars when checked. Those are popularity signals, not correctness guarantees.

Read the [skill source](https://github.com/wshobson/agents/blob/main/plugins/game-development/skills/godot-gdscript-patterns/SKILL.md) and its [worked examples](https://github.com/wshobson/agents/blob/main/plugins/game-development/skills/godot-gdscript-patterns/references/details.md) before adopting patterns. The reviewed examples are largely 2D and include systems we do not need. The sample pause input handler is guarded by PLAYING, so that handler cannot toggle back from PAUSED. Its state transition example also dereferences a previous state without a null check.

Recommendation: optional reference for scenes, signals, resources, and typed GDScript. Installed into Codex and copied into this project; examples have not been executed. Validate any adopted code against our engine and tests. Installation counts are not a reason to import an entire game architecture.

Primary references remain [Godot documentation](https://docs.godotengine.org/en/stable/) and the documentation matching our eventual pinned version.

Four additional skills from [gamedev-skills/awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills) were reviewed and installed with their references:

- [godot-3d-essentials](godot-3d-essentials/SKILL.md): scene composition, cameras, materials, and lighting.
- [godot-audio](godot-audio/SKILL.md): positional audio and mixing.
- [godot-ui-control](godot-ui-control/SKILL.md): menus, device interfaces, layout, and focus.
- [godot-export](godot-export/SKILL.md): packaging and export checks.

These community skills target Godot 4.7. Verify examples against the actual installed engine; engine version selection remains with Claude’s installation task. Their related-skill lists are suggestions, not dependencies to install automatically. Generic third-person camera examples and heavy rendering effects must be adapted to this project.

All five new skills are installed under `/home/haze/.codex/skills/` for Codex discovery on the next turn and copied under this shared directory for other agents to read explicitly. No Claude, Antigravity, or OpenCode discovery settings were modified.
