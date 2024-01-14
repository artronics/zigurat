const std = @import("std");
const Renderer = @import("renderer.zig");
const draw = @import("draw.zig");
const platform = @import("platform.zig");
const data = @import("data.zig");
const Size = data.Size;
const Allocator = std.mem.Allocator;

// pub const CommandQueue = std.fifo.LinearFifo(draw.DrawCommand, .Dynamic);
pub const CommandQueue = std.ArrayList(draw.DrawCommand);

pub const Ui = struct {
    const Self = @This();

    allocator: Allocator,
    renderer: Renderer,
    cmd_queue: CommandQueue,

    pub fn init(allocator: Allocator, renderer: Renderer) !Self {
        const cmd_q = try CommandQueue.initCapacity(allocator, 1000);

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

    pub fn run(self: *Self) void {
        while (!self.renderer.window.window.shouldClose()) {
            self.renderer.render(self.cmd_queue.items);
            std.time.sleep(16 * std.time.ns_per_ms);
        }
    }
    pub fn button(self: *Self) void {
        const rect = draw.Primitive{
            .rect = .{ .x0 = 20, .y0 = 20, .x1 = 40, .y1 = 40 },
        };
        self.cmd_queue.append(draw.DrawCommand{ .primitive = rect }) catch unreachable;
    }
};
