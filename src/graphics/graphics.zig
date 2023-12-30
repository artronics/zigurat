const std = @import("std");
const render = @import("render.zig");

pub const Renderer = render.Renderer;
pub const Primitive = @import("primitive.zig");

const platform = @import("platform");
pub const DawnInterface = platform.DawnInterface;
pub const WindowOptions = platform.WindowOptions;

test {
    std.testing.refAllDeclsRecursive(@This());
}
