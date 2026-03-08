const std = @import("std");

pub fn addIntegrationTests(
    b: *std.Build,
    add_exe: *std.Build.Step.Compile,
    math_exe: *std.Build.Step.Compile,
    zap_mod: *std.Build.Module,
) *std.Build.Step {
    const step = b.step("integration-test", "Run integration tests for examples");

    addExampleTests(b, step, add_exe);
    addMathTests(b, step, math_exe);
    addCompileErrorTests(b, step, zap_mod);

    return step;
}

fn addExampleTests(
    b: *std.Build,
    step: *std.Build.Step,
    add_exe: *std.Build.Step.Compile,
) void {
    {
        const run = b.addRunArtifact(add_exe);
        run.addArgs(&.{ "1", "2", "3" });
        run.expectStdOutEqual("6\n");
        step.dependOn(&run.step);
    }
    {
        const run = b.addRunArtifact(add_exe);
        run.addArgs(&.{ "--verbose", "1", "2", "3" });
        run.expectStdOutEqual("1 + 2 + 3 = 6\n");
        step.dependOn(&run.step);
    }
    {
        const run = b.addRunArtifact(add_exe);
        run.addArgs(&.{"10"});
        run.expectStdOutEqual("10\n");
        step.dependOn(&run.step);
    }
    {
        const run = b.addRunArtifact(add_exe);
        run.addArgs(&.{"--help"});
        run.expectStdOutMatch("USAGE: add");
        step.dependOn(&run.step);
    }
    {
        const run = b.addRunArtifact(add_exe);
        run.addArgs(&.{"--badopt"});
        run.expectStdErrMatch("unknown option '--badopt'");
        run.expectExitCode(1);
        step.dependOn(&run.step);
    }
    {
        const run = b.addRunArtifact(add_exe);
        run.expectStdErrMatch("missing required argument");
        run.expectExitCode(1);
        step.dependOn(&run.step);
    }
}

fn addMathTests(
    b: *std.Build,
    step: *std.Build.Step,
    math_exe: *std.Build.Step.Compile,
) void {
    {
        const run = b.addRunArtifact(math_exe);
        run.addArgs(&.{ "add", "1", "2", "3" });
        run.expectStdOutEqual("6\n");
        step.dependOn(&run.step);
    }
    {
        const run = b.addRunArtifact(math_exe);
        run.addArgs(&.{ "multiply", "2", "3", "4" });
        run.expectStdOutEqual("24\n");
        step.dependOn(&run.step);
    }
    {
        const run = b.addRunArtifact(math_exe);
        run.addArgs(&.{"--help"});
        run.expectStdOutMatch("USAGE: math");
        step.dependOn(&run.step);
    }
    {
        const run = b.addRunArtifact(math_exe);
        run.addArgs(&.{ "add", "--help" });
        run.expectStdOutMatch("USAGE:");
        step.dependOn(&run.step);
    }
    {
        const run = b.addRunArtifact(math_exe);
        run.addArgs(&.{"badcmd"});
        run.expectStdErrMatch("unknown subcommand 'badcmd'");
        run.expectExitCode(1);
        step.dependOn(&run.step);
    }
    {
        const run = b.addRunArtifact(math_exe);
        run.addArgs(&.{"add"});
        run.expectStdErrMatch("missing required argument");
        run.expectExitCode(1);
        step.dependOn(&run.step);
    }
}

fn addCompileErrorTests(
    b: *std.Build,
    step: *std.Build.Step,
    zap_mod: *std.Build.Module,
) void {
    {
        const wf = b.addWriteFiles();
        const source = wf.add("missing_run.zig",
            \\const std = @import("std");
            \\const zap = @import("zap");
            \\const Cmd = struct {
            \\    verbose: bool = false,
            \\};
            \\pub fn main(init: std.process.Init) !void {
            \\    return zap.run(Cmd, init);
            \\}
        );
        const exe = b.addExecutable(.{
            .name = "missing_run",
            .root_module = b.createModule(.{
                .root_source_file = source,
                .target = zap_mod.resolved_target,
                .imports = &.{.{ .name = "zap", .module = zap_mod }},
            }),
        });
        exe.expect_errors = .{ .contains = "must have a pub fn run() or subcommands" };
        step.dependOn(&exe.step);
    }
}
