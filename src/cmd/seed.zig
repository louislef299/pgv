const std = @import("std");
const pg = @import("pg");

const log = @import("../lib/log.zig").log;
const ollama = @import("../lib/ollama.zig");
const pgvector = @import("../lib/pgvector.zig");
const Flags = @import("Flags.zig");

const SeedEntry = struct {
    id: []const u8,
    text: []const u8,
};

pub fn run(allocator: std.mem.Allocator, pool: *pg.Pool, f: Flags) !void {
    // Read the seed file from disk.
    const seed_data = std.fs.cwd().readFileAlloc(
        allocator,
        f.path,
        1024 * 1024,
    ) catch |err| {
        log.err("Failed to read '{s}': {}", .{ f.path, err });
        std.posix.exit(1);
    };
    defer allocator.free(seed_data);

    const parsed = try std.json.parseFromSlice(
        []SeedEntry,
        allocator,
        seed_data,
        .{
            .allocate = .alloc_always,
        },
    );
    defer parsed.deinit();

    for (parsed.value) |entry| {
        std.debug.print("embedding '{s}'...\n", .{entry.id});

        // Call Ollama to generate the embedding vector.
        const embedding = try ollama.getEmbedding(allocator, f.model.name, entry.text);
        defer allocator.free(embedding);

        // Format as a pgvector-compatible text string: "[0.1,0.2,...]"
        const vec_str = try pgvector.formatVector(allocator, embedding);
        defer allocator.free(vec_str);

        _ = try pool.exec(
            "INSERT INTO items (content, embedding) VALUES ($1, $2::vector)",
            .{ entry.text, vec_str },
        );
        std.debug.print("  seeded '{s}'\n", .{entry.id});
    }
}
