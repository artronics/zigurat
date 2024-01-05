const std = @import("std");
const draw = @import("draw.zig");
const platform = @import("platform.zig");
const Allocator = std.mem.Allocator;

pub const Ui = struct {
    const Self = @This();

    allocator: Allocator,
    renderer: draw.Renderer,
    cmd_queue: draw.CommandQueue,

    pub fn init(allocator: Allocator, win_options: platform.Options) !Self {
        const renderer = try draw.Renderer.init(allocator, win_options);
        const cmd_q = draw.CommandQueue.init(allocator);

        return .{
            .allocator = allocator,
            .renderer = renderer,
            .cmd_queue = cmd_q,
        };
    }
    pub fn deinit(self: Self) void {
        self.renderer.deinit();
        self.cmd_queue.deinit();
    }

    pub fn run(self: Self) void {
        self.renderer.run();
    }
    pub fn button(self: *Self) void {
        const rect = draw.Primitive{ .rect = .{
            .a = .{ .x = 0.5, .y = 0.5 },
            .b = .{ .x = 0.5, .y = -0.5 },
        } };
        self.cmd_queue.append(draw.DrawCommand{ .primitive = rect }) catch unreachable;
    }
};
