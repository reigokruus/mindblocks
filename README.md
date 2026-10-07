# Mindblocks

Notes as cubes floating in 3D space. A small Godot 4 starter project for
thinking through big ideas spatially.

## Open it

1. Install Godot 4.4 or newer (the standard build, not .NET).
2. In the Project Manager: **Import** → pick `project.godot` in this folder.
3. Press **F5** (or the ▶ button) to run.

## Controls

On macOS, use Cmd wherever this says Ctrl (Cmd+Z, Cmd+C, Cmd+Enter…); the in-app help shows Cmd there.

| Action | Input |
|---|---|
| Look around | Move the mouse (clicks act at the crosshair) |
| Pause / free the cursor | Esc; Continue or Esc again to resume |
| Quit | Esc → Exit (saves first) |
| Start over | Esc → New notespace → Delete and start new: clears all blocks and links and brings back the first-run blocks and starting view (Ctrl+Z brings the old notespace back) |
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
| Anchor blocks | An anchor (thick dark frame) carries every block linked to it, directly or through other blocks, when you move it, so linked stacks move as one, wobbling a little on the way and settling exactly where you put them; Ctrl+Z puts them all back. Toggle Anchor in the editor. AI group titles start as anchors |
| Recolor selected | 1–7 |
| Focus camera on selected | F |
| Delete selected | Delete / Backspace |
| Copy a cube by dragging | Hold Alt and drag a cube (or one of its arrows): a copy comes with you, the original stays |
| Copy / cut / paste | Ctrl+C or Ctrl+X on a selected cube, Ctrl+V pastes it where you're looking (a cut cube keeps its links on its first paste) |
| Undo | Ctrl+Z: undoes deletes, moves, rotations, new / copied / pasted / cut cubes, and text, color and mark edits (last 50 steps); a message top right says what was undone |
| Redo | Ctrl+Y or Ctrl+Shift+Z (cleared once you do something new) |
| Orbit | Right-drag |
| Pan | Middle-drag or Shift+right-drag |
| Zoom | Scroll while orbiting (right-drag); scrolling while just flying does nothing |
| Fly | W A S D, Q / E for down / up, Shift = much faster |
| Fly up / down | Space or E / Q |
| Toggle floor guides | G |
| Break down a task with AI | B, or Esc → Break down a task: describe a big task, and Claude lays it out as linked blocks in a new notespace (groups of tasks, each with its subtasks around it). If there are blocks already, it asks before erasing them. Ctrl+Enter generates; Ctrl+Z brings the old blocks back. Needs an Anthropic API key, see below |
| Add or change blocks with AI | Shift+B, or Esc → Add with AI: say what to add or change, and Claude adds, rewrites, links / unlinks, marks, recolors or removes blocks in the current space. New blocks branch out from the block they belong under; changed ones pulse. Ctrl+Z undoes it all in one step |
| Toggle help | H (hidden at start; a small "H to toggle help" note bottom left is always shown) |

Closing the editor on an empty note deletes it.

## Where your notes live

Everything autosaves to `user://notes.json`. That's:

```
Linux:   ~/.local/share/godot/app_userdata/Mindblocks/notes.json
macOS:   ~/Library/Application Support/Godot/app_userdata/Mindblocks/notes.json
Windows: %APPDATA%\Godot\app_userdata\Mindblocks\notes.json
```

The app used to be called Spatial Notes. If there's no Mindblocks save yet but
there is one in the old `Spatial Notes` folder next to it, it's copied over on
startup (the old file is left alone).

With no save at all, the app starts with four linked blocks explaining the basics.

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
own spot in front of you, clear of everything else. Ids that don't match a block are
skipped. Everything is one undo step, and a message says what changed.

Both need an Anthropic API key. If `ANTHROPIC_API_KEY` is set, that one is used.
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
- **Depth guides.** A faint floor grid, plus a drop line and a colored ring
  on the floor under every note, show each note's height and floor position
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
- **Groups / clusters:** a translucent box or sphere you can drop notes into
  and move together.
- **Richer notes:** images, or Markdown via `RichTextLabel` in a `SubViewport`.
- **Export:** Android and Web exports work with the Compatibility renderer.
