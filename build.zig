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

    const async_square_exe = b.addExecutable(.{
        .name = "async-square",
        .root_module = b.createModule(.{
            .root_source_file = b.path("example/async-square.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "zap", .module = zap_mod }},
        }),
    });
    b.installArtifact(async_square_exe);

    const shell_completion_exe = b.addExecutable(.{
        .name = "shell-completion",
        .root_module = b.createModule(.{
            .root_source_file = b.path("example/shell-completion.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "zap", .module = zap_mod }},
        }),
    });
    b.installArtifact(shell_completion_exe);

    const integration_step = integration.addIntegrationTests(b, add_exe, math_exe, shell_completion_exe, zap_mod);
    test_step.dependOn(integration_step);

    const test_shell_completions_step = b.step(
        "test-shell-completions",
        "Run shell completion tests",
    );
    const test_script = b.path("tests/completions/test_completions.sh");
    for ([_][]const u8{ "fish", "bash", "zsh" }) |shell| {
        const run = b.addSystemCommand(&.{"bash"});
        run.addFileArg(test_script);
        run.addArtifactArg(shell_completion_exe);
        run.addArg(shell);
        test_shell_completions_step.dependOn(&run.step);
    }
}
