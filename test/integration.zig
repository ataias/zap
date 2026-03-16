const std = @import("std");

pub fn addIntegrationTests(
    b: *std.Build,
    add_exe: *std.Build.Step.Compile,
    math_exe: *std.Build.Step.Compile,
    shell_completion_exe: *std.Build.Step.Compile,
    nested_exe: *std.Build.Step.Compile,
    zap_mod: *std.Build.Module,
) *std.Build.Step {
    const step = b.step("integration-test", "Run integration tests for examples");

    addExampleTests(b, step, add_exe);
    addMathTests(b, step, math_exe);
    addShellCompletionTests(b, step, shell_completion_exe);
    addNestedTests(b, step, nested_exe);
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
    {
        const run = b.addRunArtifact(add_exe);
        run.addArgs(&.{ "--generate-completion-script", "zsh" });
        run.expectStdOutMatch("#compdef add");
        step.dependOn(&run.step);
    }
    {
        const run = b.addRunArtifact(add_exe);
        run.addArgs(&.{ "--generate-completion-script", "bash" });
        run.expectStdOutMatch("complete -F");
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
        run.addArgs(&.{"ad"});
        run.expectStdErrMatch("unknown subcommand 'ad', did you mean 'add'?");
        run.expectExitCode(1);
        step.dependOn(&run.step);
    }
    {
        const run = b.addRunArtifact(math_exe);
        run.addArgs(&.{"mlutiply"});
        run.expectStdErrMatch("unknown subcommand 'mlutiply', did you mean 'multiply'?");
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
    {
        const run = b.addRunArtifact(math_exe);
        run.addArgs(&.{ "--generate-completion-script", "zsh" });
        run.expectStdOutMatch("#compdef math");
        step.dependOn(&run.step);
    }
    {
        const run = b.addRunArtifact(math_exe);
        run.addArgs(&.{ "--generate-completion-script", "bash" });
        run.expectStdOutMatch("complete -F");
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
    // --generate-completion-script zsh exits 0 with completion output
    {
        const run = b.addRunArtifact(exe);
        run.addArgs(&.{ "--generate-completion-script", "zsh" });
        run.expectStdOutMatch("#compdef");
        step.dependOn(&run.step);
    }
    // --generate-completion-script bash exits 0 with completion output
    {
        const run = b.addRunArtifact(exe);
        run.addArgs(&.{ "--generate-completion-script", "bash" });
        run.expectStdOutMatch("complete -F");
        step.dependOn(&run.step);
    }
    // from_command hint appears in generated fish completions
    {
        const run = b.addRunArtifact(exe);
        run.addArgs(&.{ "--generate-completion-script", "fish" });
        run.expectStdOutMatch("echo web api worker");
        step.dependOn(&run.step);
    }
    // from_command hint appears in generated bash completions
    {
        const run = b.addRunArtifact(exe);
        run.addArgs(&.{ "--generate-completion-script", "bash" });
        run.expectStdOutMatch("echo web api worker");
        step.dependOn(&run.step);
    }
    // from_command hint appears in generated zsh completions
    {
        const run = b.addRunArtifact(exe);
        run.addArgs(&.{ "--generate-completion-script", "zsh" });
        run.expectStdOutMatch("echo web api worker");
        step.dependOn(&run.step);
    }
}

fn addNestedTests(
    b: *std.Build,
    step: *std.Build.Step,
    nested_exe: *std.Build.Step.Compile,
) void {
    {
        const run = b.addRunArtifact(nested_exe);
        run.addArgs(&.{ "server", "start" });
        run.expectStdOutEqual("starting server on port 8080\n");
        step.dependOn(&run.step);
    }
    {
        const run = b.addRunArtifact(nested_exe);
        run.addArgs(&.{ "server", "start", "--port", "9090" });
        run.expectStdOutEqual("starting server on port 9090\n");
        step.dependOn(&run.step);
    }
    {
        const run = b.addRunArtifact(nested_exe);
        run.addArgs(&.{ "server", "stop" });
        run.expectStdOutEqual("stopping server\n");
        step.dependOn(&run.step);
    }
    {
        const run = b.addRunArtifact(nested_exe);
        run.addArgs(&.{ "server", "stop", "--force" });
        run.expectStdOutEqual("force stopping server\n");
        step.dependOn(&run.step);
    }
    {
        const run = b.addRunArtifact(nested_exe);
        run.addArgs(&.{"version"});
        run.expectStdOutEqual("1.0.0\n");
        step.dependOn(&run.step);
    }
    // nested --help shows top-level subcommands
    {
        const run = b.addRunArtifact(nested_exe);
        run.addArgs(&.{"--help"});
        run.expectStdOutMatch("server");
        step.dependOn(&run.step);
    }
    {
        const run = b.addRunArtifact(nested_exe);
        run.addArgs(&.{"--help"});
        run.expectStdOutMatch("version");
        step.dependOn(&run.step);
    }
    // nested server --help shows sub-subcommands
    {
        const run = b.addRunArtifact(nested_exe);
        run.addArgs(&.{ "server", "--help" });
        run.expectStdOutMatch("start");
        step.dependOn(&run.step);
    }
    {
        const run = b.addRunArtifact(nested_exe);
        run.addArgs(&.{ "server", "--help" });
        run.expectStdOutMatch("stop");
        step.dependOn(&run.step);
    }
    // nested server start --help shows start's options
    {
        const run = b.addRunArtifact(nested_exe);
        run.addArgs(&.{ "server", "start", "--help" });
        run.expectStdOutMatch("--port");
        step.dependOn(&run.step);
    }
    // nested server (no subcommand) shows help
    {
        const run = b.addRunArtifact(nested_exe);
        run.addArgs(&.{"server"});
        run.expectStdOutMatch("USAGE:");
        step.dependOn(&run.step);
    }
    // unknown sub-subcommand
    {
        const run = b.addRunArtifact(nested_exe);
        run.addArgs(&.{ "server", "badcmd" });
        run.expectStdErrMatch("unknown subcommand 'badcmd'");
        run.expectExitCode(1);
        step.dependOn(&run.step);
    }
    // typo suggestion at nested level
    {
        const run = b.addRunArtifact(nested_exe);
        run.addArgs(&.{ "server", "strat" });
        run.expectStdErrMatch("did you mean 'start'");
        run.expectExitCode(1);
        step.dependOn(&run.step);
    }
    // completion scripts
    {
        const run = b.addRunArtifact(nested_exe);
        run.addArgs(&.{ "--generate-completion-script", "fish" });
        run.expectStdOutMatch("complete -c nested");
        step.dependOn(&run.step);
    }
    {
        const run = b.addRunArtifact(nested_exe);
        run.addArgs(&.{ "--generate-completion-script", "zsh" });
        run.expectStdOutMatch("#compdef nested");
        step.dependOn(&run.step);
    }
    {
        const run = b.addRunArtifact(nested_exe);
        run.addArgs(&.{ "--generate-completion-script", "bash" });
        run.expectStdOutMatch("complete -F");
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
        exe.expect_errors = .{ .contains = "Cmd' must have a pub fn run() or subcommands" };
        step.dependOn(&exe.step);
    }
    {
        const wf = b.addWriteFiles();
        const source = wf.add("nested_missing_run.zig",
            \\const std = @import("std");
            \\const zap = @import("zap");
            \\const Bad = struct {};
            \\const Parent = struct {
            \\    pub const meta: zap.CommandMeta = .{
            \\        .subcommands = &.{Bad},
            \\    };
            \\};
            \\pub fn main(init: std.process.Init) !void {
            \\    return zap.run(Parent, init);
            \\}
        );
        const exe = b.addExecutable(.{
            .name = "nested_missing_run",
            .root_module = b.createModule(.{
                .root_source_file = source,
                .target = zap_mod.resolved_target,
                .imports = &.{.{ .name = "zap", .module = zap_mod }},
            }),
        });
        exe.expect_errors = .{ .contains = "Bad' must have a pub fn run() or subcommands" };
        step.dependOn(&exe.step);
    }
}
