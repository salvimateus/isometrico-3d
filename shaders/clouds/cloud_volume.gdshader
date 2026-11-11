shader_type spatial;
// Back faces of the proxy box carry the raymarch, so it keeps rendering with the camera inside.
render_mode unshaded, cull_front, depth_draw_never, depth_test_disabled, blend_mix, shadows_disabled;

#include "res://shaders/clouds/cloud_volume.gdshaderinc"
