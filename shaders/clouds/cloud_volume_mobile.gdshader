shader_type spatial;
// Mobile variant: depth-tested back faces and an analytic ground plane instead of the depth texture copy.
render_mode unshaded, cull_front, depth_draw_never, blend_mix, shadows_disabled;

#define CLOUD_ANALYTIC_GROUND
#include "res://shaders/clouds/cloud_volume.gdshaderinc"
