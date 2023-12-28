const std = @import("std");
const gpu = @import("gpu");
// const platform = @import("platform/platform.zig");
const platform = @import("platform");
const gfx = @import("graphics/graphics.zig");

pub const DawnInterface = gpu.dawn.Interface;

pub const WindowOptions = platform.WindowOptions;
pub const Renderer = gfx.Renderer;

test {
    std.testing.refAllDeclsRecursive(@This());
}
