# Mindblocks

Notes as cubes floating in 3D space. A small Godot 4 starter project for
thinking through big ideas spatially.

## Open it

1. Install Godot 4.4 or newer (the standard build, not .NET).
2. In the Project Manager: **Import** → pick `project.godot` in this folder.
3. Press **F5** (or the ▶ button) to run.

## Controls

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
| Snap a cube next to another | Move it close to another cube: a ghost shows where it will land; let go to snap (hold Shift to place freely) |
| No overlapping | A cube dropped, created or pasted inside / too close to another floats away to the nearest free spot; the other cube stays put |
| Rotate a cube freely | Hold R and move the mouse (selected or carried cube) |
| Turn a cube 90° | Arrow keys (selected cube) |
| Straighten a cube | Double-tap R (upright and lined up with the grid; position stays) |
| Link / unlink two notes | Select one, Shift+click the other |
| Recolor selected | 1–7 |
| Focus camera on selected | F |
| Delete selected | Delete / Backspace |
| Copy a cube by dragging | Hold Alt and drag a cube (or one of its arrows): a copy comes with you, the original stays |
| Copy / cut / paste | Ctrl+C or Ctrl+X on a selected cube, Ctrl+V pastes it where you're looking (a cut cube keeps its links on its first paste) |
| Undo | Ctrl+Z: undoes deletes, moves, rotations, new / copied / pasted / cut cubes, and text, color and mark edits (last 50 steps); a message top right says what was undone |
| Redo | Ctrl+Y or Ctrl+Shift+Z (cleared once you do something new) |
| Orbit | Right-drag |
| Pan | Middle-drag or Shift+right-drag |
| Zoom | Scroll |
| Fly | W A S D, Q / E for down / up, Shift = faster |
| Fly up / down | Space or E / Q |
| Toggle floor guides | G |
| Toggle help | H |

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

It's plain JSON: notes (id, text, color, position, status), links (pairs of ids),
and the camera position.

## How it's built

```
project.godot        GL Compatibility renderer, so it runs on laptops, phones and the web
main.tscn            one Node3D with main.gd; everything else is built in code
scripts/main.gd      environment, input, picking, dragging, links, editor UI, save/load
scripts/note.gd      one note: a cube with Label3D text on every face, outline, done/failed marks
scripts/camera_rig.gd orbit / pan / zoom / fly camera
```

A few design decisions worth knowing before you change things:

- **Notes are cubes with the text on all six faces**, so they read from any
  side. They keep their own rotation (saved as a quaternion); R + mouse turns
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
