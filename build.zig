const std = @import("std");
const integration = @import("test/integration.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const core_mod = b.addModule("zap_core", .{
        .root_source_file = b.path("src/core/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const parse_mod = b.addModule("zap_parse", .{
        .root_source_file = b.path("src/parse/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "zap_core", .module = core_mod }},
    });

    const help_mod = b.addModule("zap_help", .{
        .root_source_file = b.path("src/help/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "zap_core", .module = core_mod }},
    });

    const completions_mod = b.addModule("zap_completions", .{
        .root_source_file = b.path("src/completions/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "zap_core", .module = core_mod }},
    });

    const zap_mod = b.addModule("zap", .{
        .root_source_file = b.path("src/zap.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zap_core", .module = core_mod },
            .{ .name = "zap_parse", .module = parse_mod },
            .{ .name = "zap_help", .module = help_mod },
            .{ .name = "zap_completions", .module = completions_mod },
        },
    });

    // Each module is tested independently so its boundaries (and its tests) are
    // exercised on their own, not just transitively through the facade.
    const test_step = b.step("test", "Run all tests");
    for ([_]*std.Build.Module{ core_mod, parse_mod, help_mod, completions_mod, zap_mod }) |mod| {
        const mod_tests = b.addTest(.{ .root_module = mod });
        test_step.dependOn(&b.addRunArtifact(mod_tests).step);
    }

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

    const nested_exe = b.addExecutable(.{
        .name = "nested",
        .root_module = b.createModule(.{
            .root_source_file = b.path("example/nested.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "zap", .module = zap_mod }},
        }),
    });
    b.installArtifact(nested_exe);

    const integration_step = integration.addIntegrationTests(b, add_exe, math_exe, shell_completion_exe, nested_exe, zap_mod);
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
    const nested_test_script = b.path("tests/completions/test_nested_completions.sh");
    for ([_][]const u8{ "fish", "bash", "zsh" }) |shell| {
        const run = b.addSystemCommand(&.{"bash"});
        run.addFileArg(nested_test_script);
        run.addArtifactArg(nested_exe);
        run.addArg(shell);
        test_shell_completions_step.dependOn(&run.step);
    }
}
