const std = @import("std");
const gfx = @import("graphics");

pub const DawnInterface = gfx.DawnInterface;

pub const Renderer = gfx.Renderer;

test {
    std.testing.refAllDeclsRecursive(@This());
}
