const std = @import("std");
const pg = @import("pg");
const lib = @import("../log.zig");

pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var target: []const u8 = "localhost";
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--target") or std.mem.eql(u8, args[i], "-t")) {
            if (i + 1 < args.len) {
                target = args[i + 1];
                i += 1;
            }
        }
    }

    var pool = pg.Pool.init(allocator, .{
        .size = 3,
        .connect = .{ .host = target, .port = 5432 },
        .auth = .{ .username = "postgres", .password = "pgv", .database = "postgres" },
    }) catch |err| {
        lib.log.err("Failed to connect to {s}: {}", .{ target, err });
        std.posix.exit(1);
    };
    defer pool.deinit();

    std.debug.print("connected to {s}!\n", .{target});

    _ = try pool.exec("CREATE EXTENSION vector;", .{});
    _ = try pool.exec("CREATE TABLE items (id bigserial PRIMARY KEY, embedding vector(3));", .{});
    _ = try pool.exec("INSERT INTO items (embedding) VALUES ('[1,2,3]'), ('[4,5,6]');", .{});
}
