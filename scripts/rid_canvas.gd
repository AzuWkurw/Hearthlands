class_name RidCanvas
extends RefCounted
## The drawing calls the map view uses (draw_rect, draw_texture_rect, ...), recorded into a canvas item
## of the RenderingServer instead of the map view itself. The map view draws its buildings, fields and
## trees through one of these when zoomed out, and keeps the recording until something changes: a
## frame then only moves and scales it with the camera (MapView, "the building layer").

var rid: RID


func _init(p_rid: RID) -> void:
	rid = p_rid


func clear() -> void:
	RenderingServer.canvas_item_clear(rid)


func draw_set_transform(pos: Vector2, rot := 0.0, scale := Vector2.ONE) -> void:
	RenderingServer.canvas_item_add_set_transform(rid, Transform2D(rot, scale, 0.0, pos))


func draw_texture_rect(tex: Texture2D, rect: Rect2, tile: bool, modulate := Color.WHITE, transpose := false) -> void:
	if tex != null:
		RenderingServer.canvas_item_add_texture_rect(rid, rect, tex.get_rid(), tile, modulate, transpose)


func draw_texture_rect_region(tex: Texture2D, rect: Rect2, src: Rect2, modulate := Color.WHITE, transpose := false, clip_uv := true) -> void:
	if tex != null:
		RenderingServer.canvas_item_add_texture_rect_region(rid, rect, tex.get_rid(), src, modulate, transpose, clip_uv)


func draw_rect(rect: Rect2, color: Color, filled := true, width := -1.0, antialiased := false) -> void:
	if filled:
		RenderingServer.canvas_item_add_rect(rid, rect, color)
	else:
		var r := rect
		draw_polyline(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]), color, width, antialiased)


func draw_circle(pos: Vector2, radius: float, color: Color, filled := true, width := -1.0, antialiased := false) -> void:
	if filled:
		RenderingServer.canvas_item_add_circle(rid, pos, radius, color)
	else:
		draw_arc(pos, radius, 0.0, TAU, 24, color, width, antialiased)


func draw_arc(center: Vector2, radius: float, start: float, end: float, points: int, color: Color, width := -1.0, antialiased := false) -> void:
	var pts := PackedVector2Array()
	for k in points + 1:
		var a := lerpf(start, end, float(k) / points)
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	draw_polyline(pts, color, width, antialiased)


func draw_line(a: Vector2, b: Vector2, color: Color, width := -1.0, antialiased := false) -> void:
	RenderingServer.canvas_item_add_line(rid, a, b, color, width, antialiased)


func draw_polyline(points: PackedVector2Array, color: Color, width := -1.0, antialiased := false) -> void:
	RenderingServer.canvas_item_add_polyline(rid, points, PackedColorArray([color]), width, antialiased)


func draw_colored_polygon(points: PackedVector2Array, color: Color, uvs := PackedVector2Array(), texture: Texture2D = null) -> void:
	RenderingServer.canvas_item_add_polygon(rid, points, PackedColorArray([color]), uvs, texture.get_rid() if texture != null else RID())


func draw_polygon(points: PackedVector2Array, colors: PackedColorArray, uvs := PackedVector2Array(), texture: Texture2D = null) -> void:
	RenderingServer.canvas_item_add_polygon(rid, points, colors, uvs, texture.get_rid() if texture != null else RID())


func draw_mesh(mesh: Mesh, texture: Texture2D, transform := Transform2D(), modulate := Color.WHITE) -> void:
	if mesh != null:
		RenderingServer.canvas_item_add_mesh(rid, mesh.get_rid(), transform, modulate, texture.get_rid() if texture != null else RID())
