// Marks the rider's pixels in the stencil buffer while they ride through a portal, and draws
// nothing. The portal surface (portal.gdshader) does not draw over marked pixels, so the part
// of the rider already through the opening stays on screen, standing in the other world
// exactly where the window shows it, instead of vanishing behind the surface until the
// camera follows through. Laid over the rider's meshes as their material_overlay by the
// LevelController for the length of a crossing only.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled,
	shadows_disabled;
// Must match RIDER_STENCIL in portal.gdshader.
stencil_mode write, compare_always, 7;

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
