@tool
extends EditorPlugin
## Land Lab: a main-screen tab in the Godot editor (top bar, next to 2D / 3D / Script) for tweaking the procedural land.
## The panel is land_lab_panel.gd; the world is built by a background headless Godot (tools/land_lab_render.gd).

const LabPanel := preload("res://addons/land_lab/land_lab_panel.gd")
var panel: Control


func _enter_tree() -> void:
	panel = LabPanel.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	EditorInterface.get_editor_main_screen().add_child(panel)
	panel.hide()


func _exit_tree() -> void:
	if panel:
		panel.stop_worker()
		panel.queue_free()


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if panel:
		panel.visible = visible


func _get_plugin_name() -> String:
	return "Land Lab"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("Terrain3D" if EditorInterface.get_editor_theme().has_icon("Terrain3D", "EditorIcons") else "WorldEnvironment", "EditorIcons")
