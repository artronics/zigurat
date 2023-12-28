const std = @import("std");
const render = @import("render.zig");

pub const Renderer = render.Renderer;

test {
    std.testing.refAllDeclsRecursive(@This());
}
