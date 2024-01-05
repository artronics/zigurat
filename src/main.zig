const std = @import("std");
const ui = @import("ui");
pub const widget = @import("widget.zig");

pub const DawnInterface = ui.DawnInterface;

// pub const widget = ui.widget;
pub const Ui = ui.Ui;

test {
    std.testing.refAllDeclsRecursive(@This());
}
