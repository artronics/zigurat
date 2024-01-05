pub const Size = extern struct {
    width: u32,
    height: u32,
    pub inline fn eql(a: Size, b: Size) bool {
        return a.width == b.width and a.height == b.height;
    }
};

pub const Point = extern struct {
    x: f32,
    y: f32,
};

pub const Color = extern struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,
};
