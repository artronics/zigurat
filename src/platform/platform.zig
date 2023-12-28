const native = @import("native.zig");
const backend = @import("backend.zig");

pub const Backend = native.WgpuBackend;
pub const WindowOptions = backend.Options;

pub const MockPlatform = struct {
    pub const MockBackend = struct {};
};
