shader_type spatial;
// One panel of a folding paper sheet (ui/paper_sheet.gd: the trail map, paper menus). The print (print_tex,
// white = bare paper) is multiplied onto a real paper scan (ambientCG Paper003, CC0) laid over the whole
// sheet, so every panel shows its own part of the same crumpled sheet. The back is bare paper; the outer
// panel's back carries the cover.
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D print_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D paper_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D paper_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D paper_rough : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec2 sheet_cells = vec2(4.0, 2.0);    // panels across / down
uniform float panel_aspect = 0.8;             // panel width / height
uniform vec4 cover_rect;                      // where the cover is in print_tex (xy offset, zw size)
uniform float page_v = 0.6667;                // the front print's share of print_tex's height
uniform float has_cover = 1.0;
uniform vec3 tint = vec3(1.02, 0.985, 0.92);  // a warm, slightly aged white
uniform float crumple = 0.7;                  // normal map strength
uniform sampler2D content_tex : source_color, filter_linear_mipmap_anisotropic;   // a print under the page (the map's world)
uniform vec4 content_rect = vec4(0.0, 0.0, 1.0, 1.0);   // the part of it on the sheet (uv offset, uv size)
uniform float use_content = 0.0;

instance uniform vec2 cell;                   // this panel's column / row
instance uniform float cover;                 // what's printed on this panel's back: 0 bare paper, 1 the cover, 2 the
											  // next slot of the cover strip (the leaflet's back panel)
instance uniform float pillow;                // a little sag between the creases (m)

varying vec2 sheet_uv;

void vertex() {
	// paper between two creases never lies flat: a soft bulge, zero at the folds
	VERTEX.z += pillow * sin(UV.x * PI) * sin(UV.y * PI);
	sheet_uv = (cell + UV) / sheet_cells;
}

void fragment() {
	float sheet_aspect = sheet_cells.x * panel_aspect / sheet_cells.y;
	vec2 puv = sheet_uv * vec2(sheet_aspect, 1.0) * 1.15;   // the scan with square texels
	vec3 paper = texture(paper_tex, puv).rgb;
	paper = mix(paper, vec3(dot(paper, vec3(0.333))), 0.6) * tint;
	vec3 col;
	if (FRONT_FACING) {
		vec4 pg = texture(print_tex, vec2(sheet_uv.x, sheet_uv.y * page_v));
		vec3 ink = pg.rgb;
		if (use_content > 0.5) {
			vec2 cu = content_rect.xy + sheet_uv * content_rect.zw;
			bool inside = cu.x > 0.0 && cu.y > 0.0 && cu.x < 1.0 && cu.y < 1.0;
			vec3 under = inside ? texture(content_tex, cu).rgb : vec3(1.0);
			ink = mix(under, pg.rgb, pg.a);
		}
		col = paper * ink;
	} else if (cover > 0.5 && has_cover > 0.5) {
		vec2 cu = vec2(1.0 - UV.x, UV.y);   // seen from behind: mirror it back
		vec2 slot = vec2((cover > 1.5 ? 1.0 : 0.0) * cover_rect.z, 0.0);
		col = paper * texture(print_tex, cover_rect.xy + slot + cu * cover_rect.zw).rgb;
	} else {
		col = paper * vec3(0.96, 0.95, 0.92);
	}
	// the creases: worn, a little darker, and the ink rubbed off right on the fold
	float e = min(min(UV.x, 1.0 - UV.x) * panel_aspect, min(UV.y, 1.0 - UV.y));
	float crease = smoothstep(0.0, 0.007, e);
	col = mix(mix(paper * 0.9, col, 0.7), col, crease);   // a hairline of worn ink on the fold
	col *= mix(0.93, 1.0, smoothstep(0.0, 0.05, e));      // and the paper a touch grubbier near it
	ALBEDO = col;
	ROUGHNESS = clamp(texture(paper_rough, puv).r * 0.25 + 0.72, 0.0, 1.0);
	SPECULAR = 0.3;
	NORMAL_MAP = texture(paper_nrm, puv).rgb;
	NORMAL_MAP_DEPTH = crumple;
}
