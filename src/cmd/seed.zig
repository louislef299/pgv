const std = @import("std");
const pg = @import("pg");
const flags = @import("flags.zig");
const lib = @import("../lib/log.zig");
const models = @import("../lib/models.zig");

const root = @import("../main.zig");

const SeedEntry = struct {
    id: []const u8,
    text: []const u8,
};

const OllamaResponse = struct {
    embedding: []f64,
};

const SeedFlags = struct {
    model: []const u8 = "nomic-embed-text",
    path: []const u8 = "./seed.json",
};

pub fn run(allocator: std.mem.Allocator, pool: *pg.Pool, args: []const []const u8) !void {
    var f = SeedFlags{};
    flags.parseFlags(root.usage, &f, args);

    _ = models.find(f.model) orelse {
        lib.log.err("Unknown model '{s}'. Supported models:", .{f.model});
        for (models.ollama) |m| lib.log.err("  {s}", .{m.name});
        std.posix.exit(1);
    };

    // Read the seed file from disk.
    const seed_data = std.fs.cwd().readFileAlloc(allocator, f.path, 1024 * 1024) catch |err| {
        lib.log.err("Failed to read '{s}': {}", .{ f.path, err });
        std.posix.exit(1);
    };
    defer allocator.free(seed_data);

    const parsed = try std.json.parseFromSlice([]SeedEntry, allocator, seed_data, .{
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    for (parsed.value) |entry| {
        std.debug.print("embedding '{s}'...\n", .{entry.id});

        // Call Ollama to generate the embedding vector.
        const embedding = try getEmbedding(allocator, f.model, entry.text);
        defer allocator.free(embedding);

        // pgvector accepts text like '[0.1,0.2,...]' cast to vector.
        _ = try pool.exec(
            "INSERT INTO items (content, embedding) VALUES ($1, $2::vector)",
            .{ entry.text, embedding },
        );

        std.debug.print("  seeded '{s}'\n", .{entry.id});
    }
}

/// Calls the Ollama /api/embeddings endpoint and returns the embedding
/// formatted as a pgvector-compatible text string "[0.1,0.2,...]".
fn getEmbedding(allocator: std.mem.Allocator, model_name: []const u8, text: []const u8) ![]u8 {
    // Build the JSON request body for Ollama.
    const body = try std.fmt.allocPrint(
        allocator,
        \\{{"model":"{s}","prompt":"{s}"}}
    ,
        .{ model_name, text },
    );
    defer allocator.free(body);

    // Shell out to curl to call the Ollama embedding API.
    // TODO: replace with zul.http.Client(https://www.goblgobl.com/zul/http/client/)
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{
            "curl",                                  "-s",
            "-X",                                    "POST",
            "-H",                                    "Content-Type: application/json",
            "-d",                                    body,
            "http://localhost:11434/api/embeddings",
        },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.Exited != 0) {
        lib.log.err("curl failed: {s}", .{result.stderr});
        return error.OllamaRequestFailed;
    }

    // Parse the JSON response to extract the embedding array.
    const resp = try std.json.parseFromSlice(OllamaResponse, allocator, result.stdout, .{
        .allocate = .alloc_always,
    });
    defer resp.deinit();

    // Format as a pgvector-compatible text string: "[0.1,0.2,...]"
    var vec: std.ArrayList(u8) = .empty;
    errdefer vec.deinit(allocator);
    try vec.append(allocator, '[');
    for (resp.value.embedding, 0..) |v, i| {
        if (i > 0) try vec.append(allocator, ',');
        try vec.writer(allocator).print("{d}", .{v});
    }
    try vec.append(allocator, ']');

    return try vec.toOwnedSlice(allocator);
}
