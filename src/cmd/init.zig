const std = @import("std");
const pg = @import("pg");
const lib = @import("../lib/log.zig");
const models = @import("../lib/models.zig");

const Flags = @import("./Flags.zig");

pub fn run(_: std.mem.Allocator, pool: *pg.Pool, f: Flags) !void {
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
