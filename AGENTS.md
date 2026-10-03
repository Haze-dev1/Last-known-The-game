# Project instructions

## Direction

Build a lightweight, chapter-based first-person survival mystery using Godot and typed GDScript. Target native Linux first; preserve portability for later Windows and macOS testing. Kowloon supplies the urban geography, adapted for gameplay. Nature has reclaimed the city over decades.

Preserve the unseen protagonist, absence of present-day human NPCs and spoken dialogue, and an eerie rather than horror tone. Technology restoration and evidence-based investigation drive progression. Story proposals remain provisional until the user accepts them.

## Read for the task

- Before implementation, read [the development plan](docs/development-plan.md) for milestones, ownership, and performance targets. Complete one playable chapter before expanding the city.
- For narrative or clue changes, read [the story draft](docs/source/story.md). Preserve the distinction between established evidence and the player's interpretation.
- For environment, art, or level work, read [world direction](docs/source/world.md) and [the map brief](docs/source/map.md). Kowloon is selected even where older notes still list city selection as open.
- Consult [docs/README.md](docs/README.md) for the document index. Update affected documents when decisions change rather than letting competing versions accumulate.

## Implementation workflow

Follow [project structure](docs/project-structure.md) when adding files. Put the Godot project in `game/`, editable asset sources in `assets-source/`, automation scripts in `tools/`, and generated exports in `builds/`. Keep scenes and their scripts together by feature; create folders as content requires them.

1. Identify the current milestone and the observable behavior the task must deliver. Reuse existing scenes and systems before adding new ones.
2. Inspect the actual engine version, project settings, and available commands. During setup, pin a stable Godot version and document verified launch, check, and export commands. Do not assume proposed tooling is installed.
3. Implement the smallest complete change using typed GDScript and built-in engine features. Add dependencies only for a concrete current need. Keep shared gameplay logic separate from chapter-specific content without building speculative frameworks.
4. Run checks appropriate to the change. For gameplay changes, verify the affected path in the running game when possible. State explicitly when visual or interactive verification is unavailable.
5. Report changed behavior, checks actually run, remaining limitations, and the next milestone. Preserve other contributors' work.

## Gameplay and portability

- Represent evidence and puzzle prerequisites explicitly. Repeated interactions and clues discovered out of order must leave progression consistent.
- Preserve essential progression across checkpoints. Resource depletion must have a recovery path when it could otherwise make a required puzzle impossible.
- Keep pause, computer-screen input, and player movement modes consistent, including mouse capture on entry and exit.
- Use engine-managed project and user-data paths. Keep filenames and references case-consistent. Avoid machine-specific paths in game code.
- Track source and license information for imported assets and geographic data. Downloaded geometry still needs collision, scale, and performance checks.

## Performance and completion

Use the development plan's budgets as targets, not measured achievements. Benchmark a representative scene before multiplying its vegetation, lights, or materials across the chapter. Record hardware, resolution, renderer, and build type with performance results.

A headless check does not prove visual quality or playability. Before calling a chapter release ready, test its exported Linux build from a fresh start through the ending and verify checkpoint restoration, pause/resume, settings, and exit. Record any checks requiring user playtesting as pending. Windows and macOS support require testing on those platforms.

## Skills

Load the relevant local skill on demand:

| Task | Skill |
| --- | --- |
| Implementation scope and dependency choices | [ponytail](skills/ponytail/SKILL.md) |
| Engine API, compatibility, or verification claims | [verify-claims](skills/verify-claims/SKILL.md) |
| Review of progression, state, or save/load changes | [correctness-review](skills/correctness-review/SKILL.md) |
| Reproducible bugs or performance regressions | [diagnosing-bugs](skills/diagnosing-bugs/SKILL.md) |
| Review of tests protecting gameplay behavior | [test-quality](skills/test-quality/SKILL.md) |
| Setup, export, and handoff documentation | [tech-writing](skills/tech-writing/SKILL.md) |

Read linked supporting files when the selected skill requires them. The copies sometimes refer to `.claude/CLAUDE.md` or preinstalled hooks; inspect whether those exist and use these project documents for context when absent. See [the skill catalog](skills/README.md) for provenance and the installed Godot references. Treat community examples as unverified until checked against the pinned engine and exercised.

## Git and GitHub workflow

The user owns the initial commit and push. Wait for that initial push before taking over routine repository maintenance; do not create a remote or initial commit on their behalf.

After the initial push, inspect the branch, worktree status, and remote before repository work. Use short, descriptive feature branches for coherent tasks and focused commits describing the resulting behavior. Review the diff and stage specific intended paths, including relevant documentation and tracker updates. Preserve unrelated changes and other agents' work.

Run appropriate checks before committing and record what actually passed. Push task branches and use pull requests for integration; include the problem, change, validation, and any remaining limitations. Merge only when the user authorizes it. Avoid force pushes, rewritten shared history, and destructive cleanup unless explicitly requested.

Keep generated builds and engine caches out of Git. Preserve Godot resource UID and import-setting sidecars, source assets, and export presets without credentials. Check asset sizes and licenses before adding them; decide on Git LFS before committing large binary assets. Distribute packaged games as release artifacts when publishing is authorized.

Maintain `docs/tracker/progress.json` and the curated root `debug.log` in version control. Add only concise, redacted observations to the log; noisy runtime logs stay ignored. Report the branch, commit, and PR when created, and distinguish local changes from pushed work.

## Agent handoffs

Use the development plan's role assignments when the user authorizes work in other agents. This document does not itself authorize spawning agents or messaging external chats. Give each authorized helper a bounded task, owned files, expected output, and acceptance checks. Keep one integrator responsible for shared scenes and game state.

For handoffs, name the files changed, checks run, known issues, and next action. Keep design decisions and task status in the repository so progress does not depend on another agent's chat history.

## Progress and debug records

At the start of work, read `docs/tracker/progress.json`. After a meaningful milestone, verification result, blocker, or handoff, update the relevant task with its owner, status, evidence, next action, and an ISO 8601 timestamp. Use `pending`, `in_progress`, `blocked`, or `completed`; completion requires recorded evidence. Re-read before writing, preserve other agents’ updates, and write valid JSON through a temporary file followed by atomic replacement. The integrator owns shared tracker updates during parallel work.

Maintain root `debug.log` as an append-only development record. Append timestamp, agent, task ID, severity, command or action, observed result, and any follow-up for failed checks, reproduced bugs, fixes, and verification. Redact secrets and avoid full noisy dumps. Record successful checks as well so resolved failures are traceable. Never invent engine output. This file is not yet wired to Godot; when runtime logging is added, use a writable user-data path for packaged builds and summarize relevant results here.

Store game design and narrative documents in `docs/source/`; workflow/setup documents in `docs/`; task state in `docs/tracker/`. Keep root entry points and executable skill packages in place. Update links when moving files.

Installed Godot skills are available under `skills/`: `godot-gdscript-patterns`, `godot-3d-essentials`, `godot-audio`, `godot-ui-control`, and `godot-export`. Read the matching SKILL.md for its task. The latter four target Godot 4.7; verify APIs and renderer support against the actual installed stable version. Skill examples do not override our first-person tone, lightweight scope, or portability requirements.
