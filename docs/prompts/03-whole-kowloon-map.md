# Claude task — build the whole Kowloon world

Work in the current checkout of Last Known. Discover the repository root rather than assuming an absolute checkout path. PR #2 is merged into main at `7b08540c49e8472ce4aa7e78adbcc76bb44d9d70`. Verify the remote and start from main containing that merge, preserving unrelated local work.

Build the whole geographically grounded Kowloon map in Godot 4.7.2 with typed GDScript and a Linux exploration build. Implement finished files and a runnable map, not only a proposal or a small demonstration district. The user deliberately prioritizes the whole world before detailed POIs. Chapters remain narrative progression within this shared world, not limits on its geography.

## Context and authority

Read `AGENTS.md`, `docs/tracker/progress.json`, `docs/project-structure.md`, `docs/setup.md`, and `docs/source/map.md` plus `world.md`. Inspect current Chapter 1 code and its tests before changing shared player or UI behavior. The city is reclaimed through ordinary vegetation growth over decades, with first-person anonymity, no present-day human NPCs, and no spoken dialogue.

Use relevant local skills: Godot 3D essentials, GDScript patterns, export, scope discipline, API verification, and debugging. Read supporting references as needed. Confirm installed versions and renderer capabilities; validate community examples. Respect host permissions.

This task supersedes the older instruction to expand only one chapter or one street. Update map and development documents to reflect the shared-world decision. Preserve the existing chapter as a selectable regression/test scene while the new world develops; detailed relocation of its POIs is later work.

## Geographic scope and realism

Cover Kowloon as a whole, rather than only Sham Shui Po. Establish an explicit geographic polygon from authoritative boundaries and document whether it includes New Kowloon. Prefer the commonly understood Kowloon urban area including New Kowloon when sources permit; label the chosen extent clearly instead of quietly substituting a smaller district. Adjacent hills or islands outside the polygon can be background scenery.

Use actual road alignments, building footprints, elevations, rail corridors, parks, and coastlines. Keep metric scale and documented coordinate transforms. Controlled simplification and fictional access changes are allowed; preserve district relationships and recognizable urban layout. Never invent a uniform grid and label it real Kowloon.

Research and obtain reusable sources. Start with Hong Kong Lands Department iB1000/CSDI datasets, official 3D and terrain products, and Hong Kong OpenStreetMap extracts from Geofabrik. Inspect metadata and actual files before choosing the pipeline. Check accuracy, coordinate systems, download size, and license/attribution requirements. Some terrain products include vegetation or elevated structures; distinguish those from bare ground. Do not scrape proprietary map tiles or assume screenshots are reusable geometry.

Keep a source manifest with URLs, licenses, download date, bounds, coordinate system, processing steps, checksums, and limitations. Prefer pinned dataset snapshots. If a preferred service fails, use a suitable licensed alternative and record what changed. Escalate only real gaps that prevent whole-map completion; missing height attributes can use explicitly documented inferred heights without pretending they are surveyed.

## World deliverable

Produce a continuous explorable exterior world covering the documented polygon:

- Terrain and coastline aligned with the source geometry.
- Connected road and pedestrian surfaces, including intersections and meaningful elevation changes. Treat bridges and tunnels distinctly where source information supports it.
- Buildings derived from real footprints, with varied heights and shared facade materials. Preserve major geographic landmarks as simplified silhouettes, without needing detailed story POIs yet.
- Recognizable district variation through source-based land use, building scale, street character, parks, and industrial/waterfront areas.
- A deliberate overgrowth pass: growth concentrated near soil, parks, exposed plots, water, and damaged surfaces; concrete and architecture remain visible. Use reproducible placement and reusable assets.
- Collision for reachable ground and nearby buildings, safe spawn locations, boundaries, and a recovery action if the player becomes stuck.
- A separate world-exploration entry point with walking, a clearly labeled developer free-flight mode, district jump points, and an overview map showing the coverage polygon and loaded regions. These tools help inspect all districts; they do not replace real walking routes.

The first broad pass may simplify buildings, but continue through a coherent exterior presentation pass. Exclude identical white cubes everywhere, randomly scattered skyscrapers, uniform neon materials, vines covering every wall, and heavy fog hiding missing geography. Use restrained weathered concrete, practical street detail, varied facade rhythm, and locally appropriate vegetation. Final art across every building is outside this task; convincing world structure and a consistent explorable exterior treatment are inside it.

## Implementation and performance

Use Godot for runtime rendering and Python or appropriate GIS tools for offline processing. Select the smallest tools that handle the real dataset; avoid constructing a custom GIS framework. Store raw/source assets in `assets-source/`, processing tools in `tools/`, runtime world assets/scenes in `game/world/`, and exports under `builds/linux/`. Large data requires a Git/LFS decision before staging; keep reproducible download manifests for data excluded from Git.

Build spatial chunks with documented size, distance-based loading/unloading, inexpensive distant silhouettes, and collision limited to relevant nearby areas. Keep one scene coordinate convention, unit scale, stable chunk IDs, and deterministic generation. Validate seam alignment and stop memory accumulation when revisiting districts. Do not instantiate every detailed building and plant for the entire city at startup.

Measure a representative dense street before expanding its detail everywhere. The provisional laptop targets remain 60 FPS at 1080p low settings and under 2 GB runtime RAM; record actual results and adjust detail. The old 500 MB chapter budget is not a confirmed whole-world budget: report actual source, generated, and packaged sizes separately. Change renderer only with recorded comparison and regression checks.

## Execution and autonomy

Keep going when the next action does not need user input. Put progress notes alongside the next action; do not end with “want me to continue?” Stop only for a genuine missing decision/access requirement or before destructive operations, force-pushing, or unrelated changes outside the repository. Use normal permission mechanisms for required tool installation and downloads.

For this large task, use subagents if your harness supports them: one for source/coordinate research, one for offline processing, and one for rendering/performance checks. Assign distinct files and contracts. Keep one integrator responsible for shared world formats, scene assembly, and tracker writes. Verify their artifacts and checks before accepting their reports; do not invent delegation if unavailable.

Persist work in `docs/tracker/progress.json` using a whole-world task and submilestones, and append concise observations to root `debug.log`. Write detailed decisions, limitations, and reproducible commands in `docs/world-map-pipeline.md`. Resume from those files after context compaction. Once a decision is settled, revisit it only when new evidence requires it.

## Finish line

Done means all of the following are satisfied or explicitly recorded as blocking completion:

1. The complete documented Kowloon polygon has generated terrain, road/building coverage, district jump points, and a visible overview coverage map. Dataset omissions and simplifications are disclosed.
2. An offline pipeline can reproduce the runtime map from pinned inputs, with a manifest and verified commands. Import geometry checks cover bounds, scale, building counts, missing coverage, and chunk seams.
3. The Linux map-exploration build exports and starts. Walking is tested through representative districts, intersections, slopes, and chunk boundaries; the developer flight mode permits inspection of the whole world.
4. Streaming is checked across district jumps and repeated travel; stale collision, gaps, failure to unload, and unbounded memory growth are addressed.
5. Capture and inspect actual screenshots of multiple districts, a dense street, park/overgrowth, waterfront, and an aerial overview. Confirm they match the geographic source and chosen visual direction. If graphical access is unavailable, mark visual acceptance pending and provide the runnable artifact for user inspection.
6. Benchmark representative routes on actual hardware and report renderer, resolution, settings, FPS/frame times, peak RAM, load times, and build size. Headless execution alone does not establish visual performance.
7. Existing Chapter 1 tests still pass or any legitimate change is explained and verified. Do not discard regression tests merely to obtain a passing result.
8. Docs, source attribution, tracker, and debug log reflect actual results. Review the diff against main for merge-blocking defects only, with file/line and reproduction evidence for each finding.

Use a descriptive feature branch, focused commits, push it, and open a draft PR. This authorizes branch/commit/push/draft-PR work, not merging or publishing a public game release. Preserve the user's other changes.

## Final report

End with exactly these headings: **Blocked on me**, **Changed**, **Found**. Put required user actions first, or state none. Include the world coverage, playable artifact and launch instructions, pipeline/source manifest, inspected screenshots, measured performance, regression results, PR link, and next step for detailed POIs. Mark anything you could not confirm and say where you checked. Do not describe a partial district as a finished whole map.
