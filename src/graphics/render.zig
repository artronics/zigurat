const std = @import("std");
const Allocator = std.mem.Allocator;
const platform = @import("platform");
const Backend = if (@import("builtin").is_test) platform.MockPlatform.MockBackend else platform.Backend;
const testing = std.testing;

pub const Renderer = struct {
    const Self = @This();

    allocator: Allocator,
    backend: *Backend,

    pub fn init(allocator: Allocator, win_options: platform.WindowOptions) !Self {
        const backend = try allocator.create(Backend);
        backend.* = try Backend.init(allocator, win_options);

        return .{
            .allocator = allocator,
            .backend = backend,
        };
    }
};

test {
    const a = testing.allocator;
    _ = Renderer.init(a, .{});
}
