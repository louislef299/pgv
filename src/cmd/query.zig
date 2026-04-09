const std = @import("std");
const pg = @import("pg");

pub const log = std.log.scoped(.query);
const runner = @import("../lib/runner.zig");
const pgvector = @import("../lib/pgvector.zig");
const Flags = @import("Flags.zig");

pub fn run(allocator: std.mem.Allocator, pool: *pg.Pool, f: Flags) !void {
    if (f.query.len == 0) {
        log.err("query text is required: ishi query \"your question here\"", .{});
        std.posix.exit(1);
    }

    std.debug.print("querying: \"{s}\"\n\n", .{f.query});

    // Embed the query text via the model runner.
    const embedding = try runner.getEmbedding(allocator, .{
        .model_name = f.model.name,
        .text = f.query,
        .runner = f.runner,
    });
    defer allocator.free(embedding);

    // Format as pgvector-compatible string.
    const vec_str = try pgvector.formatVector(allocator, embedding);
    defer allocator.free(vec_str);

    // Find the 3 most semantically similar items using cosine distance.
    var result = try pool.query(
        \\SELECT content, 1 - (embedding <=> $1::vector) AS similarity
        \\FROM items ORDER BY embedding <=> $1::vector LIMIT 3
    , .{vec_str});
    defer result.deinit();

    var rank: u8 = 1;
    while (try result.next()) |row| {
        const content = try row.get([]const u8, 0);
        const similarity = try row.get(f64, 1);
        std.debug.print("{d}. ({d:.4}) {s}\n", .{ rank, similarity, content });
        rank += 1;
    }

    if (rank == 1) {
        std.debug.print("no results found. have you run 'ishi seed' yet?\n", .{});
    }
}
