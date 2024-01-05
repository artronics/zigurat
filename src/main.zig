const std = @import("std");
pub const widget = @import("widget.zig");
pub const DawnInterface = @import("gpu").dawn.Interface;


// pub const widget = ui.widget;
pub const Ui = widget.Ui;

test {
    std.testing.refAllDeclsRecursive(@This());
}
