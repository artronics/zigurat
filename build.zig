const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "zigurat",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // GPU
    const gpu_dep = b.dependency("mach_gpu", .{
        .target = target,
        .optimize = optimize,
    });
    @import("mach_gpu").link(b.dependency("mach_gpu", .{
        .target = target,
        .optimize = optimize,
    }).builder, lib, .{}) catch unreachable;
    lib.addModule("gpu", gpu_dep.module("mach-gpu"));

    // GLFW
    const glfw_dep = b.dependency("mach_glfw", .{
        .target = target,
        .optimize = optimize,
    });
    @import("mach_glfw").link(b.dependency("mach_glfw", .{
        .target = target,
        .optimize = optimize,
    }).builder, lib);
    lib.addModule("glfw", glfw_dep.module("mach-glfw"));

    // FREETYPE
    const freetype_dep = b.dependency("mach_freetype", .{
        .target = target,
        .optimize = optimize,
    });
    @import("mach_freetype").linkFreetype(b.dependency("mach_freetype", .{
        .target = target,
        .optimize = optimize,
    }).builder, lib);
    lib.addModule("freetype", freetype_dep.module("mach-freetype"));

    // ZIGIMG
    const zigimg_dep = b.dependency("zigimg", .{
        .target = target,
        .optimize = optimize,
    });

    const assets_mod = b.addModule("assets", .{
        .source_file = .{ .path = "assets/main.zig" },
    });
    lib.addModule("assets", assets_mod);

    b.installArtifact(lib);

    const module = b.addModule("zigurat", .{
        .source_file = .{ .path = "src/main.zig" },
        .dependencies = &.{
            .{ .name = "assets", .module = assets_mod },
            .{ .name = "gpu", .module = gpu_dep.module("mach-gpu") },
            .{ .name = "glfw", .module = glfw_dep.module("mach-glfw") },
            .{ .name = "freetype", .module = freetype_dep.module("mach-freetype") },
            .{ .name = "zigimg", .module = zigimg_dep.module("zigimg") },
        },
    });

    // Examples
    const hello_example = b.addExecutable(.{
        .name = "hello",
        .root_source_file = .{ .path = "examples/hello.zig" },
        .target = target,
        .optimize = optimize,
    });
    hello_example.addModule("zigurat", module);

    @import("mach_glfw").link(b.dependency("mach_glfw", .{
        .target = target,
        .optimize = optimize,
    }).builder, hello_example);

    @import("mach_gpu").link(b.dependency("mach_gpu", .{
        .target = target,
        .optimize = optimize,
    }).builder, hello_example, .{}) catch unreachable;

    @import("mach_freetype").linkFreetype(b.dependency("mach_freetype", .{
        .target = target,
        .optimize = optimize,
    }).builder, hello_example);

    b.installArtifact(hello_example);
    const run_hello_cmd = b.addRunArtifact(hello_example);
    run_hello_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_hello_cmd.addArgs(args);
    }

    const run_hello_step = b.step("run-hello", "Run the hello example");
    run_hello_step.dependOn(&run_hello_cmd.step);

    // Tests
    addTest(b, "main", optimize, target);
    addTest(b, "font", optimize, target);
    addTest(b, "draw", optimize, target);
}

fn addTest(b: *std.Build, comptime name: []const u8, optimize: std.builtin.OptimizeMode, target: std.zig.CrossTarget) void {
    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/" ++ name ++ ".zig" },
        .target = target,
        .optimize = optimize,
    });

    // GLFW
    const glfw_dep = b.dependency("mach_glfw", .{
        .target = target,
        .optimize = optimize,
    });
    unit_tests.addModule("glfw", glfw_dep.module("mach-glfw"));
    @import("mach_glfw").link(b.dependency("mach_glfw", .{
        .target = target,
        .optimize = optimize,
    }).builder, unit_tests);

    // GPU
    const gpu_dep = b.dependency("mach_gpu", .{
        .target = target,
        .optimize = optimize,
    });
    unit_tests.addModule("gpu", gpu_dep.module("mach-gpu"));
    @import("mach_gpu").link(b.dependency("mach_gpu", .{
        .target = target,
        .optimize = optimize,
    }).builder, unit_tests, .{}) catch unreachable;

    // FREETYPE
    const freetype_dep = b.dependency("mach_freetype", .{
        .target = target,
        .optimize = optimize,
    });
    unit_tests.addModule("freetype", freetype_dep.module("mach-freetype"));
    @import("mach_freetype").linkFreetype(b.dependency("mach_freetype", .{
        .target = target,
        .optimize = optimize,
    }).builder, unit_tests);

    // ZIGIMG
    const zigimg_dep = b.dependency("zigimg", .{
        .target = target,
        .optimize = optimize,
    });
    unit_tests.addModule("zigimg", zigimg_dep.module("zigimg"));

    const assets_mod = b.addModule("assets", .{
        .source_file = .{ .path = "assets/main.zig" },
    });
    unit_tests.addModule("assets", assets_mod);

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test-" ++ name, "Run " ++ name ++ "tests");
    test_step.dependOn(&run_unit_tests.step);
}
