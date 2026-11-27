const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSafe,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const exe = b.addExecutable(.{
        .name = "vedit",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const test_step = b.step("test", "Run all Zig 0.17.0 unit & differential kernel tests");
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const unit_tests = b.addTest(.{
        .root_module = test_mod,
    });
    const run_tests = b.addRunArtifact(unit_tests);
    test_step.dependOn(&run_tests.step);

    const court_step = b.step("test-court", "Run full zero-Python adversarial sabotage, flagship regression & closed-loop court");
    const court_mod = b.createModule(.{
        .root_source_file = b.path("src/court_tests.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const court_tests = b.addTest(.{
        .root_module = court_mod,
    });
    const run_court = b.addRunArtifact(court_tests);
    run_court.step.dependOn(b.getInstallStep());
    court_step.dependOn(&run_court.step);
}
