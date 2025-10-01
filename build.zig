const std = @import("std");
const mz = @import("microzig");

const MicroBuild = mz.MicroBuild(.{ .rp2xxx = true });

pub fn build(b: *std.Build) void {
    //standard build.zig stuff
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib_mod = b.addModule("zigbasic", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_mod.addImport("zigbasic_lib", lib_mod);

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "zigbasic",
        .root_module = lib_mod,
    });

    b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "zigbasic",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    //Microzig specific stuff
    const mz_dep = b.dependency("microzig", .{});
    const mb = MicroBuild.init(b, mz_dep) orelse {
        std.log.err("couldn't init microbuild for microzig", .{});
        return;
    };

    const fw = mb.add_firmware(.{
        .name = "danbasic",
        .target = mb.ports.rp2xxx.boards.raspberrypi.pico2_arm,
        .optimize = .ReleaseSmall,
        .root_source_file = b.path("src/pico_firmware.zig"),
    });

    fw.app_mod.addImport("zigbasic", lib_mod);

    mb.install_firmware(fw, .{});

    // const lib_unit_tests = b.addTest(.{
    //     .root_module = lib_mod,
    // });

    // const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    // const exe_unit_tests = b.addTest(.{
    //     .root_module = exe_mod,
    // });

    // const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // const test_step = b.step("test", "Run unit tests");
    // test_step.dependOn(&run_lib_unit_tests.step);
    // test_step.dependOn(&run_exe_unit_tests.step);
}
