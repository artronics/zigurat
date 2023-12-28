const std = @import("std");
const native = @import("native.zig");
const backend = @import("backend.zig");

// Exports
pub const gpu = @import("gpu");

pub const DawnInterface = gpu.dawn.Interface;
pub const Backend = native.WgpuBackend;
pub const WindowOptions = backend.Options;
