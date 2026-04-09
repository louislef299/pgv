const std = @import("std");
const pg = @import("pg");

const log = @import("../lib/log.zig").log;
const git = @import("../lib/git.zig");
const runner = @import("../lib/runner.zig");
const pgvector = @import("../lib/pgvector.zig");
const Flags = @import("Flags.zig");

const SeedEntry = struct {
    id: []const u8,
    text: []const u8,
};

pub fn run(allocator: std.mem.Allocator, pool: *pg.Pool, f: Flags) !void {
    if (f.jsonpath.len == 0) {
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
        // Truncate final content to ~1024 bytes to stay within llama.cpp's
        // default 512-token physical batch size (~4 bytes/token for nomic-embed-text).
        const max_embed_len: usize = 1024;

        // Metadata + message overhead is ~200-300 bytes, so cap the patch early.
        const patch = ci.diff_patch[0..@min(ci.diff_patch.len, max_embed_len)];
        const full_content = try ci.format(allocator, patch);
        defer allocator.free(full_content);

        const content = full_content[0..@min(full_content.len, max_embed_len)];
        std.debug.print("Git Embedding:\t{s}\n", .{content});

        const embedding = runner.getEmbedding(allocator, .{
            .model_name = f.model.name,
            .text = content,
            .runner = f.runner,
        }) catch |err| {
            log.warn("skipping {s}: {}", .{ sha_str, err });
            continue;
        };
        defer allocator.free(embedding);

        const vec_str = try pgvector.formatVector(allocator, embedding);
        defer allocator.free(vec_str);

        // pg.zig Timestamp expects microseconds; libgit2 gives seconds.
        const commit_date_us = ci.author_date * 1_000_000;
        _ = try pool.exec(
            "INSERT INTO items (sha, content, embedding, author_name, author_email, commit_date, files_changed, insertions, deletions) VALUES ($1, $2, $3::vector, $4, $5, $6, $7, $8, $9) ON CONFLICT (sha) DO NOTHING",
            .{ sha_str, content, vec_str, ci.author_name, ci.author_email, commit_date_us, ci.files_changed, ci.insertions, ci.deletions },
        );
        std.debug.print("  seeded {s}\n", .{sha_str});
    }
}

fn seedFromJson(allocator: std.mem.Allocator, pool: *pg.Pool, f: Flags) !void {
    // Read the seed file from disk.
    const seed_data = std.fs.cwd().readFileAlloc(
        allocator,
        f.jsonpath,
        1024 * 1024,
    ) catch |err| {
        log.err("Failed to read '{s}': {}", .{ f.jsonpath, err });
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

        // Call the model runner to generate the embedding vector.
        const embedding = try runner.getEmbedding(allocator, .{
            .model_name = f.model.name,
            .text = entry.text,
            .runner = f.runner,
        });
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
