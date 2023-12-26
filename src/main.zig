const std = @import("std");
const gpu = @import("gpu");
const platform = @import("platform/native.zig");

pub const Platform = platform.Platform;

pub const DawnInterface = gpu.dawn.Interface;
