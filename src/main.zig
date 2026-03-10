const std = @import("std");
const pg = @import("pg");
const parse = @import("cmd/parse.zig");
const lib = @import("lib/log.zig");
const init_cmd = @import("cmd/init.zig");
const seed_cmd = @import("cmd/seed.zig");

// Flags defines all CLI flags shared across commands.
pub const Flags = struct {
    target: []const u8 = "localhost",
    username: []const u8 = "postgres",
    password: []const u8 = "ishi",
    database: []const u8 = "postgres",
    model: []const u8 = "nomic-embed-text",
    path: []const u8 = "./seed.json",
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var f = Flags{};
    const cmd = try parse.parse(&f, args[0..]);

    var pool = pg.Pool.init(allocator, .{
        .size = 1,
        .connect = .{ .host = f.target, .port = 5432 },
        .auth = .{ .username = f.username, .password = f.password, .database = f.database },
    }) catch |err| {
        lib.log.err("Failed to connect to {s}: {}", .{ f.target, err });
        std.posix.exit(1);
    };
    defer pool.deinit();

    switch (cmd) {
        .init => try init_cmd.run(allocator, pool, f),
        .seed => try seed_cmd.run(allocator, pool, f),
    }
}
