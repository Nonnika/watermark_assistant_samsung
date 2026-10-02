#version 460 core

#include <flutter/runtime_effect.glsl>

// 注意：第一个 uniform 必须是 vec2（ImageFilter.shader 的硬性要求），
// 表示被过滤区域的尺寸（像素）
uniform vec2 u_size;

// 底部最大模糊半径（像素），向上平滑衰减到 0，实现渐进式羽化边缘
uniform float u_max_radius;

uniform sampler2D u_texture_input;

out vec4 frag_color;

void main() {
  vec2 fc = FlutterFragCoord().xy;
  vec2 uv = fc / u_size;
  // 衰减按屏幕方向计算；GLES 只翻转纹理坐标，保持与 Vulkan 相同的渐变方向。
  float p = clamp(uv.y, 0.0, 1.0);
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif

  // 五次平滑曲线在两端的一、二阶导数均为 0，顶部更缓慢地进入模糊。
  float progress = p * p * p * (p * (p * 6.0 - 15.0) + 10.0);
  float r = u_max_radius * progress;
  vec4 original = texture(u_texture_input, uv);

  if (r < 0.5) {
    frag_color = original;
    return;
  }

  // 12 个预计算黄金角圆盘采样点，单 pass 完成。
  // 显式展开以兼容 SkSL，同时免除逐片元的 sin/cos/sqrt 和数组索引。
  vec2 scale = r / u_size;
  vec4 acc = texture(u_texture_input, uv + vec2(0.204124145, 0.000000000) * scale);
  acc += texture(u_texture_input, uv + vec2(-0.260699267, 0.238821884) * scale);
  acc += texture(u_texture_input, uv + vec2(0.039904202, -0.454687792) * scale);
  acc += texture(u_texture_input, uv + vec2(0.328594540, 0.428593391) * scale);
  acc += texture(u_texture_input, uv + vec2(-0.603011395, -0.106664226) * scale);
  acc += texture(u_texture_input, uv + vec2(0.571225035, -0.363366609) * scale);
  acc += texture(u_texture_input, uv + vec2(-0.191063596, 0.710747050) * scale);
  acc += texture(u_texture_input, uv + vec2(-0.364378996, -0.701589586) * scale);
  acc += texture(u_texture_input, uv + vec2(0.790556672, 0.288710031) * scale);
  acc += texture(u_texture_input, uv + vec2(-0.822442487, 0.339492301) * scale);
  acc += texture(u_texture_input, uv + vec2(0.396471627, -0.847236832) * scale);
  acc += texture(u_texture_input, uv + vec2(0.292982443, 0.934074206) * scale);
  // 小半径从原图连续混入采样结果，避免在 0.5 像素阈值处突然切换。
  frag_color = mix(original, acc / 12.0, smoothstep(0.5, 2.0, r));
}
