const std = @import("std");
const renderer = @import("renderer.zig");

pub const Renderer = renderer.Renderer;
pub const Primitive = @import("primitive.zig");

const platform = @import("platform");
pub const DawnInterface = platform.DawnInterface;
pub const WindowOptions = platform.WindowOptions;

test {
    std.testing.refAllDeclsRecursive(@This());
}
