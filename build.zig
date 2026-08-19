const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "sandbox",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .optimize = optimize,
            .target = target,
        }),
    });

    const bilerp = b.addExecutable(.{
        .name = "bilerp",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bilerp.zig"),
            .optimize = optimize,
            .target = target,
        }),
    });

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const raylib = raylib_dep.module("raylib"); // main raylib module
    const raygui = raylib_dep.module("raygui"); // raygui module
    const raylib_artifact = raylib_dep.artifact("raylib"); // raylib C library
    raylib_artifact.root_module.addCMacro("SUPPORT_FILEFORMAT_JPG", "true");

    exe.root_module.linkLibrary(raylib_artifact);
    exe.root_module.addImport("raylib", raylib);
    exe.root_module.addImport("raygui", raygui);

    bilerp.root_module.linkLibrary(raylib_artifact);
    bilerp.root_module.addImport("raylib", raylib);
    bilerp.root_module.addImport("raygui", raygui);

    b.installArtifact(exe);
    const exe_check = b.addExecutable(.{
        .name = "sandbox",
        .root_module = exe.root_module,
    });

    b.installArtifact(bilerp);

    const check = b.step("check", "Check compilation for ZLS");
    check.dependOn(&exe_check.step);
}
