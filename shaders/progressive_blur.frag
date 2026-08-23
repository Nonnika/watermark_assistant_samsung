#version 460 core

#include <flutter/runtime_effect.glsl>

// 注意：第一个 uniform 必须是 vec2（ImageFilter.shader 的硬性要求），
// 表示被过滤区域的尺寸（像素）
uniform vec2 u_size;

// 底部最大模糊半径（像素），向上平滑衰减到 0，实现渐进式羽化边缘
uniform float u_max_radius;

uniform sampler2D u_texture_input;

out vec4 frag_color;

const int TAPS = 12;
const float GOLDEN_ANGLE = 2.39996323;

void main() {
  vec2 fc = FlutterFragCoord().xy;
  vec2 uv = fc / u_size;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif

  // p: 顶部 0 → 底部 1（翻转后 uv.y 底部为 0）
  float p = 1.0 - uv.y;

  // 模糊半径自顶部向底部平滑增长：顶部自然羽化为无模糊，无任何分层边缘
  float r = u_max_radius * smoothstep(0.0, 1.0, p);

  if (r < 0.5) {
    frag_color = texture(u_texture_input, uv);
    return;
  }

  // 黄金角螺旋盘状采样近似高斯模糊，单 pass 完成
  vec2 texel = 1.0 / u_size;
  vec4 acc = vec4(0.0);
  for (int i = 0; i < TAPS; i++) {
    float fi = float(i);
    float ang = fi * GOLDEN_ANGLE;
    float rad = sqrt((fi + 0.5) / float(TAPS)) * r;
    vec2 offset = vec2(cos(ang), sin(ang)) * rad * texel;
    acc += texture(u_texture_input, uv + offset);
  }
  frag_color = acc / float(TAPS);
}
