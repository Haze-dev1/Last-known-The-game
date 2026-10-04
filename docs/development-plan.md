# Chapter-by-chapter development plan

## Decisions

Godot with typed GDScript; native Linux first. Kowloon is the geographic reference, with selected streets, distances, and interiors adapted for play. The game should remain lightweight. Windows and macOS exports follow platform testing later.

Godot 4.7.2 is verified installed and is the initial engine baseline. Compatibility is the verified foundation renderer. Chapter 1 investigation and checkpoints are implemented in placeholder geometry; narrative remains provisional. See [project structure](project-structure.md) for file placement and toolchain status. The Sunday 4 October 2026, 7–8 PM IST target is an attempt to deliver a playable chapter, not a commitment to complete the entire game.

**Shared-world decision (4 October 2026):** the user prioritised the whole Kowloon world before detailed POIs. This supersedes "complete one chapter before expanding the city". A streamed whole-Kowloon exterior world exists; see [world map pipeline](world-map-pipeline.md). Chapters are narrative progression within it. Chapter 1 remains a separate placeholder scene and regression test until its POIs move into the world.

## Milestones in order

1. **Define Chapter 1.** Write its opening, objective, clue chain, puzzle prerequisites, ending, and essential props. Suggested footprint: street, repair shop, apartment, utility room. Finish with a real discovery and a lead into Chapter 2. Keep unresolved full-story choices provisional.
2. **Prove the toolchain.** Install and pin Godot, create a minimal project, and run an exported Linux build. Establish a repeatable launch and error-checking workflow before detailed content work.
3. **Make a playable blockout.** Build the route in simple geometry at plausible scale. Add movement, collision, contextual interaction, and a readable computer screen. Test navigation and controls in the actual game.
4. **Finish the investigation in placeholders.** Implement evidence collection, explicit puzzle prerequisites, pause, checkpoint save/load, and the chapter ending. Check repeat interactions, clues found out of order, and resuming partway through the puzzle. Avoid a battery system that can permanently block progress.
5. **Create one representative art scene.** Add buildings, vegetation, light, and sound to one stretch. Compare renderer performance on the target laptop before repeating expensive techniques throughout the level.
6. **Complete the art and sound pass.** Reuse modular assets; detail reachable spaces; maintain asset sources and licenses. Preserve the tested clue route and object readability.
7. **Package and playtest.** Complete the exported build from a fresh save, then test checkpoint restoration, restart, input focus, settings, and exit. Record build size, memory, and performance. Clearly separate automated checks from human playtesting.

## Proposed budgets

Aim for 60 FPS at 1080p low settings on the current laptop and under 2 GB game RAM. The 500 MB packaged-chapter figure was a chapter budget, not a whole-world budget. Whole-world source, generated and packaged sizes are reported separately in the [pipeline document](world-map-pipeline.md). These are targets; measured results live with their hardware notes. Adjust scene complexity based on a representative benchmark. Hardware observed earlier: Core Ultra 7 155H, approximately 32 GB RAM, Intel Arc integrated graphics.

## Work ownership

Codex owns core implementation and integration. Claude reviews the clue logic and important changes. Gemini can research assets and handle isolated, inspectable content tasks. OpenCode is optional overflow for small tasks. The user judges atmosphere, movement, and whether the investigation is understandable.

Assign helpers bounded outputs and file ownership; avoid concurrent edits to shared scenes or game state. No external-agent tasks have been dispatched by this plan.

## Skill use

See [the shared skill library](../skills/README.md). Use scope discipline during implementation, correctness review for important changes, debugging when failures occur, and test-quality review where tests protect progression and saved state. Do not load all skills for each task.

## Immediate next step

The [proposed Chapter 1 brief](source/chapter_01.md) and exported street/shop foundation are available; see [setup and verification](setup.md). Chapter 1 now includes the apartment, utility room, corroborating records, onward lead, ending and checkpoints. Next, human-playtest the exported investigation, then benchmark one representative art/audio scene. The whole-Kowloon world is in place for exploration. Next: relocate Chapter 1 POIs to a real Sham Shui Po site inside it, then detail POIs. A survival simulation and additional chapters remain later work.
