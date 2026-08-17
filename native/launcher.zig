const std = @import("std");

const Allocator = std.mem.Allocator;
const EditKind = enum { set, prepend, append };
const Edit = struct { kind: EditKind, name: []const u8, value: []const u8, condition: ?[]const u8 = null };
const Recipe = struct {
    name: []const u8 = "",
    executable_env: []const u8 = "",
    python_requires: []const u8 = "",
    executables: std.ArrayList([]const u8),
    search: std.ArrayList([]const u8),
    extends: std.ArrayList([]const u8),
    edits: std.ArrayList(Edit),

    fn init(allocator: Allocator) Recipe {
        return .{
            .executables = std.ArrayList([]const u8).init(allocator),
            .search = std.ArrayList([]const u8).init(allocator),
            .extends = std.ArrayList([]const u8).init(allocator),
            .edits = std.ArrayList(Edit).init(allocator),
        };
    }
};

const ParseError = error{ InvalidRecipe, OutOfMemory };

fn platformName() []const u8 {
    return switch (@import("builtin").os.tag) {
        .windows => "windows",
        .macos => "macos",
        else => "linux",
    };
}

fn trim(value: []const u8) []const u8 {
    return std.mem.trim(u8, value, " \t\r");
}

fn scalar(value: []const u8) []const u8 {
    const clean = trim(value);
    if (clean.len >= 2 and ((clean[0] == '"' and clean[clean.len - 1] == '"') or
        (clean[0] == '\'' and clean[clean.len - 1] == '\'')))
        return clean[1 .. clean.len - 1];
    return clean;
}

fn recipeError(path: []const u8, line: usize, message: []const u8) ParseError {
    std.debug.print("misapp: {s}:{d}: {s}\n", .{ path, line, message });
    return error.InvalidRecipe;
}

fn validEnvName(name: []const u8) bool {
    if (name.len == 0 or name[0] == '=') return false;
    for (name) |char| if (!(std.ascii.isAlphanumeric(char) or char == '_')) return false;
    return true;
}

fn validRecipeId(name: []const u8) bool {
    if (name.len == 0) return false;
    for (name) |char| if (!(std.ascii.isAlphanumeric(char) or char == '-' or char == '_')) return false;
    return true;
}

fn validateCondition(expression: []const u8) bool {
    const value = trim(expression);
    if (std.mem.eql(u8, value, "always")) return true;
    if (std.mem.startsWith(u8, value, "platform == ")) {
        const wanted = trim(value[12..]);
        return std.mem.eql(u8, wanted, "windows") or std.mem.eql(u8, wanted, "macos") or std.mem.eql(u8, wanted, "linux");
    }
    if (std.mem.startsWith(u8, value, "env.")) {
        const rest = value[4..];
        if (std.mem.indexOf(u8, rest, " == ")) |at| return validEnvName(trim(rest[0..at])) and trim(rest[at + 4 ..]).len != 0;
        return validEnvName(trim(rest));
    }
    return false;
}

const PythonVersion = struct { major: u32, minor: u32, patch: u32 = 0 };

fn parsePythonVersion(value: []const u8) ?PythonVersion {
    var parts = std.mem.splitScalar(u8, trim(value), '.');
    const major = std.fmt.parseUnsigned(u32, parts.next() orelse return null, 10) catch return null;
    const minor = std.fmt.parseUnsigned(u32, parts.next() orelse return null, 10) catch return null;
    const patch = if (parts.next()) |part| std.fmt.parseUnsigned(u32, part, 10) catch return null else 0;
    if (parts.next() != null) return null;
    return .{ .major = major, .minor = minor, .patch = patch };
}

fn comparePythonVersion(left: PythonVersion, right: PythonVersion) std.math.Order {
    if (left.major != right.major) return std.math.order(left.major, right.major);
    if (left.minor != right.minor) return std.math.order(left.minor, right.minor);
    return std.math.order(left.patch, right.patch);
}

fn validatePythonRequirement(requirement: []const u8) bool {
    var clauses = std.mem.splitScalar(u8, requirement, ',');
    var found = false;
    while (clauses.next()) |raw_clause| {
        const clause = trim(raw_clause);
        if (clause.len == 0) return false;
        found = true;
        const offset: usize = if (std.mem.startsWith(u8, clause, ">=") or std.mem.startsWith(u8, clause, "<=") or std.mem.startsWith(u8, clause, "==")) 2 else if (std.mem.startsWith(u8, clause, ">") or std.mem.startsWith(u8, clause, "<")) 1 else return false;
        if (parsePythonVersion(clause[offset..]) == null) return false;
    }
    return found;
}

fn pythonRequirementMatches(version: PythonVersion, requirement: []const u8) bool {
    var clauses = std.mem.splitScalar(u8, requirement, ',');
    var found = false;
    while (clauses.next()) |raw_clause| {
        const clause = trim(raw_clause);
        if (clause.len == 0) return false;
        found = true;
        const operators = [_][]const u8{ ">=", "<=", "==", ">", "<" };
        var matched_operator: ?[]const u8 = null;
        for (operators) |operator| if (std.mem.startsWith(u8, clause, operator)) {
            matched_operator = operator;
            break;
        };
        const operator = matched_operator orelse return false;
        const wanted = parsePythonVersion(clause[operator.len..]) orelse return false;
        const order = comparePythonVersion(version, wanted);
        const matches = if (std.mem.eql(u8, operator, ">=")) order != .lt else if (std.mem.eql(u8, operator, "<=")) order != .gt else if (std.mem.eql(u8, operator, "==")) order == .eq else if (std.mem.eql(u8, operator, ">")) order == .gt else order == .lt;
        if (!matches) return false;
    }
    return found;
}

fn parseRecipe(allocator: Allocator, path: []const u8, contents: []const u8) ParseError!Recipe {
    var recipe = Recipe.init(allocator);
    var section: []const u8 = "";
    var platform: []const u8 = "";
    var operation: []const u8 = "";
    var condition: ?[]const u8 = null;
    var schema_seen = false;
    var lines = std.mem.splitScalar(u8, contents, '\n');
    var line_number: usize = 0;
    while (lines.next()) |raw_with_comment| {
        line_number += 1;
        const comment = std.mem.indexOfScalar(u8, raw_with_comment, '#') orelse raw_with_comment.len;
        const raw = raw_with_comment[0..comment];
        const content = trim(raw);
        if (content.len == 0) continue;
        var indent: usize = 0;
        while (indent < raw.len and raw[indent] == ' ') indent += 1;
        if (indent % 2 != 0) return recipeError(path, line_number, "indentation must use pairs of spaces");

        if (std.mem.startsWith(u8, content, "- ")) {
            const value = scalar(content[2..]);
            if (indent == 2 and std.mem.eql(u8, section, "extends")) try recipe.extends.append(value)
            else if (indent == 4 and std.mem.eql(u8, platform, platformName())) {
                if (std.mem.eql(u8, section, "executables")) try recipe.executables.append(value)
                else if (std.mem.eql(u8, section, "search")) try recipe.search.append(value)
                else return recipeError(path, line_number, "lists are allowed only in extends, executables, and search");
            } else if (indent == 2 and std.mem.eql(u8, section, "conditions")) {
                if (!std.mem.startsWith(u8, value, "when:")) return recipeError(path, line_number, "a condition item must begin with '- when:'");
                const expression = scalar(value[5..]);
                if (!validateCondition(expression)) return recipeError(path, line_number, "invalid condition; use platform == NAME, env.NAME, or env.NAME == VALUE");
                condition = expression;
                operation = "";
            }
            continue;
        }

        const colon = std.mem.indexOfScalar(u8, content, ':') orelse return recipeError(path, line_number, "expected key: value");
        const key = trim(content[0..colon]);
        const value = scalar(content[colon + 1 ..]);
        if (indent == 0) {
            section = key;
            platform = "";
            operation = "";
            condition = null;
            if (std.mem.eql(u8, key, "schema")) {
                if (!std.mem.eql(u8, value, "1")) return recipeError(path, line_number, "unsupported schema; expected 1");
                schema_seen = true;
            } else if (std.mem.eql(u8, key, "name")) recipe.name = value
            else if (std.mem.eql(u8, key, "python_requires")) {
                if (!validatePythonRequirement(value)) return recipeError(path, line_number, "invalid python_requires; use comma-separated comparisons such as >=3.11,<3.14");
                recipe.python_requires = value;
            }
            else if (std.mem.eql(u8, key, "executable_env")) {
                if (!validEnvName(value)) return recipeError(path, line_number, "executable_env must be an environment variable name");
                recipe.executable_env = value;
            } else if (!std.mem.eql(u8, key, "extends") and !std.mem.eql(u8, key, "executables") and
                !std.mem.eql(u8, key, "search") and !std.mem.eql(u8, key, "environment") and !std.mem.eql(u8, key, "conditions"))
                return recipeError(path, line_number, "unknown top-level key");
        } else if (indent == 2) {
            if (std.mem.eql(u8, section, "environment")) operation = key
            else if (std.mem.eql(u8, section, "executables") or std.mem.eql(u8, section, "search")) {
                if (!std.mem.eql(u8, key, "windows") and !std.mem.eql(u8, key, "macos") and !std.mem.eql(u8, key, "linux"))
                    return recipeError(path, line_number, "platform must be windows, macos, or linux");
                platform = key;
            }
            else if (!std.mem.eql(u8, section, "conditions")) return recipeError(path, line_number, "unexpected nested mapping");
        } else if ((indent == 4 and std.mem.eql(u8, section, "environment")) or
            (indent == 4 and std.mem.eql(u8, section, "conditions") and (std.mem.eql(u8, key, "set") or std.mem.eql(u8, key, "prepend") or std.mem.eql(u8, key, "append")))) {
            if (std.mem.eql(u8, section, "conditions")) operation = key else try appendEdit(&recipe, operation, key, value, null, path, line_number);
        } else if (indent == 6 and std.mem.eql(u8, section, "conditions")) {
            if (condition == null) return recipeError(path, line_number, "conditional edit has no when clause");
            try appendEdit(&recipe, operation, key, value, condition, path, line_number);
        } else return recipeError(path, line_number, "unsupported indentation or structure");
    }
    if (!schema_seen) return recipeError(path, 1, "missing required schema: 1");
    if (recipe.name.len == 0) return recipeError(path, 1, "missing required name");
    return recipe;
}

fn appendEdit(recipe: *Recipe, operation: []const u8, name: []const u8, value: []const u8, condition: ?[]const u8, path: []const u8, line: usize) ParseError!void {
    const kind: EditKind = if (std.mem.eql(u8, operation, "set")) .set else if (std.mem.eql(u8, operation, "prepend")) .prepend else if (std.mem.eql(u8, operation, "append")) .append else return recipeError(path, line, "environment operation must be set, prepend, or append");
    if (!validEnvName(name)) return recipeError(path, line, "invalid environment variable name");
    try recipe.edits.append(.{ .kind = kind, .name = name, .value = value, .condition = condition });
}

fn conditionMatches(expression: ?[]const u8) bool {
    const value = expression orelse return true;
    if (std.mem.eql(u8, value, "always")) return true;
    if (std.mem.startsWith(u8, value, "platform == ")) return std.mem.eql(u8, trim(value[12..]), platformName());
    const rest = value[4..];
    if (std.mem.indexOf(u8, rest, " == ")) |at| {
        const actual = std.posix.getenv(trim(rest[0..at])) orelse return false;
        return std.mem.eql(u8, actual, trim(rest[at + 4 ..]));
    }
    return std.posix.getenv(trim(rest)) != null;
}

fn configRoot(allocator: Allocator) ![]const u8 {
    if (std.posix.getenv("MISAPP_CONFIG_HOME")) |value| return allocator.dupe(u8, value);
    const home = std.posix.getenv("HOME") orelse ".";
    return switch (@import("builtin").os.tag) {
        .windows => std.fs.path.join(allocator, &.{ std.posix.getenv("APPDATA") orelse home, "misapp" }),
        .macos => std.fs.path.join(allocator, &.{ home, "Library", "Application Support", "misapp" }),
        else => if (std.posix.getenv("XDG_CONFIG_HOME")) |xdg| std.fs.path.join(allocator, &.{ xdg, "misapp" }) else std.fs.path.join(allocator, &.{ home, ".config", "misapp" }),
    };
}

fn resolveRecipeRoot(allocator: Allocator, configured: []const u8, launcher: []const u8, application: []const u8) ![]const u8 {
    const filename = try std.fmt.allocPrint(allocator, "{s}.yml", .{application});
    const configured_recipe = try std.fs.path.join(allocator, &.{ configured, "applications", filename });
    if (std.fs.cwd().access(configured_recipe, .{})) |_| return configured else |_| {}
    const scripts = std.fs.path.dirname(launcher) orelse ".";
    const prefix = std.fs.path.dirname(scripts) orelse ".";
    if (@import("builtin").os.tag == .windows) {
        const root = try std.fs.path.join(allocator, &.{ prefix, "Lib", "site-packages", "miskeyed" });
        const recipe = try std.fs.path.join(allocator, &.{ root, "applications", filename });
        if (std.fs.cwd().access(recipe, .{})) |_| return root else |_| {}
    } else {
        const library = try std.fs.path.join(allocator, &.{ prefix, "lib" });
        var directory = std.fs.cwd().openDir(library, .{ .iterate = true }) catch return error.FileNotFound;
        defer directory.close();
        var entries = directory.iterate();
        while (try entries.next()) |entry| if (entry.kind == .directory and std.mem.startsWith(u8, entry.name, "python")) {
            const root = try std.fs.path.join(allocator, &.{ library, entry.name, "site-packages", "miskeyed" });
            const recipe = try std.fs.path.join(allocator, &.{ root, "applications", filename });
            if (std.fs.cwd().access(recipe, .{})) |_| return root else |_| {}
        };
    }
    std.debug.print("misapp: no configured or packaged recipe for '{s}'\n", .{application});
    return error.FileNotFound;
}

fn loadChain(allocator: Allocator, root: []const u8, application: []const u8, stack: *std.ArrayList([]const u8), output: *std.ArrayList(Recipe)) !void {
    for (stack.items) |item| if (std.mem.eql(u8, item, application)) { std.debug.print("misapp: recipe chain contains a cycle at '{s}'\n", .{application}); return error.InvalidRecipe; };
    try stack.append(application);
    defer _ = stack.pop();
    const path = try std.fs.path.join(allocator, &.{ root, "applications", try std.fmt.allocPrint(allocator, "{s}.yml", .{application}) });
    const contents = std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024) catch { std.debug.print("misapp: recipe not found: {s}\n", .{path}); return error.InvalidRecipe; };
    const recipe = try parseRecipe(allocator, path, contents);
    for (recipe.extends.items) |parent| try loadChain(allocator, root, parent, stack, output);
    try output.append(recipe);
}

fn pythonEnvironmentRoot(allocator: Allocator, site: []const u8) ![]const u8 {
    var candidate = site;
    var depth: usize = 0;
    while (depth < 6) : (depth += 1) {
        const marker = try std.fs.path.join(allocator, &.{ candidate, "pyvenv.cfg" });
        if (std.fs.cwd().access(marker, .{})) |_| return allocator.dupe(u8, candidate) else |_| {}
        candidate = std.fs.path.dirname(candidate) orelse break;
    }
    // A wheel scripts directory and site-packages share the environment prefix. Keep a
    // deterministic fallback for environments which omit pyvenv.cfg.
    candidate = site;
    const levels: usize = if (@import("builtin").os.tag == .windows) 2 else 3;
    depth = 0;
    while (depth < levels) : (depth += 1) candidate = std.fs.path.dirname(candidate) orelse return allocator.dupe(u8, site);
    return allocator.dupe(u8, candidate);
}

fn pythonExecutable(allocator: Allocator, environment_root: []const u8) ![]const u8 {
    return if (@import("builtin").os.tag == .windows)
        std.fs.path.join(allocator, &.{ environment_root, "Scripts", "python.exe" })
    else
        std.fs.path.join(allocator, &.{ environment_root, "bin", "python" });
}

fn managedPythonVersion(allocator: Allocator, environment_root: []const u8) !PythonVersion {
    const marker = try std.fs.path.join(allocator, &.{ environment_root, "pyvenv.cfg" });
    const contents = std.fs.cwd().readFileAlloc(allocator, marker, 64 * 1024) catch {
        std.debug.print("misapp: managed Python environment has no readable pyvenv.cfg: {s}\n", .{marker});
        return error.InvalidPythonEnvironment;
    };
    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |line| {
        const equals = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = trim(line[0..equals]);
        if (!std.mem.eql(u8, key, "version") and !std.mem.eql(u8, key, "version_info")) continue;
        const raw_version = trim(line[equals + 1 ..]);
        // Some virtual-environment writers include a prerelease suffix. Compatibility is
        // intentionally gated on the numeric Python ABI portion only.
        var end: usize = 0;
        while (end < raw_version.len and (std.ascii.isDigit(raw_version[end]) or raw_version[end] == '.')) end += 1;
        while (end > 0 and raw_version[end - 1] == '.') end -= 1;
        return parsePythonVersion(raw_version[0..end]) orelse error.InvalidPythonEnvironment;
    }
    std.debug.print("misapp: pyvenv.cfg does not declare version or version_info: {s}\n", .{marker});
    return error.InvalidPythonEnvironment;
}

fn enforcePythonRequirements(allocator: Allocator, recipes: []const Recipe, environment_root: []const u8) !void {
    var required = false;
    for (recipes) |recipe| {
        if (recipe.python_requires.len != 0) {
            required = true;
            break;
        }
    }
    if (!required) return;
    const version = try managedPythonVersion(allocator, environment_root);
    for (recipes) |recipe| {
        if (recipe.python_requires.len != 0 and !pythonRequirementMatches(version, recipe.python_requires)) {
            std.debug.print(
                "misapp: managed Python {d}.{d}.{d} does not satisfy '{s}' required by '{s}'\n",
                .{ version.major, version.minor, version.patch, recipe.python_requires, recipe.name },
            );
            return error.IncompatiblePython;
        }
    }
}

fn expand(allocator: Allocator, input: []const u8, site: []const u8, python_env: []const u8, python_executable: []const u8) ![]const u8 {
    var result = try allocator.dupe(u8, input);
    const values = [_][2][]const u8{
        .{ "${site_packages}", site }, .{ "${python_env}", python_env },
        .{ "${python_executable}", python_executable }, .{ "${home}", std.posix.getenv("HOME") orelse "" },
        .{ "${program_files}", std.posix.getenv("ProgramFiles") orelse "" },
    };
    for (values) |pair| result = try std.mem.replaceOwned(u8, allocator, result, pair[0], pair[1]);
    return result;
}

fn pathSeparator() u8 { return if (@import("builtin").os.tag == .windows) ';' else ':'; }

fn lessThanString(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.order(u8, left, right) == .lt;
}

fn findExecutable(allocator: Allocator, recipes: []const Recipe, site: []const u8, python_env: []const u8, python_executable: []const u8) ![]const u8 {
    var index = recipes.len;
    while (index > 0) {
        index -= 1;
        const recipe = recipes[index];
        if (recipe.executable_env.len != 0) if (std.posix.getenv(recipe.executable_env)) |path| return allocator.dupe(u8, path);
        const path_value = std.posix.getenv("PATH") orelse "";
        for (recipe.executables.items) |name| {
            var paths = std.mem.splitScalar(u8, path_value, pathSeparator());
            while (paths.next()) |directory| {
                const candidate = try std.fs.path.join(allocator, &.{ directory, name });
                std.fs.cwd().access(candidate, .{}) catch continue;
                return candidate;
            }
        }
        for (recipe.search.items) |configured| {
            const candidate = try expand(allocator, configured, site, python_env, python_executable);
            std.fs.cwd().access(candidate, .{}) catch continue;
            return candidate;
        }
    }
    return error.FileNotFound;
}

fn usage() void {
    std.debug.print(
        "Usage: misapp APPLICATION [-- APPLICATION_ARGUMENTS...]\n" ++
            "       misapp validate APPLICATION\n" ++
            "       misapp inspect APPLICATION\n" ++
            "       misapp get APPLICATION VARIABLE\n" ++
            "       misapp help APPLICATION\n" ++
            "       misapp config-path APPLICATION\n",
        .{},
    );
}

fn userRecipePath(allocator: Allocator, configured_root: []const u8, application: []const u8) ![]const u8 {
    const filename = try std.fmt.allocPrint(allocator, "{s}.yml", .{application});
    return std.fs.path.join(allocator, &.{ configured_root, "applications", filename });
}

fn printApplicationHelp(writer: anytype, allocator: Allocator, application: []const u8, configured_root: []const u8, recipes: []const Recipe) !void {
    try writer.print("Application: {s}\nUser recipe: {s}\nRecipe chain:", .{ application, try userRecipePath(allocator, configured_root, application) });
    for (recipes) |recipe| try writer.print("\n  - {s}", .{recipe.name});
    try writer.writeAll("\n\nManaged Python requirements:\n");
    var has_python_requirement = false;
    for (recipes) |recipe| if (recipe.python_requires.len != 0) {
        has_python_requirement = true;
        try writer.print("  {s}: {s}\n", .{ recipe.name, recipe.python_requires });
    };
    if (!has_python_requirement) try writer.writeAll("  (none)\n");
    try writer.writeAll("\n\nAvailable input environment variables:\n");
    var inputs = std.StringHashMap(void).init(allocator);
    for (recipes) |recipe| {
        if (recipe.executable_env.len != 0) try inputs.put(recipe.executable_env, {});
        for (recipe.edits.items) |edit| if (edit.condition) |condition| if (std.mem.startsWith(u8, condition, "env.")) {
            const rest = condition[4..];
            const end = std.mem.indexOf(u8, rest, " == ") orelse rest.len;
            try inputs.put(trim(rest[0..end]), {});
        };
    }
    var input_names = std.ArrayList([]const u8).init(allocator);
    var input_iterator = inputs.keyIterator();
    while (input_iterator.next()) |name| try input_names.append(name.*);
    std.mem.sort([]const u8, input_names.items, {}, lessThanString);
    if (input_names.items.len == 0) try writer.writeAll("  (none)\n") else for (input_names.items) |name| try writer.print("  {s}\n", .{name});

    try writer.writeAll("\nChild environment variables configured by this recipe:\n");
    var outputs = std.StringHashMap(void).init(allocator);
    for (recipes) |recipe| for (recipe.edits.items) |edit| try outputs.put(edit.name, {});
    var output_names = std.ArrayList([]const u8).init(allocator);
    var output_iterator = outputs.keyIterator();
    while (output_iterator.next()) |name| try output_names.append(name.*);
    std.mem.sort([]const u8, output_names.items, {}, lessThanString);
    if (output_names.items.len == 0) try writer.writeAll("  (none)\n") else for (output_names.items) |name| try writer.print("  {s}\n", .{name});
    try writer.writeAll("\nRecipe substitutions:\n  ${site_packages}\n  ${python_env}\n  ${python_executable}\n  ${home}\n  ${program_files}\n\n");
    try writer.print("Use `misapp inspect {s}` for resolved values.\n", .{application});
    try writer.print("Use `misapp get {s} VARIABLE` for one machine-readable value.\n", .{application});
}

fn printValue(writer: anytype, key: []const u8, application: []const u8, root: []const u8, site: []const u8, python_env: []const u8, python_executable: []const u8, executable: []const u8, recipes: []const Recipe, environment: *const std.process.EnvMap) !bool {
    if (std.mem.eql(u8, key, "application")) try writer.print("{s}\n", .{application})
    else if (std.mem.eql(u8, key, "executable")) try writer.print("{s}\n", .{executable})
    else if (std.mem.eql(u8, key, "site_packages")) try writer.print("{s}\n", .{site})
    else if (std.mem.eql(u8, key, "python_env")) try writer.print("{s}\n", .{python_env})
    else if (std.mem.eql(u8, key, "python_executable")) try writer.print("{s}\n", .{python_executable})
    else if (std.mem.eql(u8, key, "recipe_root")) try writer.print("{s}\n", .{root})
    else if (std.mem.eql(u8, key, "recipe_count")) try writer.print("{d}\n", .{recipes.len})
    else if (std.mem.startsWith(u8, key, "environment.")) {
        const name = key[12..];
        if (!validEnvName(name)) return false;
        const value = environment.get(name) orelse return false;
        try writer.print("{s}\n", .{value});
    } else return false;
    return true;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const args = try std.process.argsAlloc(allocator);
    if (args.len < 2) { usage(); return error.InvalidArguments; }
    if (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h")) { usage(); return; }
    const validating = std.mem.eql(u8, args[1], "validate");
    const inspecting = std.mem.eql(u8, args[1], "inspect");
    const getting = std.mem.eql(u8, args[1], "get");
    const help_command = std.mem.eql(u8, args[1], "help");
    const locating_config = std.mem.eql(u8, args[1], "config-path");
    const has_command = validating or inspecting or getting or help_command or locating_config;
    const application_index: usize = if (has_command) 2 else 1;
    if (args.len <= application_index) { usage(); return error.InvalidArguments; }
    const inline_help = !has_command and args.len == 3 and (std.mem.eql(u8, args[2], "--help") or std.mem.eql(u8, args[2], "-h"));
    const helping = help_command or inline_help;
    const application = args[application_index];
    if (!validRecipeId(application)) {
        std.debug.print("misapp: application must contain only letters, numbers, '-' or '_'\n", .{});
        return error.InvalidArguments;
    }
    const configured_root = try configRoot(allocator);
    const stdout = std.io.getStdOut().writer();
    if (locating_config) {
        if (args.len != application_index + 1) { usage(); return error.InvalidArguments; }
        try stdout.print("{s}\n", .{try userRecipePath(allocator, configured_root, application)});
        return;
    }
    const launcher = try std.fs.selfExePathAlloc(allocator);
    const root = try resolveRecipeRoot(allocator, configured_root, launcher, application);
    var stack = std.ArrayList([]const u8).init(allocator);
    var recipes = std.ArrayList(Recipe).init(allocator);
    try loadChain(allocator, root, application, &stack, &recipes);
    var has_discovery = false;
    for (recipes.items) |recipe| if (recipe.executable_env.len != 0 or recipe.executables.items.len != 0 or recipe.search.items.len != 0) {
        has_discovery = true;
        break;
    };
    if (!has_discovery) {
        std.debug.print("misapp: recipe chain has no executable discovery rule\n", .{});
        return error.InvalidRecipe;
    }
    if (helping) {
        if (!inline_help and args.len != application_index + 1) { usage(); return error.InvalidArguments; }
        try printApplicationHelp(stdout, allocator, application, configured_root, recipes.items);
        return;
    }
    if (validating) {
        if (args.len != application_index + 1) { usage(); return error.InvalidArguments; }
        std.debug.print("valid: {s} ({d} recipe{s})\n", .{ args[application_index], recipes.items.len, if (recipes.items.len == 1) "" else "s" });
        return;
    }
    var environment = try std.process.getEnvMap(allocator);
    const site = std.posix.getenv("MISAPP_SITE_PACKAGES") orelse if (std.mem.endsWith(u8, root, "miskeyed")) std.fs.path.dirname(root) orelse root else root;
    const python_env = try pythonEnvironmentRoot(allocator, site);
    const python_executable = try pythonExecutable(allocator, python_env);
    try enforcePythonRequirements(allocator, recipes.items, python_env);
    for (recipes.items) |recipe| for (recipe.edits.items) |edit| if (conditionMatches(edit.condition)) {
        const value = try expand(allocator, edit.value, site, python_env, python_executable);
        const inherited = environment.get(edit.name) orelse "";
        const composed = if (edit.kind == .set or inherited.len == 0) value else if (edit.kind == .prepend)
            try std.fmt.allocPrint(allocator, "{s}{c}{s}", .{ value, pathSeparator(), inherited })
        else try std.fmt.allocPrint(allocator, "{s}{c}{s}", .{ inherited, pathSeparator(), value });
        try environment.put(edit.name, composed);
    };
    const executable = findExecutable(allocator, recipes.items, site, python_env, python_executable) catch { std.debug.print("misapp: application executable was not found\n", .{}); return error.FileNotFound; };
    if (inspecting) {
        if (args.len != application_index + 1) { usage(); return error.InvalidArguments; }
        try stdout.print("application={s}\nexecutable={s}\nsite_packages={s}\npython_env={s}\npython_executable={s}\nrecipe_root={s}\nrecipe_count={d}\n", .{ args[application_index], executable, site, python_env, python_executable, root, recipes.items.len });
        var names = std.StringHashMap(void).init(allocator);
        for (recipes.items) |recipe| for (recipe.edits.items) |edit| try names.put(edit.name, {});
        var sorted_names = std.ArrayList([]const u8).init(allocator);
        var iterator = names.keyIterator();
        while (iterator.next()) |name| try sorted_names.append(name.*);
        std.mem.sort([]const u8, sorted_names.items, {}, lessThanString);
        for (sorted_names.items) |name| if (environment.get(name)) |value| try stdout.print("environment.{s}={s}\n", .{ name, value });
        return;
    }
    if (getting) {
        if (args.len != application_index + 2) { usage(); return error.InvalidArguments; }
        if (!try printValue(stdout, args[application_index + 1], args[application_index], root, site, python_env, python_executable, executable, recipes.items, &environment)) {
            std.debug.print("misapp: unknown or unavailable variable '{s}'\n", .{args[application_index + 1]});
            return error.InvalidArguments;
        }
        return;
    }
    var child_args = std.ArrayList([]const u8).init(allocator);
    try child_args.append(executable);
    var forward = false;
    for (args[application_index + 1 ..]) |arg| { if (!forward and std.mem.eql(u8, arg, "--")) { forward = true; continue; } if (!forward) { std.debug.print("misapp: application arguments must follow --\n", .{}); return error.InvalidArguments; } try child_args.append(arg); }
    var child = std.process.Child.init(child_args.items, allocator);
    child.env_map = &environment;
    const term = try child.spawnAndWait();
    switch (term) { .Exited => |code| std.process.exit(code), else => std.process.exit(2) }
}

test "condition syntax validator" {
    try std.testing.expect(validateCondition("platform == windows"));
    try std.testing.expect(validateCondition("env.STUDIO"));
    try std.testing.expect(validateCondition("env.STUDIO == film"));
    try std.testing.expect(!validateCondition("run arbitrary code"));
}

test "managed Python requirement validator" {
    try std.testing.expect(validatePythonRequirement(">=3.11,<3.14"));
    try std.testing.expect(!validatePythonRequirement("~=3.12"));
    try std.testing.expect(pythonRequirementMatches(.{ .major = 3, .minor = 12, .patch = 3 }, ">=3.11,<3.14"));
    try std.testing.expect(!pythonRequirementMatches(.{ .major = 3, .minor = 10, .patch = 9 }, ">=3.11,<3.14"));
}
