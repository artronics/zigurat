const std = @import("std");
const platform = @import("platform");
const gfx = @import("graphics/graphics.zig");

pub const DawnInterface = platform.DawnInterface;

pub const WindowOptions = platform.WindowOptions;
pub const Renderer = gfx.Renderer;

test {
    std.testing.refAllDeclsRecursive(@This());
}
