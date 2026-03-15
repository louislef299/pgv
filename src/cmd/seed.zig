const std = @import("std");
const pg = @import("pg");

const log = @import("../lib/log.zig").log;
const git = @import("../lib/git.zig");
const ollama = @import("../lib/ollama.zig");
const pgvector = @import("../lib/pgvector.zig");
const Flags = @import("Flags.zig");

const SeedEntry = struct {
    id: []const u8,
    text: []const u8,
};

pub fn run(allocator: std.mem.Allocator, pool: *pg.Pool, f: Flags) !void {
    if (f.git) {
        log.debug("seeding from git...", .{});
        try seedFromGit(allocator, pool, f);
    } else {
        log.debug("seeding from json...", .{});
        try seedFromJson(allocator, pool, f);
    }
}

fn seedFromGit(allocator: std.mem.Allocator, pool: *pg.Pool, f: Flags) !void {
    std.debug.print("Walking up to {d} commits...\n", .{f.limit});

    const commits = git.walkCommits(allocator, ".", f.limit) catch |err| {
        log.err("Failed to walk git history: {}", .{err});
        std.posix.exit(1);
    };
    defer {
        for (commits) |*ci| {
            @constCast(ci).deinit();
        }
        allocator.free(commits);
    }

    std.debug.print("Found {d} commits, seeding...\n", .{commits.len});

    for (commits) |ci| {
        const sha_str = &ci.sha;
        std.debug.print("embedding {s}...\n", .{sha_str});

        // Combine commit message and diff patch for embedding.
        // Truncate to 8192 bytes to stay within the embedding model's context window.
        const max_embed_len: usize = 8192;
        const patch = ci.diff_patch[0..@min(ci.diff_patch.len, max_embed_len -| ci.message.len -| 2)];
        const content = try std.fmt.allocPrint(allocator, "{s}\n\n{s}", .{ ci.message, patch });
        defer allocator.free(content);

        const embedding = ollama.getEmbedding(allocator, f.model.name, content) catch |err| {
            log.warn("skipping {s}: {}", .{ sha_str, err });
            continue;
        };
        defer allocator.free(embedding);

        const vec_str = try pgvector.formatVector(allocator, embedding);
        defer allocator.free(vec_str);

        _ = try pool.exec(
            "INSERT INTO items (content, embedding) VALUES ($1, $2::vector)",
            .{ content, vec_str },
        );
        std.debug.print("  seeded {s}\n", .{sha_str});
    }
}

fn seedFromJson(allocator: std.mem.Allocator, pool: *pg.Pool, f: Flags) !void {
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
