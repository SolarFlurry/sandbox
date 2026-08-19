#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

out vec4 finalColor;

const vec2 offsets[9] = vec2[](
    vec2(0., 0.),
    vec2(1., 0.),
    vec2(0., 1.),
    vec2(-1., 0.),
    vec2(0., -1.),
    vec2(1., 1.),
    vec2(-1., -1.),
    vec2(-1, 1.),
    vec2(1., -1.)
);

uniform sampler2D texture0;

void main() {
    vec2 texSize = vec2(textureSize(texture0, 0));

    vec2 pixelCoord = fragTexCoord * texSize;

    int solidCount = 0;
    int emptyCount = 0;

    for (int i = 0; i < 9; i++) {
        vec2 p = clamp(pixelCoord + offsets[i], vec2(0.), texSize - vec2(1.));
        vec4 c = texture(texture0, p / texSize);

        solidCount += int(c.r == 1.);
    }

    finalColor = vec4(vec3(solidCount >= 7), 1.);
}
