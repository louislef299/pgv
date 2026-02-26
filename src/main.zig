const std = @import("std");
const pgvector_playground = @import("pgvector_playground");

pub fn main() !void {
    // Prints to stderr, ignoring potential errors.
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
    try pgvector_playground.bufferedPrint();
}
