// Liquid metal: a Flutter port of Paper Shaders' liquid-metal (image mode).
// https://github.com/paper-design/shaders (Apache-2.0)
#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;            // widget size
uniform vec2 uImageBox;        // fitted image box * scale
uniform vec2 uTexel;           // edge blur texel, as if the long side were 4096 px
uniform vec2 uPixel;           // one device pixel in image UV
uniform float uMinResolution;  // min(width, height) in render pixels
uniform float uTime;
uniform vec4 uColorBack;
uniform vec4 uColorTint;
uniform float uSoftness;
uniform float uRepetition;
uniform float uShiftRed;
uniform float uShiftBlue;
uniform float uDistortion;
uniform float uContour;
uniform float uAngle;
uniform sampler2D uImage;      // R = edge field, G = alpha

out vec4 fragColor;

#define PI 3.14159265358979323846

vec2 rotate(vec2 uv, float th) {
  return mat2(cos(th), sin(th), -sin(th), cos(th)) * uv;
}

vec3 permute(vec3 x) { return mod(((x * 34.0) + 1.0) * x, 289.0); }

float snoise(vec2 v) {
  const vec4 C = vec4(0.211324865405187, 0.366025403784439,
    -0.577350269189626, 0.024390243902439);
  vec2 i = floor(v + dot(v, C.yy));
  vec2 x0 = v - i + dot(i, C.xx);
  vec2 i1;
  i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
  vec4 x12 = x0.xyxy + C.xxzz;
  x12.xy -= i1;
  i = mod(i, 289.0);
  vec3 p = permute(permute(i.y + vec3(0.0, i1.y, 1.0))
    + i.x + vec3(0.0, i1.x, 1.0));
  vec3 m = max(0.5 - vec3(dot(x0, x0), dot(x12.xy, x12.xy),
      dot(x12.zw, x12.zw)), 0.0);
  m = m * m;
  m = m * m;
  vec3 x = 2.0 * fract(p * C.www) - 1.0;
  vec3 h = abs(x) - 0.5;
  vec3 ox = floor(x + 0.5);
  vec3 a0 = x - ox;
  m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
  vec3 g;
  g.x = a0.x * x0.x + h.x * x0.y;
  g.yz = a0.yz * x12.xz + h.yz * x12.yw;
  return 130.0 * dot(m, g);
}

float getColorChanges(float c1, float c2, float stripe_p, vec3 w, float blur, float bump, float tint) {
  float ch = mix(c2, c1, smoothstep(.0, 2. * blur, stripe_p));

  float border = w[0];
  ch = mix(ch, c2, smoothstep(border, border + 2. * blur, stripe_p));

  bump = smoothstep(.2, .8, bump);
  border = w[0] + .4 * (1. - bump) * w[1];
  ch = mix(ch, c1, smoothstep(border, border + 2. * blur, stripe_p));

  border = w[0] + .5 * (1. - bump) * w[1];
  ch = mix(ch, c2, smoothstep(border, border + 2. * blur, stripe_p));

  border = w[0] + w[1];
  ch = mix(ch, c1, smoothstep(border, border + 2. * blur, stripe_p));

  float gradient_t = (stripe_p - w[0] - w[1]) / w[2];
  float gradient = mix(c1, c2, smoothstep(0., 1., gradient_t));
  ch = mix(ch, gradient, smoothstep(border, border + .5 * blur, stripe_p));

  // Tint color is applied with color burn blending
  ch = mix(ch, 1. - min(1., (1. - ch) / max(tint, 0.0001)), uColorTint.a);
  return ch;
}

vec4 tex(vec2 uv) {
  return texture(uImage, clamp(uv, vec2(0.), vec2(1.)));
}

// Stripe phases for r, g, b before the time offset. Split out of main so it
// can be evaluated one pixel over in x and y: Flutter's web and Skia backends
// have no fwidth(), so the anti-aliasing width is a finite difference instead.
vec3 phases(vec2 uv, float edge, float t,
            out float edgeOut, out float bumpOut, out float bump0Out, out float diagOut, out float diag2Out) {
  float cycleWidth = uRepetition;
  uv.y = max(uv.y, 0.);

  vec2 rotatedUV = uv - vec2(.5);
  float angle = (-uAngle + 70.) * PI / 180.;
  float cosA = cos(angle);
  float sinA = sin(angle);
  rotatedUV = vec2(
    rotatedUV.x * cosA - rotatedUV.y * sinA,
    rotatedUV.x * sinA + rotatedUV.y * cosA
  ) + vec2(.5);

  float diagBLtoTR = rotatedUV.x - rotatedUV.y;
  float diagTLtoBR = rotatedUV.x + rotatedUV.y;

  vec2 grad_uv = uv - .5;
  float dist = length(grad_uv + vec2(0., .2 * diagBLtoTR));
  grad_uv = rotate(grad_uv, (.25 - .2 * diagBLtoTR) * PI);
  float direction = grad_uv.x;

  float bump = pow(1.8 * dist, 1.2);
  bump = 1. - bump;
  bump *= pow(uv.y, .3);
  bump0Out = bump;

  float noise = snoise(uv - t);

  edge += (1. - edge) * uDistortion * noise;

  direction += diagBLtoTR;
  direction -= 2. * noise * diagBLtoTR * (smoothstep(0., 1., edge) * (1.0 - smoothstep(0., 1., edge)));
  // u_contour range 2
  direction *= mix(1., 1. - edge, smoothstep(.5, 1., uContour));
  direction -= 1.7 * edge * smoothstep(.5, 1., uContour);
  direction += .2 * pow(uContour, 4.) * (1.0 - smoothstep(0., 1., edge));

  bump *= clamp(pow(uv.y, .1), .3, 1.);
  direction *= (.1 + (1.1 - edge) * bump);

  direction *= (.4 + .6 * (1.0 - smoothstep(.5, 1., edge)));
  direction += .18 * (smoothstep(.1, .2, uv.y) * (1.0 - smoothstep(.2, .4, uv.y)));
  direction += .03 * (smoothstep(.1, .2, 1. - uv.y) * (1.0 - smoothstep(.2, .4, 1. - uv.y)));

  direction *= (.5 + .5 * pow(uv.y, 2.));
  direction *= cycleWidth;

  float colorDispersion = clamp(1. - bump, 0., 1.);
  float dispersionRed = colorDispersion;
  dispersionRed += .03 * bump * noise;
  dispersionRed += 5. * (smoothstep(-.1, .2, uv.y) * (1.0 - smoothstep(.1, .5, uv.y))) * (smoothstep(.4, .6, bump) * (1.0 - smoothstep(.4, 1., bump)));
  dispersionRed -= diagBLtoTR;

  float dispersionBlue = colorDispersion;
  dispersionBlue *= 1.3;
  dispersionBlue += (smoothstep(0., .4, uv.y) * (1.0 - smoothstep(.1, .8, uv.y))) * (smoothstep(.4, .6, bump) * (1.0 - smoothstep(.4, .8, bump)));
  dispersionBlue -= .2 * edge;

  dispersionRed *= (uShiftRed / 20.);
  dispersionBlue *= (uShiftBlue / 20.);

  edgeOut = edge;
  bumpOut = bump;
  diagOut = diagBLtoTR;
  diag2Out = diagTLtoBR;
  return vec3(direction + dispersionRed, direction, direction - dispersionBlue);
}

void main() {
  vec2 fragCoord = FlutterFragCoord().xy;
  vec2 uv = (fragCoord - .5 * uSize) / uImageBox + .5;
  vec4 img = tex(uv);

  float opacity = img.g * step(0., uv.x) * step(0., uv.y) * step(uv.x, 1.) * step(uv.y, 1.);
  vec3 bgColor = uColorBack.rgb * uColorBack.a;
  float banding = 1. / 256. * (fract(sin(dot(.014 * fragCoord, vec2(12.9898, 78.233))) * 43758.5453123) - .5);
  if (opacity == 0.) {
    fragColor = vec4(bgColor + banding, uColorBack.a);
    return;
  }

  float t = .3 * (uTime + 2.8);

  // Edge: 3x3 blur of R, plus its gradient (Sobel) for the anti-aliasing pass.
  vec2 r = 6. * uTexel;
  float tl = tex(uv + vec2(-r.x, -r.y)).r;
  float tc = tex(uv + vec2(0., -r.y)).r;
  float tr = tex(uv + vec2(r.x, -r.y)).r;
  float ml = tex(uv + vec2(-r.x, 0.)).r;
  float mr = tex(uv + vec2(r.x, 0.)).r;
  float bl = tex(uv + vec2(-r.x, r.y)).r;
  float bc = tex(uv + vec2(0., r.y)).r;
  float br = tex(uv + vec2(r.x, r.y)).r;
  float blurred = (4. * img.r + 2. * (tc + ml + mr + bc) + tl + tr + bl + br) / 16.;
  vec2 blurredGrad = vec2((tr + 2. * mr + br) - (tl + 2. * ml + bl),
                          (bl + 2. * bc + br) - (tl + 2. * tc + tr)) / (8. * r);
  float contourK = smoothstep(0.0, 0.4, uContour);
  float edge0 = pow(blurred, 1.6) * contourK;
  vec2 edgeGrad = 1.6 * pow(blurred, .6) * contourK * blurredGrad;

  float edge, bump, bump0, diagBLtoTR, diagTLtoBR;
  float e, b, b0, d, d2;
  vec3 phase = phases(uv, edge0, t, edge, bump, bump0, diagBLtoTR, diagTLtoBR);
  vec3 fw = abs(phases(uv + vec2(uPixel.x, 0.), edge0 + edgeGrad.x * uPixel.x, t, e, b, b0, d, d2) - phase)
          + abs(phases(uv + vec2(0., uPixel.y), edge0 + edgeGrad.y * uPixel.y, t, e, b, b0, d, d2) - phase);

  float cycleWidth = uRepetition;
  float thin_strip_1_ratio = .12 / cycleWidth * (1. - .4 * bump0);
  float thin_strip_2_ratio = .07 / cycleWidth * (1. + .4 * bump0);
  float wide_strip_ratio = (1. - thin_strip_1_ratio - thin_strip_2_ratio);
  vec3 w = vec3(cycleWidth * thin_strip_1_ratio, cycleWidth * thin_strip_2_ratio, wide_strip_ratio);
  w[1] -= .02 * smoothstep(.0, 1., edge + bump);

  float softness = 0.05 * uSoftness;
  float blur = softness + .5 * smoothstep(1., 10., uRepetition) * smoothstep(.0, 1., edge);
  float smallCanvasT = 1.0 - smoothstep(100., 500., uMinResolution);
  blur += smallCanvasT * smoothstep(.0, 1., edge);
  float rExtraBlur = softness * (0.05 + .1 * (uShiftRed / 20.) * bump);
  float gExtraBlur = softness * 0.05 / max(0.001, abs(1. - diagBLtoTR));

  vec3 color1 = vec3(.98, 0.98, 1.);
  vec3 color2 = vec3(.1, .1, .1 + .1 * smoothstep(.7, 1.3, diagTLtoBR));

  vec3 stripe = fract(phase - t);
  float red = getColorChanges(color1.r, color2.r, stripe.r, w, blur + fw.r + rExtraBlur, bump, uColorTint.r);
  float green = getColorChanges(color1.g, color2.g, stripe.g, w, blur + fw.g + gExtraBlur, bump, uColorTint.g);
  float blue = getColorChanges(color1.b, color2.b, stripe.b, w, blur + fw.b, bump, uColorTint.b);

  vec3 color = vec3(red, green, blue) * opacity;
  color = color + bgColor * (1. - opacity);
  opacity = opacity + uColorBack.a * (1. - opacity);

  fragColor = vec4(color + banding, opacity);
}
