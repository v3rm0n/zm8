const std = @import("std");
const sdl = @import("sdl");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sdk = sdl.init(b, .{});

    const zusb = b.dependency("zusb", .{});

    const ini = b.dependency("ini", .{});

    const exe = b.addExecutable(.{
        .name = "zm8",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const zusb_module = zusb.module("zusb");

    zusb_module.addSystemIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });

    exe.linkSystemLibrary("usb-1.0");

    sdk.link(exe, .dynamic, sdl.Library.SDL2); // link SDL2 as a shared library
    exe.root_module.addImport("sdl2", sdk.getWrapperModule());
    exe.root_module.addImport("zusb", zusb_module);
    exe.root_module.addImport("ini", ini.module("ini"));

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_unit_tests.linkSystemLibrary("usb-1.0");

    sdk.link(exe_unit_tests, .dynamic, sdl.Library.SDL2); // link SDL2 as a shared library
    exe_unit_tests.root_module.addImport("sdl2", sdk.getWrapperModule());
    exe_unit_tests.root_module.addImport("ini", ini.module("ini"));

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
