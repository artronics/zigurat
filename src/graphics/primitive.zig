const std = @import("std");
const render_data = @import("data.zig");
const RenderData = render_data.RenderData;

const Self = @This();
const data: RenderData = undefined;

pub fn init(_data: RenderData) void {
    data = _data;
}

pub fn rect(self: Self) void {
    self.data;
}
