const std = @import("std");
const Renderer = @import("renderer.zig");
const Draw = @import("draw.zig");
const platform = @import("platform.zig");
const data = @import("data.zig");
const Size = data.Size;
const Allocator = std.mem.Allocator;

// pub const CommandQueue = std.fifo.LinearFifo(draw.DrawCommand, .Dynamic);
pub const CommandQueue = std.ArrayList(Draw.DrawCommand);

pub const Ui = struct {
    const Self = @This();

    allocator: Allocator,
    renderer: Renderer,
    cmd_queue: CommandQueue,
    draw: Draw,

    pub fn init(allocator: Allocator, renderer: Renderer) !Self {
        const cmd_q = try CommandQueue.initCapacity(allocator, 1000);

        return .{
            .allocator = allocator,
            .renderer = renderer,
            .draw = Draw.init(allocator, 5000),
            .cmd_queue = cmd_q,
        };
    }
    pub fn deinit(self: Self) void {
        self.renderer.deinit();
        self.cmd_queue.deinit();
        self.draw.deinit();
    }

    pub fn run(self: *Self) void {
        while (!self.renderer.window.window.shouldClose()) {
            self.renderer.render(&self.draw);
            std.time.sleep(16 * std.time.ns_per_ms);
        }
    }
    pub fn button(self: *Self) void {
        const rec = Draw.Rect.fromWH(100, 100, 200, 200);
        const tex = Draw.Rect{ .x0 = 0, .y0 = 0, .x1 = 1, .y1 = 1 };
        self.draw.rectUv(rec, tex) catch unreachable;
    }
};
