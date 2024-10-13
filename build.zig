const std = @import("std");
const sdl = @import("sdl");
const Build = std.Build;
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sdk = sdl.init(b, .{});
    const ini = b.dependency("ini", .{});

    if (target.result.os.tag == .emscripten) {
        const emsdk = b.dependency("emsdk", .{});
        const emsdk_sysroot = emSdkLazyPath(b, emsdk, &.{ "upstream", "emscripten", "cache", "sysroot" });
        b.sysroot = emsdk_sysroot.getPath(b);

        const wasmzm8 = b.addStaticLibrary(.{
            .name = "zm8",
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        });

        // one-time setup of Emscripten SDK
        if (try emSdkSetupStep(b, emsdk)) |emsdk_setup| {
            wasmzm8.step.dependOn(&emsdk_setup.step);
        }
        // add the Emscripten system include seach path
        wasmzm8.addSystemIncludePath(emSdkLazyPath(b, emsdk, &.{ "upstream", "emscripten", "cache", "sysroot", "include" }));

        const sdl_dep = b.dependency("sdlsrc", .{
            .optimize = .ReleaseFast,
            .target = target,
        });
        sdl_dep.artifact("SDL2").addSystemIncludePath(emSdkLazyPath(b, emsdk, &.{ "upstream", "emscripten", "cache", "sysroot", "include" }));

        wasmzm8.linkLibrary(sdl_dep.artifact("SDL2"));

        wasmzm8.root_module.addImport("sdl2", sdk.getWrapperModule());
        wasmzm8.root_module.addImport("ini", ini.module("ini"));

        const link_step = try emLinkStep(b, .{
            .lib_main = wasmzm8,
            .target = target,
            .optimize = optimize,
            .emsdk = emsdk,
            .extra_args = &.{
                "-sINITIAL_MEMORY=64Mb",
                "-sSTACK_SIZE=16Mb",
                "-sUSE_OFFSET_CONVERTER=1",
                "-sFULL-ES3=1",
                "-sUSE_GLFW=3",
                "-sASYNCIFY",
                "-sASYNCIFY_IMPORTS=webserial_read,webserial_write",
                "--js-library=src/webserial/webserial.js",
            },
        });

        link_step.step.dependOn(&b.addInstallFileWithDir(b.path("index.html"), .prefix, "web/index.html").step);

        var run = emRunStep(b, .{ .name = "zm8", .emsdk = emsdk });
        run.step.dependOn(&link_step.step);
        const run_cmd = b.step("run", "Run the demo for web via emrun");
        run_cmd.dependOn(&run.step);

        b.installArtifact(wasmzm8);
    } else {
        const use_libusb = b.option(bool, "use_libusb", "Use libusb instead of libserialport") orelse false;
        const options = b.addOptions();
        options.addOption(bool, "use_libusb", use_libusb);

        const zusb = b.dependency("zusb", .{});

        const exe = b.addExecutable(.{
            .name = "zm8",
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        });

        exe.root_module.addOptions("config", options);

        const zusb_module = zusb.module("zusb");

        zusb_module.addSystemIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });

        exe.linkSystemLibrary("usb-1.0");
        exe.linkSystemLibrary("serialport");

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

        exe_unit_tests.root_module.addImport("ini", ini.module("ini"));

        const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

        const test_step = b.step("test", "Run unit tests");
        test_step.dependOn(&run_exe_unit_tests.step);
    }
}

pub const EmLinkOptions = struct {
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    lib_main: *Build.Step.Compile, // the actual Zig code must be compiled to a static link library
    emsdk: *Build.Dependency,
    release_use_closure: bool = true,
    release_use_lto: bool = true,
    use_webgpu: bool = false,
    use_webgl2: bool = false,
    use_emmalloc: bool = false,
    use_filesystem: bool = true,
    shell_file_path: ?Build.LazyPath = null,
    extra_args: []const []const u8 = &.{},
};

pub fn emLinkStep(b: *Build, options: EmLinkOptions) !*Build.Step.InstallDir {
    const emcc_path = emSdkLazyPath(b, options.emsdk, &.{ "upstream", "emscripten", "emcc" }).getPath(b);
    const emcc = b.addSystemCommand(&.{emcc_path});
    emcc.setName("emcc"); // hide emcc path
    if (options.optimize == .Debug) {
        emcc.addArgs(&.{ "-Og", "-sSAFE_HEAP=1", "-sSTACK_OVERFLOW_CHECK=1", "-gsource-map" });
    } else {
        emcc.addArg("-sASSERTIONS=0");
        if (options.optimize == .ReleaseSmall) {
            emcc.addArg("-Oz");
        } else {
            emcc.addArg("-O3");
        }
        if (options.release_use_lto) {
            emcc.addArg("-flto");
        }
        if (options.release_use_closure) {
            emcc.addArgs(&.{ "--closure", "1" });
        }
    }
    if (options.use_webgpu) {
        emcc.addArg("-sUSE_WEBGPU=1");
    }
    if (options.use_webgl2) {
        emcc.addArg("-sUSE_WEBGL2=1");
    }
    if (!options.use_filesystem) {
        emcc.addArg("-sNO_FILESYSTEM=1");
    }
    if (options.use_emmalloc) {
        emcc.addArg("-sMALLOC='emmalloc'");
    }
    if (options.shell_file_path) |shell_file_path| {
        emcc.addPrefixedFileArg("--shell-file=", shell_file_path);
    }
    for (options.extra_args) |arg| {
        emcc.addArg(arg);
    }

    // add the main lib, and then scan for library dependencies and add those too
    emcc.addArtifactArg(options.lib_main);
    var it = options.lib_main.root_module.iterateDependencies(options.lib_main, false);
    while (it.next()) |item| {
        for (item.module.link_objects.items) |link_object| {
            switch (link_object) {
                .other_step => |compile_step| {
                    switch (compile_step.kind) {
                        .lib => {
                            emcc.addArtifactArg(compile_step);
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }
    }
    emcc.addArg("-o");
    const out_file = emcc.addOutputFileArg(b.fmt("{s}.html", .{options.lib_main.name}));

    // the emcc linker creates 3 output files (.html, .wasm and .js)
    const install = b.addInstallDirectory(.{
        .source_dir = out_file.dirname(),
        .install_dir = .prefix,
        .install_subdir = "web",
    });
    install.step.dependOn(&emcc.step);

    // get the emcc step to run on 'zig build'
    b.getInstallStep().dependOn(&install.step);
    return install;
}

pub const EmRunOptions = struct {
    name: []const u8,
    emsdk: *Build.Dependency,
};
pub fn emRunStep(b: *Build, options: EmRunOptions) *Build.Step.Run {
    const emrun_path = b.findProgram(&.{"emrun"}, &.{}) catch emSdkLazyPath(b, options.emsdk, &.{ "upstream", "emscripten", "emrun" }).getPath(b);
    const emrun = b.addSystemCommand(&.{ emrun_path, "--browser=chrome", b.fmt("{s}/web/{s}.html", .{ b.install_path, options.name }) });
    return emrun;
}

// helper function to build a LazyPath from the emsdk root and provided path components
fn emSdkLazyPath(b: *Build, emsdk: *Build.Dependency, subPaths: []const []const u8) Build.LazyPath {
    return emsdk.path(b.pathJoin(subPaths));
}

fn createEmsdkStep(b: *Build, emsdk: *Build.Dependency) *Build.Step.Run {
    if (builtin.os.tag == .windows) {
        return b.addSystemCommand(&.{emSdkLazyPath(b, emsdk, &.{"emsdk.bat"}).getPath(b)});
    } else {
        const step = b.addSystemCommand(&.{"bash"});
        step.addArg(emSdkLazyPath(b, emsdk, &.{"emsdk"}).getPath(b));
        return step;
    }
}

fn emSdkSetupStep(b: *Build, emsdk: *Build.Dependency) !?*Build.Step.Run {
    const dot_emsc_path = emSdkLazyPath(b, emsdk, &.{".emscripten"}).getPath(b);
    const dot_emsc_exists = !std.meta.isError(std.fs.accessAbsolute(dot_emsc_path, .{}));
    if (!dot_emsc_exists) {
        const emsdk_install = createEmsdkStep(b, emsdk);
        emsdk_install.addArgs(&.{ "install", "latest" });
        const emsdk_activate = createEmsdkStep(b, emsdk);
        emsdk_activate.addArgs(&.{ "activate", "latest" });
        emsdk_activate.step.dependOn(&emsdk_install.step);
        return emsdk_activate;
    } else {
        return null;
    }
}
