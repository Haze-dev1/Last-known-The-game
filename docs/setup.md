# Run and verify Chapter 1

Run the placeholder Chapter 1 investigation with Godot 4.7.2 and the Compatibility renderer. Commands below run from the repository root. Evidence, power, sequence flags, sensitivity and chapter completion persist through checkpoints.

## Engine and templates

`godot --version` observed `4.7.2.stable.arch_linux.ed1daf0bf`. The official Linux release template reports `4.7.2.stable.official.ed1daf0bf`, the same engine revision. Matching Linux debug/release templates and `version.txt` are installed in `~/.local/share/godot/export_templates/4.7.2.stable/`. The preset is **Linux Chapter 1**, x86_64, with an embedded PCK.

For another Linux machine, install Godot 4.7.2 and its matching templates. The official [4.7.2 release](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable) supplies the archive. The download used here was:

```bash
curl -fsSL -C - --max-time 120 -o /tmp/godot-templates.tpz https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz
mkdir -p builds/templates
unzip -jo /tmp/godot-templates.tpz templates/linux_release.x86_64 templates/linux_debug.x86_64 templates/version.txt -d builds/templates
cat builds/templates/version.txt
mkdir -p ~/.local/share/godot/export_templates/4.7.2.stable
cp builds/templates/linux_release.x86_64 builds/templates/linux_debug.x86_64 builds/templates/version.txt ~/.local/share/godot/export_templates/4.7.2.stable/
```

The archive download timed out once; repeating the curl command resumed it successfully. `version.txt` must read `4.7.2.stable`. Generated templates and builds stay ignored. No external art or map assets are imported; geometry uses built-in primitives.

## Play

```bash
godot --path game
```

Or run the exported executable:

```bash
./builds/linux/last_known.x86_64
```

Choose **New expedition** at the title (confirm again if replacing a checkpoint), or **Continue checkpoint**. Wait for arrival or skip with E/Escape. Use WASD and mouse look; E inspects; J opens/closes the evidence journal; Escape closes a record/menu or pauses walking.

1. Inspect the workbench computer: no power yet. Connect the yellow portable supply outside, then read the service note.
2. Enter the left rear utility alcove and read its closure notice.
3. Take the service stair on the right of the shop to the upstairs rear doorway. Inspect the protected photograph and revised address list. The acceptance letter is optional.
4. Compare the journal's interpretation. The note, notice and photograph corroborate a return after closure; the address list adds the station/shelter lead.
5. Return down the stair and inspect the street's onward-route marker to complete Chapter 1. Escape lets you keep exploring.

Clues can be found out of order. The four essential records are required for departure; repeated reads stay unique. Arrival and the first corroboration glance are skippable. The photograph is described in text until an approved image is authored. Geometry and clue wording remain placeholders/proposals.

## Save and recovery

The normal slot is `user://chapter_01.json`, with the preceding valid snapshot at `user://chapter_01.json.bak`. The stable project name is now **Last Known** (the earlier foundation had no persistent gameplay save). Autosaves follow arrival, power/clue discoveries, the first corroboration, sensitivity changes and chapter ending. Pause provides manual **Save checkpoint**, **Return to title** and **Quit**.

Continue uses a named safe room anchor, not your exact last coordinates. It restores power, evidence, sequence flags, sensitivity and completion. A completed checkpoint shows the ending and permits exploration. No resource system can deplete the required supply.

Checkpoint writes validate the schema and prerequisites, write/flush/re-read a temporary file, preserve a valid backup, then replace the primary. A damaged primary recovers its valid backup. If neither file is usable, Continue is disabled and the title explains that files are preserved. Confirmed New replaces this chapter slot. A temporary file left by interruption does not count as committed progress.

If saving fails, the visible checkpoint status reports the error. Return to title stays in the current session; Quit first offers **Quit without saving · checkpoint failed**, requiring another click. Native window closure/forced process termination is not an extra save trigger; essential progress already autosaves, but use pause Save/Quit for the latest room/settings.

## Import, check, export

```bash
godot --headless --path game --import
godot --headless --path game --script res://tests/foundation_check.gd
godot --path game --script res://tests/foundation_check.gd
godot --headless --path game --script res://tests/chapter_check.gd
godot --path game --script res://tests/chapter_check.gd
mkdir -p builds/linux
godot --headless --path game --export-release 'Linux Chapter 1' ../builds/linux/last_known.x86_64
./builds/linux/last_known.x86_64 --headless --quit-after 240
./builds/linux/last_known.x86_64 --quit-after 240
```

`--quit-after` counts frames, not seconds. Both checks return nonzero on failure and print `FOUNDATION CHECK: 0 failures` or `CHAPTER CHECK: 0 failures` on success. They instantiate the real scene, exercise physics/raycasts, inject engine input and use real UI signals. Save tests use `user://checks/` slots, separate from your normal chapter save.

The foundation check protects movement, collision, arrival, power, repeated reads and menu/mouse behavior. The chapter check walks the service stair up, through its doorway and down; places later clue approaches; checks optional/out-of-order records, interpretation, discovery/ending, partial/completed reloads, corrupt-primary backup, invalid schemas, write failures and confirmed restart. The headless driver cannot capture a pointer; graphical checks cover capture/look. The harnesses isolate native focus changes and explicitly exercise the production focus-loss handler. The chapter harness also suspends native mouse-look events during scripted routes; the foundation check separately exercises mouse look. Native focus switching and a fully human-controlled route remain manual checks. A separate two-process check writes a powered, one-clue checkpoint and restores its state/settings from a newly launched process.

The release excludes tests. To check its **packed resources** with the editor and an external harness, this command was exercised:

```bash
godot --main-pack /home/haze/Projects/Game/builds/linux/last_known.x86_64 --script /home/haze/Projects/Game/game/tests/chapter_check.gd
```

The same packed resources were checked across separate processes with:

```bash
godot --headless --main-pack /home/haze/Projects/Game/builds/linux/last_known.x86_64 --script /home/haze/Projects/Game/game/tests/checkpoint_process_check.gd -- write
godot --headless --main-pack /home/haze/Projects/Game/builds/linux/last_known.x86_64 --script /home/haze/Projects/Game/game/tests/checkpoint_process_check.gd -- read
```

Use equivalent absolute paths if your checkout is elsewhere. This is editor-driven validation of the exported pack, separate from native release-executable startup and human playtesting. Screenshots are test-only files under `/tmp/last-known-*.png`; game saves use engine-managed paths.

In restricted agent environments, Godot may report `Error attempting to create data dir`, editor-cache write errors, or editor socket errors. Here those were sandbox restrictions; rerunning with approved desktop permissions resolved them. Do not count a zero process exit as proof that the log has no errors.

## Verification recorded on 3 October 2026

- Foundation PR #1 merged with explicit user authorization. Chapter implementation runs on a separate feature branch.
- Import and source headless/graphical checks passed; foundation regression and Chapter 1 behavior checks reported zero failures.
- Release export and native executable headless/graphical startup passed. Exported-resource-pack graphical behavior check reported zero failures. A first run had an intermittent landing-entry assertion; the route probe/rerun passed, and the harness now prevents native pointer steering during scripted routes.
- Graphical driver: OpenGL 4.6, Mesa 26.2.2-arch1.1, Intel Arc (MTL), Compatibility. Chapter captures measured 1410 × 793 viewport pixels on this run; logical viewport is configured at 1280 × 720. Journal/ending readability inspected; placeholder sign billboards corrected for approach from either direction. No FPS/RAM benchmark is claimed.
- Artifact: `builds/linux/last_known.x86_64`, **73,550,976 bytes** (about 70.14 MiB), embedded PCK. Binaries, caches and downloaded templates stay ignored.
- Chapter 1 is implemented in placeholders; release readiness, finished art, human clue comprehension, native focus switching and Windows/macOS validation remain pending.

## Pending human checklist

1. Start a new expedition in the exported executable and reach the ending using the complete route above; try the optional letter and an alternate clue order.
2. Quit/relaunch after one clue, after restoring power, upstairs, and after completion. Continue must restore progress/settings at a safe room anchor. Try New confirmation and cancel it by continuing instead.
3. Test natural arrival/discovery and E/Escape skips, journal, record exit, pause/resume and held movement keys in each interface. Alt-tab away/back and resume explicitly; try Save, Return to title and Quit.
4. Judge stair/navigation feel, atmosphere, legibility at your preferred window size, and whether the corroboration/onward lead are understandable. Treat all clue text as proposed narrative.

Next bounded milestone: review the placeholder investigation and checkpoint flow, then build one representative art/audio scene and benchmark it before expanding the detail pass. See [Chapter 1 brief](source/chapter_01.md).
