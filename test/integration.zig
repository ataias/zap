const std = @import("std");

pub fn addIntegrationTests(
    b: *std.Build,
    add_exe: *std.Build.Step.Compile,
    math_exe: *std.Build.Step.Compile,
    shell_completion_exe: *std.Build.Step.Compile,
    zap_mod: *std.Build.Module,
) *std.Build.Step {
    const step = b.step("integration-test", "Run integration tests for examples");

    addExampleTests(b, step, add_exe);
    addMathTests(b, step, math_exe);
    addShellCompletionTests(b, step, shell_completion_exe);
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
    // --generate-completion-script works for simple (no subcommand) command
    {
        const run = b.addRunArtifact(add_exe);
        run.addArgs(&.{ "--generate-completion-script", "fish" });
        run.expectStdOutMatch("complete -c add");
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
    // --generate-completion-script works for subcommand-based command
    {
        const run = b.addRunArtifact(math_exe);
        run.addArgs(&.{ "--generate-completion-script", "fish" });
        run.expectStdOutMatch("complete -c math");
        step.dependOn(&run.step);
    }
}

fn addShellCompletionTests(
    b: *std.Build,
    step: *std.Build.Step,
    exe: *std.Build.Step.Compile,
) void {
    // --help shows visible subcommands, hides debug-info
    {
        const run = b.addRunArtifact(exe);
        run.addArgs(&.{"--help"});
        run.expectStdOutMatch("deploy");
        step.dependOn(&run.step);
    }
    {
        const run = b.addRunArtifact(exe);
        run.addArgs(&.{"--help"});
        run.expectStdOutMatch("status");
        step.dependOn(&run.step);
    }
    // deploy subcommand works
    {
        const run = b.addRunArtifact(exe);
        run.addArgs(&.{ "deploy", "--target", "prod" });
        run.expectStdOutMatch("deploying to prod");
        step.dependOn(&run.step);
    }
    // deploy --help shows visible fields, hides debug-trace
    {
        const run = b.addRunArtifact(exe);
        run.addArgs(&.{ "deploy", "--help" });
        run.expectStdOutMatch("--port");
        step.dependOn(&run.step);
    }
    // hidden field can still be parsed
    {
        const run = b.addRunArtifact(exe);
        run.addArgs(&.{ "deploy", "--target", "staging", "--debug-trace" });
        run.expectStdOutMatch("debug trace enabled");
        step.dependOn(&run.step);
    }
    // hidden subcommand can still be dispatched
    {
        const run = b.addRunArtifact(exe);
        run.addArgs(&.{"debug-info"});
        run.expectStdOutMatch("debug info output");
        step.dependOn(&run.step);
    }
    // status subcommand works
    {
        const run = b.addRunArtifact(exe);
        run.addArgs(&.{"status"});
        run.expectStdOutMatch("status: running");
        step.dependOn(&run.step);
    }
    // --generate-completion-script fish exits 0 with completion output
    {
        const run = b.addRunArtifact(exe);
        run.addArgs(&.{ "--generate-completion-script", "fish" });
        run.expectStdOutMatch("complete -c");
        step.dependOn(&run.step);
    }
    // --generate-completion-script with missing shell exits 1
    {
        const run = b.addRunArtifact(exe);
        run.addArgs(&.{"--generate-completion-script"});
        run.expectStdErrMatch("requires a shell name");
        run.expectExitCode(1);
        step.dependOn(&run.step);
    }
    // --generate-completion-script with invalid shell exits 1
    {
        const run = b.addRunArtifact(exe);
        run.addArgs(&.{ "--generate-completion-script", "invalid" });
        run.expectStdErrMatch("unknown shell");
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
