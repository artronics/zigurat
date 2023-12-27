struct VertexInput {
    @location(0) position: vec3<f32>,
    @location(1) color: vec3<f32>,
}
struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    // @location(0) vert_pos: vec3<f32>,
    @location(0) color: vec3<f32>,
};

@vertex
fn vs_main(model: VertexInput) -> VertexOutput {
    // let pos = array<vec2<f32>, 3>(
    //     // CCW
    //     vec2<f32>( 0.0,  0.5),
    //     vec2<f32>(-0.5, -0.5),
    //     vec2<f32>( 0.5, -0.5)
    //     // CW
    //     // vec2<f32>( 0.0,  0.5),
    //     // vec2<f32>( 0.5, -0.5),
    //     // vec2<f32>(-0.5, -0.5),
    // );

    var out: VertexOutput;
    out.clip_position = vec4<f32>(model.position, 1.0);
    // out.vert_pos = out.clip_position.xyz;
    out.color = model.color;

    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    return vec4<f32>(in.color, 1.0);
}


