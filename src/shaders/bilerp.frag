#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

out vec4 finalColor;

uniform sampler2D texture0;

uniform float u_seed;
uniform vec2 u_worldSpace;

#define M_PI 3.14159265358979323846

vec2 hash22(vec2 p, float seed) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(443.8975, 397.2973, 491.1871));
    p3 += dot(p3, p3.yzx + (19.19 + seed));
    vec2 randVal = fract(vec2((p3.x + p3.y) * p3.z, (p3.x + p3.z) * p3.y));
    
    float angle = randVal.x * M_PI * 2.0;
    return vec2(cos(angle), sin(angle));
}

float seededPerlinNoise(vec2 p, float seed) {
    vec2 i = floor(p);
    vec2 f = fract(p);

    vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

    vec2 g00 = hash22(i + vec2(0.0, 0.0), seed);
    vec2 g10 = hash22(i + vec2(1.0, 0.0), seed);
    vec2 g01 = hash22(i + vec2(0.0, 1.0), seed);
    vec2 g11 = hash22(i + vec2(1.0, 1.0), seed);

    float n00 = dot(g00, f - vec2(0.0, 0.0));
    float n10 = dot(g10, f - vec2(1.0, 0.0));
    float n01 = dot(g01, f - vec2(0.0, 1.0));
    float n11 = dot(g11, f - vec2(1.0, 1.0));

    float x1 = mix(n00, n10, u.x);
    float x2 = mix(n01, n11, u.x);
    float noiseValue = mix(x1, x2, u.y);

    return noiseValue * 2.0 + 0.5;
}

void main() {
    vec2 texSize = vec2(textureSize(texture0, 0));

    vec2 pixelCoord = fragTexCoord * texSize;
    vec2 c = floor(pixelCoord - 0.5) + 0.5;
    vec2 f = fract(pixelCoord - 0.5);

    vec2 p00 = clamp(c, vec2(0.), texSize - 1.);
    vec2 p10 = clamp(c + vec2(1., 0.), vec2(0.), texSize - 1.);
    vec2 p01 = clamp(c + vec2(0., 1.), vec2(0.), texSize - 1.);
    vec2 p11 = clamp(c + vec2(1., 1.), vec2(0.), texSize - 1.);

    vec4 c00 = texture(texture0, p00 / texSize);
    vec4 c10 = texture(texture0, p10 / texSize);
    vec4 c01 = texture(texture0, p01 / texSize);
    vec4 c11 = texture(texture0, p11 / texSize);

    vec4 cx0 = mix(c00, c10, f.x);
    vec4 cx1 = mix(c01, c11, f.x);
    vec4 final = mix(cx0, cx1, f.y) + seededPerlinNoise((fragTexCoord + u_worldSpace) * 20., u_seed) * .3;

    finalColor = vec4(final.r > .5 ? vec3(1.) : vec3(0.), 1.);
}
