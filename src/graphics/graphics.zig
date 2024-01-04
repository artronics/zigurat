const std = @import("std");
const renderer = @import("renderer.zig");

pub const Renderer = renderer.Renderer;
const pm = @import("primitive.zig");
pub const DrawCommand = pm.DrawCommand;
pub const CommandQueue = std.ArrayList(DrawCommand);
pub const Primitive = pm.Primitive;
pub usingnamespace pm.primitives;

const platform = @import("platform");
pub const DawnInterface = platform.DawnInterface;
pub const WindowOptions = platform.WindowOptions;

test {
    std.testing.refAllDeclsRecursive(@This());
}
