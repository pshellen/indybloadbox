precision mediump float;

// Full-screen poster backdrop: soft blur + darken + vignette.
// The blur is cheap: it samples low mipmap levels (bias) of a texture that
// was loaded with mipmap = true, then averages five spread-out taps.

varying vec2 TexCoord;

uniform sampler2D Tex0;
uniform float dim;      // overall brightness, e.g. 0.42
uniform vec2 spread;    // tap offset in texture coordinates

void main() {
    vec2 uv = TexCoord;
    const float bias = 4.5;

    vec3 c = texture2D(Tex0, uv, bias).rgb * 0.36;
    c += texture2D(Tex0, uv + vec2( spread.x,  spread.y), bias).rgb * 0.16;
    c += texture2D(Tex0, uv + vec2(-spread.x,  spread.y), bias).rgb * 0.16;
    c += texture2D(Tex0, uv + vec2( spread.x, -spread.y), bias).rgb * 0.16;
    c += texture2D(Tex0, uv + vec2(-spread.x, -spread.y), bias).rgb * 0.16;

    vec2 d = uv - 0.5;
    float vignette = clamp(1.0 - dot(d, d) * 1.6, 0.0, 1.0);

    gl_FragColor = vec4(c * dim * vignette, 1.0);
}
