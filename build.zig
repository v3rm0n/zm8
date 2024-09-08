const std = @import("std");
const sdl = @import("sdl");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sdk = sdl.init(b, .{});

    const exe = b.addExecutable(.{
        .name = "zm8",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.linkSystemLibrary("usb-1.0");

    sdk.link(exe, .dynamic, sdl.Library.SDL2); // link SDL2 as a shared library
    exe.root_module.addImport("sdl2", sdk.getWrapperModule());

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

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
