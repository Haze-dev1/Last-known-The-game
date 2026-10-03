# Project structure and working conventions

The repository root is `/home/haze/Projects/Game`. The Godot project belongs in `game/`, keeping documentation, source artwork, skills, and exported builds outside the engine's resource tree.

## Layout

```text
Game/
├── AGENTS.md
├── README.md
├── .gitignore
├── debug.log
├── game/                 # Godot project and runtime content
├── assets-source/        # Blender originals, raw map data, editable artwork
├── tools/                # Reproducible asset preparation and validation scripts
├── builds/               # Generated exports; ignored by Git
├── docs/
│   ├── README.md
│   ├── development-plan.md
│   ├── project-structure.md
│   ├── source/           # Game design, story, world, map, chapter briefs
│   └── tracker/
│       └── progress.json
└── skills/               # Shared agent guidance; never shipped with the game
```

The four implementation/output directories are reserved now. Create their subdirectories only when real content needs them. `game/project.godot` does not yet exist; the next toolchain task creates it.

## Organize the Godot project by feature

Keep a scene and its attached scripts together. Proposed locations when implemented:

- `game/player/`: player scene, controller, and interaction ray.
- `game/interaction/`: reusable interactable objects and shared interaction behavior.
- `game/investigation/`: evidence definitions and journal behavior.
- `game/ui/`: common menus, settings, and shared themes.
- `game/chapters/chapter_01/`: chapter scene, local puzzles, and chapter-specific evidence.
- `game/assets/`: shared game-ready models, textures, materials, fonts, and audio.
- `game/tests/`: runnable checks for state and progression when introduced.

Keep chapter-specific code in its chapter. Extract genuinely shared behavior when needed. Avoid a global collection of unrelated scripts or a new manager singleton for each feature.

Use lowercase `snake_case` for file/folder names. Commit authored scenes, resources, source scripts, export presets without secrets, and engine-generated resource UID sidecars. Ignore `.godot/` caches and generated exports.

## Assets and builds

Store editable `.blend` files and raw geographic downloads in `assets-source/`. Export only needed game-ready assets into `game/`. Record source URLs and license/attribution details when assets are added. Large downloads need a size review before entering version control.

Produce Linux builds under `builds/linux/`. Later platforms use sibling directories. Export templates must match the chosen engine version. Save player data through Godot's user-data path rather than writing into the installed game folder.

## Engine baseline

Verified locally: `godot --version` returns `4.7.2.stable.arch_linux.ed1daf0bf`. Use Godot 4.7.2 for the initial chapter. Recheck after system updates; an engine upgrade must be deliberate and followed by import, gameplay, and export checks.

Export templates were not found in the two checked directories: `~/.local/share/godot/export_templates/4.7.2.stable` and `/usr/share/godot/export_templates/4.7.2.stable`. Their availability elsewhere remains unverified. Resolve this during the first export task. No launch or export command for this project is verified yet.

## Next work

1. Write `docs/source/chapter_01.md`: opening, objective, clue dependencies, ending, and acceptance checks.
2. Create `game/project.godot` and a minimal scene; verify editor import and a Linux export.
3. Implement a walkable street and one complete interaction before broad world construction.
4. Finish the chapter using placeholder art, then improve visuals and sound against measured budgets.

Update `docs/tracker/progress.json` and append relevant checks to root `debug.log` as required by `AGENTS.md`.
