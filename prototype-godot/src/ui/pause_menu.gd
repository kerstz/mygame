class_name PauseMenu
extends CanvasLayer
## Minimal pause menu (Esc). Gameplay itself shows no UI at all.

signal resume_requested
signal teleport_requested(biome: int)
signal quit_requested

var _root: Control
var _widgets := {}  # setting key -> control
var _refreshing := false


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false
	GameSettings.changed.connect(func(_k): _refresh())


func open() -> void:
	_refresh()
	visible = true


func close() -> void:
	visible = false


func _theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 17
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.05, 0.06, 0.06, 0.82)
	panel.set_corner_radius_all(6)
	panel.set_content_margin_all(22)
	t.set_stylebox("panel", "PanelContainer", panel)
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(1, 1, 1, 0.06)
	btn.set_corner_radius_all(4)
	btn.set_content_margin_all(8)
	var btn_h := btn.duplicate()
	btn_h.bg_color = Color(1, 1, 1, 0.14)
	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, btn)
		t.set_stylebox("hover", type, btn_h)
		t.set_stylebox("pressed", type, btn_h)
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
	t.set_color("font_color", "Label", Color(0.86, 0.88, 0.86))
	t.set_color("font_color", "Button", Color(0.9, 0.92, 0.9))
	return t


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = _theme()
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "STILLWORLD"
	title.add_theme_font_size_override("font_size", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(0, 470)
	vb.add_child(tabs)

	# --- Explore.
	var explore := _page(tabs, "Explore")
	_button(explore, "Resume", func(): resume_requested.emit())
	_label(explore, "Walk to…")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	explore.add_child(row)
	for i in WorldNoise.BIOME_NAMES.size():
		var b := Button.new()
		b.text = ["Rainy meadow", "Overgrown forest", "Desert dunes"][i]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): teleport_requested.emit(i))
		row.add_child(b)
	_option(explore, "Time of day", "time_of_day", ["auto", "morning", "day", "evening"],
		["Follow the land", "Morning", "Midday", "Evening"])
	_slider(explore, "Weather intensity", "weather_intensity", 0.0, 1.5, 0.05)
	_label(explore, "F3: performance overlay (developer)")
	_button(explore, "Quit", func(): quit_requested.emit())

	# --- Graphics.
	var gfx := _page(tabs, "Graphics")
	var presets := HBoxContainer.new()
	gfx.add_child(presets)
	for p in ["performance", "high", "ultra"]:
		var b := Button.new()
		b.text = p.capitalize()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): GameSettings.apply_preset(p))
		presets.add_child(b)
	_slider(gfx, "Render scale", "render_scale", 0.5, 1.0, 0.01)
	_option(gfx, "Upscaler", "upscaler", [0, 1, 2], ["Bilinear", "FSR 1", "FSR 2"])
	_slider(gfx, "View distance (chunks)", "view_chunks", 2, 6, 1)
	_slider(gfx, "Horizon distance", "far_chunks", 2, 6, 1)
	_slider(gfx, "Grass density", "grass_density", 0.1, 1.0, 0.05)
	_slider(gfx, "Grass distance (m)", "grass_distance", 30, 160, 5)
	_slider(gfx, "Shadow distance (m)", "shadow_distance", 40, 400, 10)
	_option(gfx, "Shadow quality", "shadow_quality", [0, 1, 2, 3], ["Low", "Medium", "High", "Ultra"])
	_option(gfx, "Cloud quality", "cloud_quality", [0, 1, 2], ["Low", "Medium", "High"])
	_slider(gfx, "Rain particles", "rain_density", 0.1, 1.0, 0.05)
	_check(gfx, "Volumetric fog", "volumetric_fog")
	_check(gfx, "Ambient occlusion (SSAO)", "ssao")
	_check(gfx, "Screen-space reflections", "ssr")
	_check(gfx, "Global illumination (SDFGI, expensive)", "sdfgi")
	_check(gfx, "Grass shadows (expensive)", "grass_shadows")
	_check(gfx, "Fullscreen", "fullscreen")
	_check(gfx, "V-Sync", "vsync")
	_option(gfx, "Frame limit", "max_fps", [0, 60, 100, 120, 144, 165], ["Off", "60", "100", "120", "144", "165"])

	# --- Controls.
	var ctl := _page(tabs, "Controls")
	_slider(ctl, "Field of view", "fov", 60, 110, 1)
	_slider(ctl, "Mouse sensitivity", "mouse_sensitivity", 0.03, 0.4, 0.01)
	_check(ctl, "Invert vertical look", "invert_y")
	_slider(ctl, "Head motion", "head_motion", 0.0, 1.0, 0.05)
	_slider(ctl, "Walking pace (m/s)", "walk_speed", 1.0, 2.2, 0.05)
	_label(ctl, "Move: WASD / ZQSD / arrows   ·   Look: mouse   ·   Menu: Esc")

	# --- Audio.
	var aud := _page(tabs, "Audio")
	_slider(aud, "Master volume", "master_volume", 0.0, 1.0, 0.05)
	_slider(aud, "Rain & wind", "ambience_volume", 0.0, 1.0, 0.05)
	_label(aud, "There is no music, by design.")


func _page(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 8)
	scroll.add_child(vb)
	return vb


func _label(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.modulate = Color(1, 1, 1, 0.7)
	parent.add_child(l)


func _button(parent: Control, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)


func _row(parent: Control, text: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = 260
	h.add_child(l)
	parent.add_child(h)
	return h


func _slider(parent: Control, text: String, key: String, lo: float, hi: float, step: float) -> void:
	var h := _row(parent, text)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var val := Label.new()
	val.custom_minimum_size.x = 56
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(s)
	h.add_child(val)
	var is_int := typeof(GameSettings.get_value(key)) == TYPE_INT
	s.value_changed.connect(func(v: float):
		val.text = str(int(v)) if is_int else "%.2f" % v
		if not _refreshing:
			GameSettings.set_value(key, int(v) if is_int else v))
	_widgets[key] = [s, val]


func _check(parent: Control, text: String, key: String) -> void:
	var c := CheckButton.new()
	c.text = text
	c.toggled.connect(func(on: bool):
		if not _refreshing:
			GameSettings.set_value(key, on))
	parent.add_child(c)
	_widgets[key] = [c]


func _option(parent: Control, text: String, key: String, values: Array, labels: Array) -> void:
	var h := _row(parent, text)
	var o := OptionButton.new()
	for l in labels:
		o.add_item(l)
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.item_selected.connect(func(i: int):
		if not _refreshing:
			GameSettings.set_value(key, values[i]))
	h.add_child(o)
	_widgets[key] = [o, values]


func _refresh() -> void:
	_refreshing = true
	for key in _widgets:
		var w: Array = _widgets[key]
		var v = GameSettings.get_value(key)
		if w[0] is HSlider:
			w[0].value = v
			w[1].text = str(int(v)) if typeof(v) == TYPE_INT else "%.2f" % v
		elif w[0] is CheckButton:
			w[0].button_pressed = v
		elif w[0] is OptionButton:
			var idx: int = w[1].find(v)
			if idx >= 0:
				w[0].select(idx)
	_refreshing = false
