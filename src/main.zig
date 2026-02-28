// https://ziglang.org/documentation/0.15.2/std
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var buf: [1024]u8 = undefined;
    var stdW = std.fs.File.stdout().writer(&buf);
    const stdout = &stdW.interface;

    var args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    for (args[1..]) |arg| {
        try stdout.print("{s} ", .{arg});
    }
    try stdout.print("\n", .{});
    try stdout.flush();
}
