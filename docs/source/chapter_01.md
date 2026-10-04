# Chapter 1 — the shop

Status: implemented in placeholder geometry with **proposed narrative**. Names, exact evacuation dates/addresses, sibling relationship and full-story ending remain unresolved. The new N-04 marking, handover text, photo description and staging are proposals, not approved canon. No geographic data or external artwork is imported.

## Arrival and goal

Start a new expedition on a quiet Kowloon-inspired street. A three-second first-person approach is skippable with E/Escape. Reach the repair shop, recover records, corroborate a return after evacuation, and find an onward lead. There are no present-day human NPCs, spoken dialogue or visible protagonist.

## Implemented locations

- Street and shop: the original foundation. Connect a portable supply brought on this expedition to the workbench, then inspect its saved service note. The supply serves one device and does not restore the municipal grid.
- Utility room: enter the left rear alcove of the shop. A printed closure notice and independent utility handover describe receipt of the revised N-04 notice after the station's last departure.
- Apartment: take the exterior service stair to the right of the shop and enter its upstairs rear doorway. A protected shop photograph, revised address list, acceptance letter and packed case establish investigation and personal context. The stairs use a smooth convex collision ramp under visual steps; no jumping is required.
- Departure marker: return to the street and inspect the onward-route marker only after the essential records are collected.

The photograph is a **textual stand-in** describing a recognizable historical reflection and a closure placard, not finished image art. It must be replaced with an approved authored photograph during the art pass. Storage survival, restoration details and actual geography remain research work.

## Evidence and dependencies

| Record | Access | What it supports |
| --- | --- | --- |
| Saved service note | Workbench power required | Repair work and an upstairs address list; author and chronology unconfirmed alone. |
| Utility closure notice | Freely accessible | Independent chronology for the revised N-04 placard received after station closure. |
| Shop photograph | Freely accessible upstairs | Missing person physically present in the shop; compare its placard with the utility record. |
| Revised address list | Freely accessible upstairs | Northern station handover desk, then the overflow school shelter. |
| Acceptance letter | Optional upstairs | Personal plans before the emergency; no evidence of later fate. |

Service note + closure notice + photograph enable the journal's corroborated reconstruction: the missing person returned after the station's final evacuation. This distinguishes identity from account activity and corroborates chronology with a physical record. The address list adds the onward lead. All four essential records are required before departure; the letter never replaces one.

Power, rooms and clues may be discovered in any order. Repeated reads add one record per ID. J opens the evidence journal with collected titles, current interpretation and any onward lead. Props remain available for rereading their complete text.

## First-person sequences and ending

Arrival completion and skipping restore the same street pose/input state. Closing the record that first completes corroboration triggers a 1.6-second first-person upward glance; natural completion and E/Escape skipping restore the original camera and walking. Its seen flag survives checkpoints; loading evidence never replays it unexpectedly.

After all essential evidence, interacting with the departure marker records Chapter 1 completion and displays the discovery plus the station/shelter lead. Escape returns to exploration; Continue restores the completed ending. Chapter 2 is not implemented, and this ending does not resolve the missing person's eventual fate.

## Checkpoints and input

Title offers New expedition and Continue checkpoint. New requires a second confirmation when a checkpoint exists. Autosaves occur after arrival, supply activation, reading evidence, first corroboration, sensitivity changes and departure. Pause offers manual save, return to title and Quit. Continue restores power, unique evidence, sequence flags, sensitivity and a named safe room anchor rather than an arbitrary stair/intersection position.

Records, journal, menus, sequences and ending own input while open; movement remains blocked. Escape returns to walking; focus loss pauses walking. A failed save keeps the session visible: Return to title is blocked, and Quit offers an explicit second click to leave without saving. A damaged primary can recover its previous valid backup; unrecoverable or incompatible checkpoints disable Continue and preserve the files until confirmed New.

## Acceptance and remaining work

Automated acceptance: rejected early departure/unpowered computer; all essential clues and optional letter; out-of-order/repeat consistency; physical stair ascent/entry/descent and original street collision; journal interpretation; arrival/discovery skips; pause/mouse/sensitivity; reload at partial, powered and completed states; safe spawn; corruption/backup/incompatible schema/write-failure behavior. Actual results and export commands are recorded in [setup](../setup.md).

Human acceptance remains pending: fresh exported playthrough to ending, checkpoint resume, native focus switching, Quit/restart, movement feel, visual atmosphere and clue comprehension. Placeholder implementation completion does not mean release ready.

Next bounded milestone: human review of this investigation, then one representative art/audio scene and a measured performance benchmark before wider detail placement. Keep narrative proposals reviewable and preserve the tested route.
