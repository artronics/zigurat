const std = @import("std");
const Allocator = std.mem.Allocator;
const gpu = @import("gpu");
const glfw = @import("glfw");

const log = std.log.scoped(.zigurat);

/// GLFW error handling callback
///
/// This only logs errors, and doesn't e.g. exit the application, because many simple operations of
/// GLFW can result in an error on the stack when running under different Wayland Linux systems.
/// Doing anything else here would result in a good chance of applications not working on Wayland,
/// so the best thing to do really is to just log the error. See the mach-glfw README for more info.
pub fn errorCallback(error_code: glfw.ErrorCode, description: [:0]const u8) void {
    if (std.mem.eql(u8, description, "Raw mouse motion is not supported on this system")) return;
    log.err("glfw: {}: {s}\n", .{ error_code, description });
}

pub const Options = struct {
    is_app: bool = false,
    headless: bool = false,
    display_mode: DisplayMode = .windowed,
    border: bool = true,
    title: [:0]const u8 = "Zigurat",
    size: Size = .{ .width = 1920 / 2, .height = 1080 / 2 },
    power_preference: gpu.PowerPreference = .undefined,
    required_features: ?[]const gpu.FeatureName = null,
    required_limits: ?gpu.Limits = null,
};

pub const DisplayMode = enum {
    /// Windowed mode.
    windowed,

    /// Fullscreen mode, using this option may change the display's video mode.
    fullscreen,

    /// Borderless fullscreen window.
    ///
    /// Beware that true .fullscreen is also a hint to the OS that is used in various contexts, e.g.
    ///
    /// * macOS: Moving to a virtual space dedicated to fullscreen windows as the user expects
    /// * macOS: .borderless windows cannot prevent the system menu bar from being displayed
    ///
    /// Always allow users to choose their preferred display mode.
    borderless,
};

pub const Size = struct {
    width: u32,
    height: u32,

    pub inline fn eql(a: Size, b: Size) bool {
        return a.width == b.width and a.height == b.height;
    }
};
