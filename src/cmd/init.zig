const std = @import("std");
const pg = @import("pg");
const flags = @import("flags.zig");
const lib = @import("../lib/log.zig");
const models = @import("../lib/models.zig");

const root = @import("../main.zig");

// InitFlags defines the supported CLI flags for the init command.
// Each field name corresponds to a --flag name and its default value
// is used when the flag is not provided by the caller.
const InitFlags = struct {
    model: []const u8 = "nomic-embed-text",
};

pub fn run(_: std.mem.Allocator, pool: *pg.Pool, args: []const []const u8) !void {
    var f = InitFlags{};
    flags.parseFlags(root.usage, &f, args);

    // Validate the model before running DDL.
    const model = models.find(f.model) orelse {
        lib.log.err("Unknown model '{s}'. Supported models:", .{f.model});
        for (models.ollama) |m| lib.log.err("  {s}", .{m.name});
        std.posix.exit(1);
    };

    _ = try pool.exec("CREATE EXTENSION IF NOT EXISTS vector;", .{});

    // DDL cannot use query parameters — build the SQL on the stack.
    var buf: [256]u8 = undefined;
    const create_table = try std.fmt.bufPrint(
        &buf,
        "CREATE TABLE IF NOT EXISTS items (id bigserial PRIMARY KEY, content text, embedding vector({d}));",
        .{model.dims},
    );
    _ = try pool.exec(create_table, .{});

    std.debug.print("initialized for model '{s}' ({d} dims)\n", .{
        model.name, model.dims,
    });
}
