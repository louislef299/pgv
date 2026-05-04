const std = @import("std");
const pg = @import("pg");

pub const log = std.log.scoped(.init);
const models = @import("../lib/models.zig");

const Flags = @import("./Flags.zig");

const table =
    \\CREATE TABLE IF NOT EXISTS items (
    \\ id bigserial PRIMARY KEY,
    \\ sha TEXT UNIQUE,
    \\ content text,
    \\ embedding vector({d}),
    \\ author_name TEXT,
    \\ author_email TEXT,
    \\ commit_date TIMESTAMPTZ,
    \\ files_changed INT,
    \\ insertions INT,
    \\ deletions INT);
;

pub fn run(_: std.mem.Allocator, pool: *pg.Pool, f: Flags) !void {
    _ = try pool.exec("CREATE EXTENSION IF NOT EXISTS vector;", .{});

    // DDL cannot use query parameters — build the SQL on the stack.
    var buf: [512]u8 = undefined;
    const create_table = try std.fmt.bufPrint(&buf, table, .{f.model.dims});
    _ = try pool.exec(create_table, .{});

    std.debug.print("initialized for model '{s}' ({d} dims)\n", .{
        f.model.name, f.model.dims,
    });
}
