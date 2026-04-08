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

    /// Formats commit metadata, message, and diff patch into a single
    /// string suitable for embedding.
    pub fn format(
        self: *const CommitInfo,
        allocator: std.mem.Allocator,
        patch: []const u8,
    ) ![]u8 {
        const epoch_secs = std.time.epoch.EpochSeconds{ .secs = @intCast(self.author_date) };
        const epoch_day = epoch_secs.getEpochDay();
        const year_day = epoch_day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();
        const day_secs = epoch_secs.getDaySeconds();

        const date_str = try std.fmt.allocPrint(allocator, "{d}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}", .{
            year_day.year,
            @intFromEnum(month_day.month),
            month_day.day_index + 1,
            day_secs.getHoursIntoDay(),
            day_secs.getMinutesIntoHour(),
            day_secs.getSecondsIntoMinute(),
        });
        defer allocator.free(date_str);

        // ci.sha, ci.author_name, ci.author_email, ci.author_date (formatted),
        // ci.files_changed, ci.insertions, ci.deletions
        const commitFmt =
            \\{s} {s} {s} {s}
            \\Files Changed: {d}
            \\Insertions: {d}
            \\Deletions: {d}
            \\
            \\{s}
            \\{s}
        ;

        return try std.fmt.allocPrint(
            allocator,
            commitFmt,
            .{
                self.sha,
                self.author_name,
                self.author_email,
                date_str,
                self.files_changed,
                self.insertions,
                self.deletions,

                self.message,
                patch,
            },
        );
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

/// Extract a CommitInfo from a resolved commit object and its OID.
/// The repo handle is needed for diffing. Caller owns the returned CommitInfo.
fn readCommit(allocator: std.mem.Allocator, repo: ?*lg2.git_repository, oid: *const lg2.git_oid, commit: ?*lg2.git_commit) !CommitInfo {
    var sha: [40]u8 = undefined;
    const sha_str = lg2.git_oid_tostr_s(oid);
    if (sha_str) |s| {
        @memcpy(&sha, s[0..40]);
    } else {
        @memset(&sha, '0');
    }

    const author = lg2.git_commit_author(commit);
    const author_name = try dupeString(allocator, if (author) |a| a.*.name else null);
    errdefer allocator.free(author_name);

    const author_email = try dupeString(allocator, if (author) |a| a.*.email else null);
    errdefer allocator.free(author_email);

    const author_date: i64 = if (author) |a| a.*.when.time else 0;

    const committer = lg2.git_commit_committer(commit);
    const committer_name = try dupeString(allocator, if (committer) |c| c.*.name else null);
    errdefer allocator.free(committer_name);

    const committer_email = try dupeString(allocator, if (committer) |c| c.*.email else null);
    errdefer allocator.free(committer_email);

    const committer_date: i64 = if (committer) |c| c.*.when.time else 0;

    const message = try dupeString(allocator, lg2.git_commit_message(commit));
    errdefer allocator.free(message);

    var tree: ?*lg2.git_tree = null;
    try check(lg2.git_commit_tree(&tree, commit));
    defer lg2.git_tree_free(tree);

    var parent_tree: ?*lg2.git_tree = null;
    if (lg2.git_commit_parentcount(commit) > 0) {
        var parent: ?*lg2.git_commit = null;
        try check(lg2.git_commit_parent(&parent, commit, 0));
        defer lg2.git_commit_free(parent);
        try check(lg2.git_commit_tree(&parent_tree, parent));
    }
    defer if (parent_tree) |pt| lg2.git_tree_free(pt);

    var diff: ?*lg2.git_diff = null;
    try check(lg2.git_diff_tree_to_tree(&diff, repo, parent_tree, tree, null));
    defer lg2.git_diff_free(diff);

    var stats: ?*lg2.git_diff_stats = null;
    try check(lg2.git_diff_get_stats(&stats, diff));
    defer lg2.git_diff_stats_free(stats);

    const files_changed = lg2.git_diff_stats_files_changed(stats);
    const insertions = lg2.git_diff_stats_insertions(stats);
    const deletions = lg2.git_diff_stats_deletions(stats);

    var diff_buf: lg2.git_buf = .{ .ptr = null, .reserved = 0, .size = 0 };
    try check(lg2.git_diff_to_buf(&diff_buf, diff, lg2.GIT_DIFF_FORMAT_PATCH));
    defer lg2.git_buf_dispose(&diff_buf);

    const diff_patch = if (diff_buf.ptr) |ptr|
        try allocator.dupe(u8, ptr[0..diff_buf.size])
    else
        try allocator.dupe(u8, "");
    errdefer allocator.free(diff_patch);

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

pub fn readHeadCommit(allocator: std.mem.Allocator, repo_path: [*:0]const u8) !CommitInfo {
    _ = lg2.git_libgit2_init();
    defer _ = lg2.git_libgit2_shutdown();

    var repo: ?*lg2.git_repository = null;
    try check(lg2.git_repository_open(&repo, repo_path));
    defer lg2.git_repository_free(repo);

    var oid: lg2.git_oid = undefined;
    try check(lg2.git_reference_name_to_id(&oid, repo, "HEAD"));

    var commit: ?*lg2.git_commit = null;
    try check(lg2.git_commit_lookup(&commit, repo, &oid));
    defer lg2.git_commit_free(commit);

    return readCommit(allocator, repo, &oid, commit);
}

/// Walk up to `max_commits` commits from HEAD and return their metadata.
/// Caller owns the returned slice and each CommitInfo within it.
pub fn walkCommits(allocator: std.mem.Allocator, repo_path: [*:0]const u8, max_commits: usize) ![]CommitInfo {
    _ = lg2.git_libgit2_init();
    defer _ = lg2.git_libgit2_shutdown();

    var repo: ?*lg2.git_repository = null;
    try check(lg2.git_repository_open(&repo, repo_path));
    defer lg2.git_repository_free(repo);

    var walker: ?*lg2.git_revwalk = null;
    try check(lg2.git_revwalk_new(&walker, repo));
    defer lg2.git_revwalk_free(walker);

    _ = lg2.git_revwalk_sorting(walker, lg2.GIT_SORT_TIME);
    try check(lg2.git_revwalk_push_head(walker));

    var commits: std.ArrayList(CommitInfo) = .empty;
    errdefer {
        for (commits.items) |*ci| ci.deinit();
        commits.deinit(allocator);
    }

    var oid: lg2.git_oid = undefined;
    while (commits.items.len < max_commits) {
        if (lg2.git_revwalk_next(&oid, walker) < 0) break;

        var commit: ?*lg2.git_commit = null;
        try check(lg2.git_commit_lookup(&commit, repo, &oid));
        defer lg2.git_commit_free(commit);

        const info = try readCommit(allocator, repo, &oid, commit);
        try commits.append(allocator, info);
    }

    return commits.toOwnedSlice(allocator);
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

test "walkCommits returns multiple commits" {
    const allocator = std.testing.allocator;
    const commits = try walkCommits(allocator, ".", 5);
    defer {
        for (commits) |*ci| {
            @constCast(ci).deinit();
        }
        allocator.free(commits);
    }

    // This repo has multiple commits
    try std.testing.expect(commits.len > 1);

    // First commit should be the most recent (same as HEAD)
    var head = try readHeadCommit(allocator, ".");
    defer head.deinit();
    try std.testing.expectEqualSlices(u8, &head.sha, &commits[0].sha);

    std.debug.print("\n--- walkCommits test ({d} commits) ---\n", .{commits.len});
    for (commits, 0..) |ci, i| {
        std.debug.print("[{d}] {s} {s}\n", .{ i, &ci.sha, ci.message[0..@min(ci.message.len, 60)] });
    }
    std.debug.print("--- end ---\n", .{});
}
