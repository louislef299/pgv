const std = @import("std");
const pg = @import("pg");

const Flags = @import("./cmd/Flags.zig");
const init_cmd = @import("cmd/init.zig");
const lib = @import("lib/log.zig");
const seed_cmd = @import("cmd/seed.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const f = try Flags.init(allocator);

    var pool = pg.Pool.init(allocator, .{
        .size = 1,
        .connect = .{ .host = f.target, .port = 5432 },
        .auth = .{ .username = f.username, .password = f.password, .database = f.database },
    }) catch |err| {
        lib.log.err("Failed to connect to {s}: {}", .{ f.target, err });
        std.posix.exit(1);
    };
    defer pool.deinit();

    switch (f.cmd) {
        .init => try init_cmd.run(allocator, pool, f),
        .seed => try seed_cmd.run(allocator, pool, f),
    }
}
