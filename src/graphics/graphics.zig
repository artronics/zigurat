const std = @import("std");
const render = @import("render.zig");

pub const Renderer = render.Renderer;
pub const Primitive = @import("primitive.zig");

test {
    std.testing.refAllDeclsRecursive(@This());
}
