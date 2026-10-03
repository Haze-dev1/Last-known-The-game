# Run and verify the Linux foundation

Run the street/shop/power/clue slice with Godot 4.7.2 and the Compatibility renderer. Commands below run from the repository root. This milestone has session-only progress and sensitivity; checkpoint saving belongs to the next task.

## Engine and templates

`godot --version` observed `4.7.2.stable.arch_linux.ed1daf0bf`. The official Linux release template reports `4.7.2.stable.official.ed1daf0bf`, the same engine revision. Matching Linux debug/release templates and `version.txt` are installed in `~/.local/share/godot/export_templates/4.7.2.stable/`. The preset is **Linux Foundation**, x86_64, with an embedded PCK.

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

Wait for the three-second arrival, or skip with E/Escape. Walk straight into the repair shop. Look at the computer and press E: it rejects access without power. Walk back to the yellow portable supply beside the entrance, look at it, and press E. Return to the computer and press E to read the saved note. The HUD records one clue even after repeated reads. Escape or the screen's button returns to walking. You can activate the supply before inspecting the computer.

WASD moves; mouse looks; E interacts; Escape opens/closes pause while walking and leaves the computer while reading. Pause exposes mouse sensitivity and Quit. Movement stops while arrival, computer, or pause owns input. Losing focus pauses walking; resume explicitly after returning. There are no NPCs, spoken dialogue, combat, resource depletion, or save files in this slice.

## Import, check, export

```bash
godot --headless --path game --import
godot --headless --path game --script res://tests/foundation_check.gd
godot --path game --script res://tests/foundation_check.gd
mkdir -p builds/linux
godot --headless --path game --export-release 'Linux Foundation' ../builds/linux/last_known.x86_64
./builds/linux/last_known.x86_64 --headless --quit-after 240
./builds/linux/last_known.x86_64 --quit-after 240
```

`--quit-after` counts frames, not seconds. The behavior check returns nonzero on an assertion failure and prints `FOUNDATION CHECK: 0 failures` on success. It uses the real scene, physics, raycasts, injected key/mouse events, and connected UI signals. It walks the street-to-workbench route; supply and subsequent computer approach positions are placed by the harness. It also checks wall occlusion, repeated reads, power-first order, held movement in menus, and arrival completion/skip position equivalence.

The headless driver cannot capture the pointer, so pointer capture/look are checked only in the graphical run. The graphical harness isolates window-manager focus changes and explicitly exercises the production focus-loss handler. It saves viewport frames to `/tmp/last-known-{street,shop,clue,pause}.png`; that temporary path is test-only. Normal game paths remain engine-managed.

In restricted agent environments, Godot may report `Error attempting to create data dir`, editor-cache write errors, or editor socket errors. Here those were sandbox restrictions; rerunning with approved desktop permissions resolved them. Do not count a zero process exit as proof that the log has no errors.

## Verification recorded on 3 October 2026

- Minimal scene imported, started headlessly, and exported before blockout work.
- Final import: no observed script/resource errors. Headless and graphical real-scene behavior checks: zero failures.
- Release export: succeeded; executable headless startup and graphical startup both exited successfully without observed errors.
- Graphical driver: OpenGL 4.6, Mesa 26.2.2-arch1.1, Intel Arc (MTL), Compatibility. Captured viewport: 2880 × 1620; configured logical viewport: 1280 × 720. Screens inspected for readable clue/menu and route visibility. Overlapping street/shop floor surfaces discovered during inspection were corrected.
- Artifact: `builds/linux/last_known.x86_64`, **73,534,600 bytes** (about 70.13 MiB). Tests are excluded from the release pack.
- These checks establish automated behavior and graphical startup. No human playable review, full-chapter release test, FPS benchmark, memory benchmark, Windows test, or macOS test is claimed.

## Pending human checklist

1. Play the exported build from launch through no-power feedback, supply activation, clue reading, repeated reading, and return to walking. Check route readability and movement feel.
2. Compare natural arrival against E and Escape skips; try mouse look and collisions along walls, entrance, shelves, and workbench.
3. Pause/resume, change sensitivity, leave the computer using Escape and the button; hold movement keys during menus. Alt-tab away/back and verify pause plus explicit recapture on resume.
4. Use Quit and restart; expect power/evidence/sensitivity to reset. Judge the quiet tone and readable UI at your preferred window size.

Next bounded task: complete Chapter 1's investigation and checkpoint saving, after reviewing the proposed [chapter brief](source/chapter_01.md).
