const std = @import("std");
pub const widget = @import("widget.zig");
const platform = @import("platform.zig");
const window = @import("window.zig");

pub const DawnInterface = @import("gpu").dawn.Interface;

pub const PlatformOptions = platform.Options;

pub const Ui = widget.Ui;
pub const Backend = platform.WgpuBackend;
pub const Window = window.Window;
pub const Renderer = @import("renderer.zig");

test {
    std.testing.refAllDeclsRecursive(@This());
}
