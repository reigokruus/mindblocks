extends Node3D
## A single note: a cube floating in 3D space. Its text shows on one face only:
## the one turned most toward the camera, crossfading to another face as the
## camera moves round, and turned in quarter turns to read upright from where you are.
## Every note is the same size; the text is scaled to fill a face, so a single
## word is huge and a paragraph is small.
## Notes keep their own rotation (they don't turn toward the camera); main
## rotates them on request. Built entirely in code: a lit cube with darkened
## edges, a white inverted-hull selection outline, and a Label3D per face.
## Main also sets a depth effect: notes behind the one in focus go darker.

const SIZE := 2.0  # cube side
const PAD := 0.16
const PIXEL_SIZE := 0.004
const MIN_FONT_SIZE := 8
const MAX_FONT_SIZE := 200
const BREAK_FLAGS := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
## Outward normal and text "up" for each face.
const FACES: Array[Array] = [
	[Vector3.BACK, Vector3.UP], [Vector3.FORWARD, Vector3.UP],
	[Vector3.RIGHT, Vector3.UP], [Vector3.LEFT, Vector3.UP],
	[Vector3.UP, Vector3.FORWARD], [Vector3.DOWN, Vector3.BACK],
]

const CUBE_SHADER := """
shader_type spatial;
render_mode cull_back, fog_disabled;
// Two versions are compiled: opaque, and see-through for done / failed notes
// ("//ALPHA" is uncommented for the second one).

uniform vec4 color : source_color = vec4(1.0);
uniform float half_size = 1.0;
uniform float anchor = 0.0;  // 1 draws the anchor frame

varying vec3 lpos;
varying vec3 lnorm;

void vertex() {
	lpos = VERTEX;
	lnorm = NORMAL;
}

void fragment() {
	// Distance from this pixel to the nearest edge of its face.
	vec3 a = abs(lpos);
	vec3 n = abs(lnorm);
	float e;
	if (n.x > 0.5) {
		e = half_size - max(a.y, a.z);
	} else if (n.y > 0.5) {
		e = half_size - max(a.x, a.z);
	} else {
		e = half_size - max(a.x, a.y);
	}
	// Slightly darker edges make the cube's shape easy to read.
	float shade = 1.0 - 0.28 * (1.0 - smoothstep(0.0, 0.07, e));
	// Anchors get a thick dark frame around every face.
	shade *= 1.0 - anchor * 0.55 * (1.0 - smoothstep(0.15, 0.17, e));
	ALBEDO = color.rgb * shade;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	// A bit of self-glow keeps colors bright on faces turned away from the light.
	EMISSION = color.rgb * 0.2 * shade;
	//ALPHA = color.a;
}
"""

const MARK_SHADER := """
shader_type spatial;
// cull_back: marks on the far faces must not show through see-through cubes.
render_mode unshaded, cull_back, fog_disabled, depth_draw_never;

uniform vec4 color : source_color = vec4(1.0);
uniform int shape = 1;  // 1 = checkmark, 2 = cross
uniform float half_width = 0.11;

varying vec2 local;

float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

void vertex() {
	local = VERTEX.xy;
}

void fragment() {
	float d;
	if (shape == 1) {
		d = min(seg(local, vec2(-0.62, 0.02), vec2(-0.18, -0.48)),
				seg(local, vec2(-0.18, -0.48), vec2(0.66, 0.6)));
	} else {
		d = min(seg(local, vec2(-0.58, -0.58), vec2(0.58, 0.58)),
				seg(local, vec2(-0.58, 0.58), vec2(0.58, -0.58)));
	}
	float aa = fwidth(d);
	ALBEDO = color.rgb;
	ALPHA = color.a * (1.0 - smoothstep(half_width - aa, half_width + aa, d));
}
"""
## Text face switching: how long the crossfade takes, and how much more a
## face must point at the camera than the current one to take over (so it
## doesn't flicker at 45°).
const FADE_TIME := 0.25
const FACE_HYSTERESIS := 0.1
const UPRIGHT_HYSTERESIS := 0.15
const FINISHED_ALPHA := 0.5  # done / failed cubes are see-through, text included
const DONE_COLOR := Color(0.02, 0.6, 0.18, 0.65)
const FAILED_COLOR := Color(0.9, 0.12, 0.12, 0.6)

static var _cube_shader: Shader
static var _cube_shader_clear: Shader
static var _mark_shader: Shader

var id: int = 0
var text: String = ""
var color: Color = Color("ffe680")
var status: String = ""  # "", "done" or "failed"
## An anchor carries every block linked to it (directly or through others) when moved.
var anchor := false

var _cube_mat: ShaderMaterial
var _outline: MeshInstance3D
var _labels: Array[Label3D] = []
var _marks: Array[MeshInstance3D] = []
var _mark_mat: ShaderMaterial
var _dim := 0.0
var _shown := -1  # face showing the text, or -1 before the first frame
var _face_vis: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]  # text opacity per face
var _face_up: Array[Vector3] = []  # text "up" per face, in the cube's space
var _ink := Color.BLACK
var _alpha := 1.0


func _ready() -> void:
	if _cube_shader == null:
		_cube_shader = Shader.new()
		_cube_shader.code = CUBE_SHADER
		_cube_shader_clear = Shader.new()
		_cube_shader_clear.code = CUBE_SHADER.replace("//ALPHA", "ALPHA")
		_mark_shader = Shader.new()
		_mark_shader.code = MARK_SHADER
	_cube_mat = ShaderMaterial.new()
	_cube_mat.shader = _cube_shader
	_cube_mat.set_shader_parameter("half_size", SIZE * 0.5)
	var box := BoxMesh.new()
	box.size = Vector3.ONE * SIZE
	var cube := MeshInstance3D.new()
	cube.mesh = box
	cube.material_override = _cube_mat
	add_child(cube)

	# Selection outline: a slightly bigger box showing only its inside faces.
	var outline_mat := StandardMaterial3D.new()
	outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	outline_mat.albedo_color = Color(1.0, 1.0, 1.0)
	var outline_box := BoxMesh.new()
	outline_box.size = Vector3.ONE * (SIZE + 0.12)
	_outline = MeshInstance3D.new()
	_outline.mesh = outline_box
	_outline.material_override = outline_mat
	_outline.visible = false
	add_child(_outline)

	_mark_mat = ShaderMaterial.new()
	_mark_mat.shader = _mark_shader
	_mark_mat.render_priority = 2  # over the text
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * SIZE
	for f in FACES:
		var normal: Vector3 = f[0]
		var face_basis := Basis.looking_at(-normal, f[1])  # +Z points out of the face
		var l := _make_label()
		l.transform = Transform3D(face_basis, normal * (SIZE * 0.5 + 0.004))
		l.visible = false
		_labels.append(l)
		_face_up.append(f[1])
		add_child(l)
		var m := MeshInstance3D.new()
		m.mesh = quad
		m.material_override = _mark_mat
		m.transform = Transform3D(face_basis, normal * (SIZE * 0.5 + 0.01))
		m.visible = false
		_marks.append(m)
		add_child(m)

	refresh()


func _make_label() -> Label3D:
	var l := Label3D.new()
	l.pixel_size = PIXEL_SIZE
	l.outline_size = 0
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.width = (SIZE - PAD * 2.0) / PIXEL_SIZE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.double_sided = false  # text on far faces must not show through
	l.render_priority = 1
	return l


## Call after changing `text`, `color`, `status` or `anchor`.
func refresh() -> void:
	if _labels.is_empty():
		return  # not in the tree yet; _ready() will call this
	var shown := text if text.strip_edges() != "" else "(empty note)"
	var font_size := _fit_font_size(shown)
	for l in _labels:
		l.text = shown
		l.font_size = font_size
	_apply_depth_fx()


## dim is 0..1. Set every frame by main from the note's depth behind the focus.
func set_depth_fx(dim: float) -> void:
	if absf(dim - _dim) < 0.005:
		return
	_dim = dim
	_apply_depth_fx()


func _apply_depth_fx() -> void:
	if _labels.is_empty():
		return
	var finished := status != ""
	var alpha := FINISHED_ALPHA if finished else 1.0
	var body := color.darkened(_dim)
	_cube_mat.set_shader_parameter("color", Color(body, alpha))
	_cube_mat.set_shader_parameter("anchor", 1.0 if anchor else 0.0)
	var shader := _cube_shader_clear if finished else _cube_shader
	if _cube_mat.shader != shader:
		_cube_mat.shader = shader
	var ink := Color(0.1, 0.1, 0.12) if color.get_luminance() > 0.5 else Color(0.96, 0.96, 0.96)
	_ink = ink.darkened(_dim * 0.5)
	_alpha = alpha
	for i in _labels.size():
		_labels[i].modulate = Color(_ink, _alpha * ease(_face_vis[i], -2.0))
	for m in _marks:
		m.visible = status != ""
	if status != "":
		var mark_col := DONE_COLOR if status == "done" else FAILED_COLOR
		mark_col = mark_col.darkened(_dim)
		_mark_mat.set_shader_parameter("color", mark_col)
		_mark_mat.set_shader_parameter("shape", 1 if status == "done" else 2)


## Picks the face turned most toward the camera for the text, fades faces in
## and out, and clicks the text on the shown face(s) round to read upright.
func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _labels.is_empty():
		return
	var inv := global_transform.affine_inverse()
	var cam_local := inv * cam.global_position
	var best := 0
	var scores: Array[float] = []
	for i in FACES.size():
		var n: Vector3 = FACES[i][0]
		scores.append(n.dot((cam_local - n * SIZE * 0.5).normalized()))
		if scores[i] > scores[best]:
			best = i
	var first := _shown < 0
	if first or (best != _shown and scores[best] > scores[_shown] + FACE_HYSTERESIS):
		_shown = best
	var cam_up := (inv.basis * cam.global_transform.basis.y).normalized()
	for i in FACES.size():
		var target := 1.0 if i == _shown else 0.0
		var was := _face_vis[i]
		_face_vis[i] = target if first else move_toward(was, target, delta / FADE_TIME)
		var l := _labels[i]
		l.visible = _face_vis[i] > 0.001
		if not l.visible:
			continue
		if _face_vis[i] != was:
			l.modulate = Color(_ink, _alpha * ease(_face_vis[i], -2.0))
		_turn_upright(i, cam_up, cam_local)


## Turns face `i`'s text upright, in quarter turns: of the face's four edge
## directions, the one closest to the wanted up becomes the text's up. On side
## faces (facing sideways in the world) that's the world's up, so their text
## stays upright however you move; on faces pointing up or down it's the
## camera's up, so the text faces you. A new direction has to be clearly closer
## (UPRIGHT_HYSTERESIS) before the text clicks round, so it doesn't flip back
## and forth halfway between two.
func _turn_upright(i: int, cam_up: Vector3, cam_local: Vector3) -> void:
	var n: Vector3 = FACES[i][0]
	var world_n := (global_transform.basis * n).normalized()
	var ref := cam_up if absf(world_n.y) > 0.7 else (global_transform.basis.inverse() * Vector3.UP).normalized()
	var want := ref - n * ref.dot(n)
	if want.length() < 0.2:
		# The wanted up is nearly along the normal: use the way the camera looks across the face.
		var across := n * SIZE * 0.5 - cam_local
		want = across - n * across.dot(n)
	if want.length() < 0.001:
		return
	want = want.normalized()
	var a: Vector3 = FACES[i][1]
	var b := n.cross(a)
	var up := _face_up[i]
	for c in [a, -a, b, -b]:
		if c.dot(want) > up.dot(want) + UPRIGHT_HYSTERESIS:
			up = c
	if up.is_equal_approx(_face_up[i]):
		return
	_face_up[i] = up
	_labels[i].basis = Basis(up.cross(n), up, n)


func set_selected(on: bool) -> void:
	if _outline:
		_outline.visible = on


## Distance along a world-space ray to where it enters the cube, or INF if it misses.
func ray_distance(from: Vector3, dir: Vector3) -> float:
	var inv := global_transform.affine_inverse()
	var o := inv * from
	var d := inv.basis * dir
	var h := SIZE * 0.5 + 0.02
	var t_near := -INF
	var t_far := INF
	for k in 3:
		if absf(d[k]) < 1e-8:
			if absf(o[k]) > h:
				return INF
			continue
		var t1 := (-h - o[k]) / d[k]
		var t2 := (h - o[k]) / d[k]
		t_near = maxf(t_near, minf(t1, t2))
		t_far = minf(t_far, maxf(t1, t2))
	if t_near > t_far or t_far < 0.0:
		return INF
	return maxf(t_near, 0.0)


func to_dict() -> Dictionary:
	var p := global_position
	var q := quaternion
	return {
		"id": id,
		"text": text,
		"color": color.to_html(false),
		"pos": [p.x, p.y, p.z],
		"rot": [q.x, q.y, q.z, q.w],
		"status": status,
		"anchor": anchor,
	}


## The largest font size at which the text, wrapped to the face width, fits the
## face, and no single word is wider than the face (so words never get split).
static func _fit_font_size(t: String) -> int:
	var font := ThemeDB.fallback_font
	var box := Vector2.ONE * (SIZE - PAD * 2.0) / PIXEL_SIZE
	var words := t.split(" ", false)
	var lo := MIN_FONT_SIZE
	var hi := MAX_FONT_SIZE
	while lo < hi:  # binary search for the largest size that fits
		var mid := (lo + hi + 1) / 2
		var fits := true
		for w in words:
			for part in w.split("\n", false):
				if font.get_string_size(part, HORIZONTAL_ALIGNMENT_LEFT, -1, mid).x > box.x:
					fits = false
					break
			if not fits:
				break
		if fits:
			var size := font.get_multiline_string_size(
				t, HORIZONTAL_ALIGNMENT_LEFT, box.x, mid, -1, BREAK_FLAGS)
			fits = size.y <= box.y
		if fits:
			lo = mid
		else:
			hi = mid - 1
	return lo
