const std = @import("std");
const Allocator = std.mem.Allocator;
const gfx = @import("graphics");

pub const DawnInterface = gfx.DawnInterface;
pub const WindowOptions = gfx.WindowOptions;

pub const Ui = struct {
    const Self = @This();

    allocator: Allocator,
    renderer: gfx.Renderer,
    cmd_queue: gfx.CommandQueue,

    pub fn init(allocator: Allocator, win_options: gfx.WindowOptions) !Self {
        const renderer = try gfx.Renderer.init(allocator, win_options);
        const cmd_q = gfx.CommandQueue.init(allocator);

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
        const rect = gfx.Primitive{ .rect = .{
            .a = .{ .x = 0.5, .y = 0.5 },
            .b = .{ .x = 0.5, .y = -0.5 },
        } };
        self.cmd_queue.append(gfx.DrawCommand{ .primitive = rect }) catch unreachable;
    }
};
