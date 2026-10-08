# Mindblocks

Notes as cubes floating in 3D space. A small Godot 4 project for thinking
through big ideas spatially: fly around your notes, link them into stacks that
move as one, and let Claude break a big task down into blocks or reorganise
the space for you.

▶ **[Play Mindblocks in your browser on itch.io](https://rkr8.itch.io/mindblocks)**:
no download needed. The AI features need your own Anthropic API key.

## Open it

1. Install Godot 4.4 or newer (the standard build, not .NET).
2. In the Project Manager: **Import** → pick `project.godot` in this folder.
3. Press **F5** (or the ▶ button) to run.

## Controls

On macOS, use Cmd wherever this says Ctrl (Cmd+Z, Cmd+C, Cmd+Enter…); the in-app help shows Cmd there.

| Action | Input |
|---|---|
| Look around | Move the mouse (clicks act at the crosshair) |
| Read a block | Its text shows on the face turned toward you, always upright, and moves to another face as you fly around |
| Pause / free the cursor | Esc; Continue or Esc again to resume. The pause menu has ▶️ Continue, 🆕 New notespace, 🧩 Break down a task, ✨ Add with AI, 🧭 Arrange notes around me and 🚪 Exit |
| Quit | Esc → Exit (saves first) |
| Start over | Esc → New notespace → Delete and start new: clears all blocks and links and brings back the first-run overview stacks and starting view (Ctrl+Z brings the old notespace back) |
| New note | Double-click empty space |
| New linked cube next to another | Click a cube, then click the + off one of its faces (it lands directly beside that face; faces with a cube already against them have no +) |
| Edit note | Double-click it, or select + Enter |
| Close editor | Close button, Ctrl+Enter, Esc, or click outside |
| Mark done / failed | Mark done / Mark failed in the editor (click again to clear); marked cubes turn 50% see-through |
| Move note | Hold click on it and look around / fly — it's carried along |
| Move note nearer / farther | Scroll while carrying |
| Move a cube along its own sides | Select it, then drag one of its colored arrows (red X, green Y, blue Z; they turn with the cube) |
| Snap a cube next to another | Move it close to another cube: a ghost shows where it will land; let go to snap (hold Shift to place freely); it clicks when it lands |
| No overlapping | A cube dropped, created or pasted inside / too close to another floats away to the nearest free spot; the other cube stays put |
| Rotate a cube freely | Hold R and move the mouse (selected or carried cube) |
| Turn a cube 90° | Arrow keys (selected cube) |
| Straighten a cube | Double-tap R (upright and lined up with the grid; position stays) |
| Link / unlink two notes | Select one, Shift+click the other (a click sounds; a lower one for unlinking) |
| Anchor blocks | An anchor (thick dark frame) carries every block linked to it, directly or through other blocks, when you move it, so linked stacks move as one, wobbling a little on the way and settling exactly where you put them; Ctrl+Z puts them all back. Toggle Anchor in the editor. AI group titles start as anchors. An anchor only turns left / right (R + mouse, ← / →, R R to straighten), and its whole stack swings round after it on the same springs, settling in its exact shape (one undo step) |
| Recolor selected | 1–7 |
| Focus camera on selected | F |
| Delete selected | Delete / Backspace |
| Copy a cube by dragging | Hold Alt and drag a cube (or one of its arrows): a copy comes with you, the original stays |
| Copy / cut / paste | Ctrl+C or Ctrl+X on a selected cube, Ctrl+V pastes it where you're looking (a cut cube keeps its links on its first paste) |
| Undo | Ctrl+Z: undoes deletes, moves, rotations, new / copied / pasted / cut cubes, text, color, mark and anchor edits, stack moves and turns, arranging, and each AI breakdown or AI edit as a whole (last 50 steps); a message top right says what was undone |
| Redo | Ctrl+Y or Ctrl+Shift+Z (cleared once you do something new) |
| Orbit | Right-drag |
| Pan | Middle-drag or Shift+right-drag |
| Zoom | Scroll while orbiting (right-drag); scrolling while just flying does nothing |
| Fly | W A S D, Q / E for down / up (18 units/s), Shift = much faster (60); holding a direction speeds up to 2.5× over 1.5 s |
| Fly up / down | Space or E / Q |
| Arrange notes around me | O, or Esc → Arrange notes around me: every stack (blocks connected by links; a lone block counts as one) goes on one circle round you at eye level, equally spaced (360° / number of stacks), the first straight ahead, in the order they already were around you. The circle is big enough for each stack to be seen whole and for neighbours to stay apart. Long stacks are turned so you see their full width. Doing it again without moving changes nothing. You stay where you are; Ctrl+Z puts everything back |
| Toggle floor guides | G |
| Break down a task with AI | B, or Esc → Break down a task: describe a big task, and Claude lays it out as linked blocks in a new notespace (groups of tasks, each with its subtasks around it). If there are blocks already, it asks before erasing them. Ctrl+Enter generates; Ctrl+Z brings the old blocks back. Needs an Anthropic API key, see below |
| Add or change blocks with AI | Shift+B, or Esc → Add with AI: say what to add or change, and Claude adds, rewrites, links / unlinks, marks, recolors, removes, moves or rearranges blocks and whole stacks in the current space (e.g. "organise this", "put the marketing stuff next to Shop"). New blocks branch out from the block they belong under; changed ones pulse. Ctrl+Z undoes it all in one step |
| Toggle help | H (hidden at start; a small "H to toggle help" note bottom left is always shown) |

Closing the editor on an empty note deletes it.

## Export and share

`export_presets.cfg` has two presets, each a single file with everything packed
inside, written to `build/` (ignored by git):

- **Windows Desktop** → `build/windows/Mindblocks.exe` (64-bit)
- **Linux** → `build/linux/Mindblocks.x86_64` (64-bit)

The app icon is `icon.svg` (also the window icon); the `.exe` gets it from
`icon.ico` (16–256 px), which Godot embeds by itself.

1. Once per Godot version: Editor → **Manage Export Templates** → **Download
   and Install** (about 1 GB).
2. Project → **Export…** → pick the preset → **Export Project**, or from a
   terminal in this folder:
   `godot --headless --path . --export-release "Windows Desktop" build/windows/Mindblocks.exe`
   or `godot --headless --path . --export-release "Linux" build/linux/Mindblocks.x86_64`
3. Share the file (zip it for sending).
   - **Windows:** it's not code-signed, so SmartScreen may say "Windows
     protected your PC": click **More info** → **Run anyway**.
   - **Linux:** make it executable once (`chmod +x Mindblocks.x86_64`), then
     double-click it or run `./Mindblocks.x86_64`.

Notes and the API key live in each user's own app data folder (see below),
never in the build, so don't worry about shipping yours. Anyone who wants the
AI features pastes their own Anthropic API key the first time they press B or
Shift+B; everything else works without one.

## Play in the browser (itch.io)

The live version is at [rkr8.itch.io/mindblocks](https://rkr8.itch.io/mindblocks).

There's also a **Web** export preset → `build/web/index.html` (single-threaded,
so hosts don't need special headers). To put it on itch.io:

1. Export it: `godot --headless --path . --export-release "Web" build/web/index.html`
2. Zip the *contents* of `build/web` (so `index.html` is at the top of the zip).
3. On itch.io: **Upload new project** → Kind of project **HTML** → upload the
   zip and tick **This file will be played in the browser**.
4. Embed options: viewport **1280 × 760**, enable **Fullscreen button**, leave
   **SharedArrayBuffer support** and **Mobile friendly** off.

In the browser, click Continue to grab the mouse; Esc (which the browser uses
to free the mouse) brings the menu back. The menu has no emoji there (browsers
give Godot no emoji font), and since a page can't close its own tab, Exit
saves, leaves fullscreen and shows "Saved. You can close this tab now." Text uses the bundled Noto Sans with
distance-field rendering, which stays crisp at any size in the browser. Notes are saved in that browser. The AI
features need each visitor's own Anthropic API key, which also stays in their
browser.

### Deploying to itch.io

Updates go up with itch's command-line tool [butler](https://itch.io/docs/butler/):

1. Once: install butler and run `butler login` (it opens your browser to approve).
2. Every update: `./deploy_web.sh`. It exports the Web build and runs
   `butler push build/web rkr8/mindblocks:html5`, uploading only what changed,
   with the git version as the build number.
3. After the very first push: on the itch page, tick **This file will be played
   in the browser** on the `html5` upload, and delete any zip uploaded by hand,
   so there's just one browser upload.

## Where your notes live

Everything autosaves to `user://notes.json`. That's:

```
Linux:   ~/.local/share/godot/app_userdata/Mindblocks/notes.json
macOS:   ~/Library/Application Support/Godot/app_userdata/Mindblocks/notes.json
Windows: %APPDATA%\Godot\app_userdata\Mindblocks\notes.json
```

The app used to be called Spatial Notes. If there's no Mindblocks save yet but
there is one in the old `Spatial Notes` folder next to it, it's copied over on
startup (the old file is left alone). That's only tried once: a
`migrated_from_spatial_notes` marker file next to the save remembers it, so a
notespace you remove later doesn't come back from the old folder.

With no save at all (and after Esc → New notespace), the app starts with an
overview: four anchored stacks around you (Welcome to Mindblocks, Blocks,
Organise, AI with Claude) whose blocks explain the main features and keys.

It's plain JSON: notes (id, text, color, position, rotation, status, anchor), links (pairs of ids),
and the camera position.

## AI: break down a task, add with AI

Both use Claude (`claude-opus-5-5`, through the Anthropic Messages API) and
return structured JSON that the app turns into blocks.

**Break down a task** (B) starts a new notespace. Claude splits a big task
into 2–6 groups of related work: each group has a title, its tasks and their
subtasks. Each group grows like a 3D mind map: its tasks spread out around and
below the title block, in every direction including depth, and each task's
subtasks fan out the same way around that task, away from the title. Blocks are
about 5–8 apart, never closer than 3.4, with a little randomness so it doesn't
look machine-made. Links connect title → task → subtask, each group gets its
own color, and groups sit side by side with a gap between them. If the space already has blocks, the panel asks before
erasing them. They're only erased once Claude's answer has arrived, and the
whole swap is one undo step.

**Add with AI** (Shift+B) sends Claude every block (id, text, done / failed,
color, position) and link, along with what you ask for. Claude answers with
changes: new blocks (each under a parent block, or as a new group), rewritten
texts, done / failed marks, colors, new or removed links, and removed blocks.
A new block branches out from its parent the same way, away from the block
the parent hangs from, into the most open space nearby. A new group gets its
own spot in front of you, clear of everything else.

Add with AI can also reorganise the space. Claude says where things go
relative to each other, and the app works out the exact positions:
- **move** puts one block on a side (left / right / above / below / front /
  behind, as you see it) of another block.
- **move_stack** moves a whole stack (everything linked to a block) next to
  another block or stack, or into free space in front of you.
- **arrange** lays a stack out again as a tidy 3D mind map around its anchor,
  which stays put.

Moved blocks keep clear of everything else (stacks by 4 units) and fly to their
new places with a small overshoot. Ids that don't match a block are skipped. Everything is one undo step, and messages show Claude's one-line summary and what changed (e.g. "Moved blocks around (7)").

Both need an Anthropic API key (create one in the Claude Console under
Settings → API Keys; the API is billed separately from a Claude.ai plan, so the
account needs some credit). If `ANTHROPIC_API_KEY` is set, that one is used.
Otherwise the panel asks for one once and keeps it in `user://settings.cfg` (in
the same folder as `notes.json`, never in the notes or the repo). Delete that
file to forget the key. A key the API rejects is forgotten automatically.

If Claude's safety checks decline a request, the API retries it on its
recommended fallback model (`fallbacks: "default"`).

## How it's built

```
project.godot        GL Compatibility renderer, so it runs on laptops, phones and the web
main.tscn            one Node3D with main.gd; everything else is built in code
scripts/main.gd      environment, input, picking, dragging, links, editor UI, AI breakdown, save/load
scripts/note.gd      one note: a cube with its text on the face toward you, outline, done/failed marks
scripts/camera_rig.gd orbit / pan / zoom / fly camera
scripts/room.gd      the home-office room the notes float in
fonts/               Noto Sans (SIL Open Font License, see NotoSans-LICENSE.txt), the web build's UI font
```

A few design decisions worth knowing before you change things:

- **Notes are cubes with their text on one face**: the face turned most
  toward the camera. As you fly around, the text crossfades to whichever face
  now faces you best (with a little hysteresis so it doesn't flicker at 45°),
  and it's always upright: on side faces it stays level with the world however
  you move, and on top / bottom faces it clicks round in quarter turns to face
  you, so it's never upside down or sideways. They keep their own rotation (saved as a quaternion); R + mouse turns
  one trackball-style around the camera's axes, arrow keys do eased 90° turns.
  New notes start upright with a face toward the camera.
- **Picking doesn't use physics.** `_pick()` transforms the mouse ray into
  each cube's local space and does a ray/box slab test. Simple and exact.
- **Mouse look, game style.** The cursor is captured and moving the mouse
  turns the camera in place; clicks pick at the screen center (crosshair).
  Esc frees the cursor and shows a pause menu.
- **Dragging carries the note with the camera.** Its offset is stored in
  camera space, so it follows looking, flying and orbiting. Scrolling while
  dragging moves it along the camera→note line, so it stays at the same spot
  on screen while changing depth.
- **Text is displayed in 3D but edited in 2D.** `Label3D` renders the note; a
  normal `TextEdit` panel edits it, with live preview. Much simpler than
  editable text inside 3D, and it works with touch.
- **Cubes** are a `BoxMesh` with a small shader that darkens the face edges
  so the shape reads clearly, lit by a directional light (with a little
  self-glow so colors stay bright). Selection is an inverted-hull outline.
- **Anchors** carry their stack. When an anchor is grabbed, every block linked
  to it (transitively, through any links) records its offset from the anchor and
  is pulled toward that spot by a damped spring (`FOLLOW_*` in main.gd), so the
  stack lags, overshoots and wobbles a little, tilting with its speed, with
  blocks more links away a bit looser. Once the anchor has landed and the stack
  has come to rest, every block is put exactly in place. Snapping is decided by the
  anchor alone, then the whole stack is shifted clear of outside blocks.
- **All cubes are the same size; the text scales to fit a face.**
  `_fit_font_size()` binary-searches the largest font size at which the
  wrapped text fits (without splitting words), so one word is huge and a
  paragraph is small.
- **A giant home office; you're the size of a fly.** `scripts/room.gd` builds a
  cozy room from plain boxes, cylinders and spheres (no asset files), laid out
  in ~10 cm "room units" and shown `SCALE` (5) times bigger around you. A block
  is a sugar cube, the laptop (with keycaps) is about 15 blocks wide, the desk
  is a big plateau, and the lamp a tower. Also: wooden floor and rug, a mug, an
  office chair, a bookshelf, a bed, plants, a door, pictures and a wall clock,
  plus a few glowing dust motes drifting in the lamp light. You start hovering
  just above the desk, with the welcome stacks floating over the laptop and
  lamp. The camera can't leave the room, and Arrange notes around me keeps
  stacks inside it when they fit. The desk lamp and ceiling lamp are the only
  extra lights, with no shadows, so note text stays clear; a faint warm haze
  softens the far side of the room.
- **Nothing passes through the furniture.** The room lists its solid parts as
  rough boxes (`SOLIDS`). Every frame the camera and every note are pushed out
  of them and kept inside the walls, the shortest way out, so flying or
  dragging along a surface slides along it. A note pressed against something
  (carried into it, or part of a stack pushed into it) flattens against it, by
  how hard it's pushed, and springs back with a little wobble once it's free;
  the first touch while moving clicks softly. Only the look is squashed, never
  the saved position. A stack let go against something is shifted clear of it.
- **Flying across it.** Holding a direction speeds up over 1.5 s to 2.5 times
  the speed (normally 18 → 45 units/s, with Shift 60 → 150), so crossing the
  room takes a few seconds; letting go resets it.
- **Kept light on the GPU.** The room's ~300 parts are merged into one mesh per
  color at startup (about 50 draw calls in all instead of 120), its materials
  are lit per vertex (they're flat colors, so it looks the same), and it has
  only one extra light, the desk lamp. The frame rate is capped at 60, 30 while
  paused and 10 while the window is in the background. To check on a machine:
  `godot --path . -- --perf` prints frame rate and draw calls every 2 s, and
  `--nomsaa` turns antialiasing off (on the web: `?perf&nomsaa` in the address).
- **Starry night outside.** The window has no glass: the scene's background
  shows through it, a small sky shader (`SKY_SHADER`) with a sparse sprinkle of
  dim stars (`SKY_STAR_AMOUNT`, `SKY_STAR_BRIGHTNESS`).
- **Depth guides.** A drop line and a colored ring under every note, landing on
  whatever is right below it (the desk, the bed, the top of the bookshelf, or
  the floor), show each note's height and floor position
  at a glance (G toggles them). Links are camera-facing ribbons with a fixed
  world width, so nearer links look thicker, and they fade with distance.
- **The camera can't enter cubes.** After the camera moves each frame,
  `_keep_camera_outside_notes()` pushes it out of any cube (plus a small
  margin) along the shortest way out, so it slides along faces.
- **Focus darkening.** Whatever note you're aiming at (or carrying / editing)
  sets the focus depth; notes behind it turn darker the farther back they are.

## Ideas for next steps

- **Obsidian mode:** read `.md` files from a vault folder as notes, keep only
  positions and colors in the JSON, and draw `[[links]]` as connection lines.
- **Touch controls:** two-finger drag to orbit, pinch to zoom
  (`InputEventScreenDrag`, `InputEventMagnifyGesture`). One-finger already
  works as a mouse.
- **Search:** type to highlight matching notes and fly to them.
- **Multiple spaces:** one JSON file per subject, with a switcher.
- **Visible clusters:** anchors already move linked stacks together; a faint
  translucent hull around each stack would show where one ends.
- **Richer notes:** images, or Markdown via `RichTextLabel` in a `SubViewport`.
- **Export:** Android and Web exports work with the Compatibility renderer.
