const std = @import("std");
const pg = @import("pg");
const flags = @import("cmd/flags.zig");
const lib = @import("lib/log.zig");
const init_cmd = @import("cmd/init.zig");
const seed_cmd = @import("cmd/seed.zig");

const usage =
    \\ishi - git intelligence, from within
    \\
    \\Usage: git ishi <command> [options]
    \\
    \\Commands:
    \\  init    Initialize the pg database with pgvector
    \\  seed    Seed the pg database with embeddings
    \\
;

// GlobalFlags defines connection flags shared across all commands.
const GlobalFlags = struct {
    target: []const u8 = "localhost",
    username: []const u8 = "postgres",
    password: []const u8 = "ishi",
    database: []const u8 = "postgres",
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print(usage, .{});
        return;
    }

    const Cmd = enum { init, seed };
    const cmd = std.meta.stringToEnum(Cmd, args[1]) orelse {
        std.debug.print(usage, .{});
        return;
    };

    var gf = GlobalFlags{};
    try flags.parse(&gf, args[2..]);

    var pool = pg.Pool.init(allocator, .{
        .size = 1,
        .connect = .{ .host = gf.target, .port = 5432 },
        .auth = .{ .username = gf.username, .password = gf.password, .database = gf.database },
    }) catch |err| {
        lib.log.err("Failed to connect to {s}: {}", .{ gf.target, err });
        std.posix.exit(1);
    };
    defer pool.deinit();

    switch (cmd) {
        .init => try init_cmd.run(allocator, pool, args[2..]),
        .seed => try seed_cmd.run(allocator, pool, args[2..]),
    }
}
