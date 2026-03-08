const std = @import("std");
const integration = @import("test/integration.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zap_mod = b.addModule("zap", .{
        .root_source_file = b.path("src/zap.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib_tests = b.addTest(.{
        .root_module = zap_mod,
    });
    const run_lib_tests = b.addRunArtifact(lib_tests);

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_lib_tests.step);

    const add_exe = b.addExecutable(.{
        .name = "add",
        .root_module = b.createModule(.{
            .root_source_file = b.path("example/add.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "zap", .module = zap_mod }},
        }),
    });
    b.installArtifact(add_exe);

    const math_exe = b.addExecutable(.{
        .name = "math",
        .root_module = b.createModule(.{
            .root_source_file = b.path("example/math.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "zap", .module = zap_mod }},
        }),
    });
    b.installArtifact(math_exe);

    const integration_step = integration.addIntegrationTests(b, add_exe, math_exe, zap_mod);
    test_step.dependOn(integration_step);
}
