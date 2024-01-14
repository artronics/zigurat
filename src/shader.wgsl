struct VertexInput {
    @location(0) position: vec2<f32>,
    @location(1) uv: vec2<f32>,
    @location(2) color: vec4<f32>,
}

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    // @location(0) vert_pos: vec3<f32>,
    @location(0) color: vec4<f32>,
    @location(1) uv: vec2<f32>,
};

struct Uniforms {
    mvp: mat4x4<f32>,
    gamma: f32,
};

@group(0) @binding(0) var<uniform> uniforms: Uniforms;

@vertex
fn vs_main(model: VertexInput) -> VertexOutput {

    var out: VertexOutput;
    // out.clip_position = vec4<f32>(model.pos, 0.0, 1.0);
    // out.vert_pos = out.clip_position.xyz;

    out.clip_position = uniforms.mvp * vec4<f32>(model.position, 0.0, 1.0);
    out.color = model.color;
    out.uv = model.uv;

    return out;
}

@group(0) @binding(1) var s: sampler;
@group(1) @binding(0) var t: texture_2d<f32>;

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let color = in.color * textureSample(t, s, in.uv);
    let corrected_color = pow(color.rgb, vec3<f32>(uniforms.gamma));
    // return vec4<f32>(corrected_color, color.a);
    return vec4<f32>(1,0,0,1);
}


// struct VertexInput {
//     @location(0) position: vec2<f32>,
//     @location(1) uv: vec2<f32>,
//     @location(2) color: vec4<f32>,
// };

// struct VertexOutput {
//     @builtin(position) position: vec4<f32>,
//     @location(0) color: vec4<f32>,
//     @location(1) uv: vec2<f32>,
// };

// struct Uniforms {
//     mvp: mat4x4<f32>,
//     gamma: f32,
// };

// @group(0) @binding(0) var<uniform> uniforms: Uniforms;

// @vertex
// fn main(in: VertexInput) -> VertexOutput {
//     var out: VertexOutput;
//     out.position = uniforms.mvp * vec4<f32>(in.position, 0.0, 1.0);
//     out.color = in.color;
//     out.uv = in.uv;
//     return out;
// }
// struct VertexOutput {
//     @builtin(position) position: vec4<f32>,
//     @location(0) color: vec4<f32>,
//     @location(1) uv: vec2<f32>,
// };

// struct Uniforms {
//     mvp: mat4x4<f32>,
//     gamma: f32,
// };

// @group(0) @binding(0) var<uniform> uniforms: Uniforms;
// @group(0) @binding(1) var s: sampler;
// @group(1) @binding(0) var t: texture_2d<f32>;

// @fragment
// fn main(in: VertexOutput) -> @location(0) vec4<f32> {
//     let color = in.color * textureSample(t, s, in.uv);
//     let corrected_color = pow(color.rgb, vec3<f32>(uniforms.gamma));
//     return vec4<f32>(corrected_color, color.a);
// }
