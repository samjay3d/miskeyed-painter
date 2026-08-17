const std = @import("std");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    if (args.len == 2 and std.mem.eql(u8, args[1], "--check-site")) {
        if (std.posix.getenv("MISAPP_SITE_PACKAGES") == null) return error.MissingSitePackages;
        return;
    }
    const separator: u8 = if (@import("builtin").os.tag == .windows) ';' else ':';
    const expected = try std.fmt.allocPrint(allocator, "new{c}old", .{separator});
    if (!std.mem.eql(u8, std.posix.getenv("SUBSTANCE_PAINTER_PLUGINS_PATH") orelse "", expected)) return error.BadPluginPath;
    if (!std.mem.eql(u8, std.posix.getenv("CHAIN_WORKED") orelse "", "yes")) return error.ChainFailed;
    if (!std.mem.eql(u8, std.posix.getenv("CONDITION_WORKED") orelse "", "yes")) return error.ConditionFailed;
    if (std.posix.getenv("MISAPP_PYTHON_ENV") == null) return error.MissingPythonEnvironment;
    if (std.posix.getenv("MISAPP_PYTHON_EXECUTABLE") == null) return error.MissingPythonExecutable;
    if (args.len != 2 or !std.mem.eql(u8, args[1], "expected-argument")) return error.BadArguments;
}
