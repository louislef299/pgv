const std = @import("std");
const lg2 = @cImport(@cInclude("git2.h"));

// CommitInfo holds extracted Git commit data. Caller must call deinit() to
// free the allocator-owned string memory.
pub const CommitInfo = struct {
    sha: [40]u8,
    author_name: []const u8,
    author_email: []const u8,
    author_date: i64,
    committer_name: []const u8,
    committer_email: []const u8,
    committer_date: i64,
    message: []const u8,
    diff_patch: []const u8, // full patch text
    files_changed: usize,
    insertions: usize,
    deletions: usize,

    allocator: std.mem.Allocator,

    pub fn deinit(self: *CommitInfo) void {
        self.allocator.free(self.author_name);
        self.allocator.free(self.author_email);
        self.allocator.free(self.committer_name);
        self.allocator.free(self.committer_email);
        self.allocator.free(self.message);
        self.allocator.free(self.diff_patch);
    }
};

/// Helper to convert a libgit2 error code into a Zig error.
fn check(code: c_int) !void {
    if (code < 0) {
        return error.Lg2Error;
    }
}

/// Copy a C string (nullable) into a Zig-owned slice.
fn dupeString(allocator: std.mem.Allocator, c_str: ?[*:0]const u8) ![]const u8 {
    const s = c_str orelse return allocator.dupe(u8, "");
    return allocator.dupe(u8, std.mem.span(s));
}

pub fn readHeadCommit(allocator: std.mem.Allocator, repo_path: [*:0]const u8) !CommitInfo {
    // 4a. https://github.com/libgit2/libgit2?tab=readme-ov-file#initialization
    _ = lg2.git_libgit2_init();
    defer _ = lg2.git_libgit2_shutdown();

    // 4b. https://libgit2.org/docs/reference/main/repository/git_repository_open.html
    var repo: ?*lg2.git_repository = null;
    try check(lg2.git_repository_open(&repo, repo_path));
    defer lg2.git_repository_free(repo);

    // 4c. https://libgit2.org/docs/reference/main/oid/git_oid_fromstr.html
    var oid: lg2.git_oid = undefined;
    try check(lg2.git_reference_name_to_id(&oid, repo, "HEAD"));

    // 4d. https://libgit2.org/docs/reference/main/commit/git_commit_lookup.html
    var commit: ?*lg2.git_commit = null;
    try check(lg2.git_commit_lookup(&commit, repo, &oid));
    defer lg2.git_commit_free(commit);

    // 4e. Extract commit metadata
    // https://libgit2.org/docs/reference/main/oid/git_oid_tostr_s.html
    var sha: [40]u8 = undefined;
    const sha_str = lg2.git_oid_tostr_s(&oid);
    if (sha_str) |s| {
        @memcpy(&sha, s[0..40]);
    } else {
        @memset(&sha, '0');
    }

    // https://libgit2.org/docs/reference/main/commit/git_commit_author.html
    const author = lg2.git_commit_author(commit);
    const author_name = try dupeString(allocator, if (author) |a| a.*.name else null);
    errdefer allocator.free(author_name);

    const author_email = try dupeString(allocator, if (author) |a| a.*.email else null);
    errdefer allocator.free(author_email);

    const author_date: i64 = if (author) |a| a.*.when.time else 0;

    // https://libgit2.org/docs/reference/main/commit/git_commit_committer.html
    const committer = lg2.git_commit_committer(commit);
    const committer_name = try dupeString(allocator, if (committer) |c| c.*.name else null);
    errdefer allocator.free(committer_name);

    const committer_email = try dupeString(allocator, if (committer) |c| c.*.email else null);
    errdefer allocator.free(committer_email);

    const committer_date: i64 = if (committer) |c| c.*.when.time else 0;

    // https://libgit2.org/docs/reference/main/commit/git_commit_message.html
    const message = try dupeString(allocator, lg2.git_commit_message(commit));
    errdefer allocator.free(message);

    // 4f. https://libgit2.org/docs/reference/main/commit/git_commit_tree.html
    var tree: ?*lg2.git_tree = null;
    try check(lg2.git_commit_tree(&tree, commit));
    defer lg2.git_tree_free(tree);

    // 4g. https://libgit2.org/docs/reference/main/commit/git_commit_parentcount.html
    // https://libgit2.org/docs/reference/main/commit/git_commit_parent.html
    var parent_tree: ?*lg2.git_tree = null;
    if (lg2.git_commit_parentcount(commit) > 0) {
        var parent: ?*lg2.git_commit = null;
        try check(lg2.git_commit_parent(&parent, commit, 0));
        defer lg2.git_commit_free(parent);
        try check(lg2.git_commit_tree(&parent_tree, parent));
    }
    defer if (parent_tree) |pt| lg2.git_tree_free(pt);

    // 4h. https://libgit2.org/docs/reference/main/diff/git_diff_tree_to_tree.html
    var diff: ?*lg2.git_diff = null;
    try check(lg2.git_diff_tree_to_tree(&diff, repo, parent_tree, tree, null));
    defer lg2.git_diff_free(diff);

    // 4i. https://libgit2.org/docs/reference/main/diff/git_diff_get_stats.html
    var stats: ?*lg2.git_diff_stats = null;
    try check(lg2.git_diff_get_stats(&stats, diff));
    defer lg2.git_diff_stats_free(stats);

    // https://libgit2.org/docs/reference/main/diff/git_diff_stats_files_changed.html
    const files_changed = lg2.git_diff_stats_files_changed(stats);
    // https://libgit2.org/docs/reference/main/diff/git_diff_stats_insertions.html
    const insertions = lg2.git_diff_stats_insertions(stats);
    // https://libgit2.org/docs/reference/main/diff/git_diff_stats_deletions.html
    const deletions = lg2.git_diff_stats_deletions(stats);

    // 4j. https://libgit2.org/docs/reference/main/diff/git_diff_to_buf.html
    var diff_buf: lg2.git_buf = .{ .ptr = null, .reserved = 0, .size = 0 };
    try check(lg2.git_diff_to_buf(&diff_buf, diff, lg2.GIT_DIFF_FORMAT_PATCH));
    // https://libgit2.org/docs/reference/main/buffer/git_buf_dispose.html
    defer lg2.git_buf_dispose(&diff_buf);

    const diff_patch = if (diff_buf.ptr) |ptr|
        try allocator.dupe(u8, ptr[0..diff_buf.size])
    else
        try allocator.dupe(u8, "");
    errdefer allocator.free(diff_patch);

    // 4k. Populate and return CommitInfo
    return CommitInfo{
        .sha = sha,
        .author_name = author_name,
        .author_email = author_email,
        .author_date = author_date,
        .committer_name = committer_name,
        .committer_email = committer_email,
        .committer_date = committer_date,
        .message = message,
        .diff_patch = diff_patch,
        .files_changed = files_changed,
        .insertions = insertions,
        .deletions = deletions,
        .allocator = allocator,
    };
}

test "readHeadCommit returns valid data for current repo" {
    const allocator = std.testing.allocator;
    var info = try readHeadCommit(allocator, ".");
    defer info.deinit();

    // SHA should be 40 hex characters
    for (info.sha) |c| {
        try std.testing.expect(std.ascii.isHex(c));
    }

    // Author and committer should be non-empty on any real repo
    try std.testing.expect(info.author_name.len > 0);
    try std.testing.expect(info.author_email.len > 0);
    try std.testing.expect(info.committer_name.len > 0);
    try std.testing.expect(info.committer_email.len > 0);

    // Timestamps should be positive (post-epoch)
    try std.testing.expect(info.author_date > 0);
    try std.testing.expect(info.committer_date > 0);

    // Message should be non-empty
    try std.testing.expect(info.message.len > 0);

    std.debug.print("\n--- readHeadCommit smoke test ---\n", .{});
    std.debug.print("sha:            {s}\n", .{&info.sha});
    std.debug.print("author:         {s} <{s}>\n", .{ info.author_name, info.author_email });
    std.debug.print("author_date:    {d}\n", .{info.author_date});
    std.debug.print("committer:      {s} <{s}>\n", .{ info.committer_name, info.committer_email });
    std.debug.print("committer_date: {d}\n", .{info.committer_date});
    std.debug.print("message:        {s}\n", .{info.message[0..@min(info.message.len, 80)]});
    std.debug.print("files_changed:  {d}\n", .{info.files_changed});
    std.debug.print("insertions:     {d}\n", .{info.insertions});
    std.debug.print("deletions:      {d}\n", .{info.deletions});
    std.debug.print("diff_patch len: {d} bytes\n", .{info.diff_patch.len});
    std.debug.print("--- end ---\n", .{});
}
