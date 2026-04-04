const std = @import("std");

/// A supported embedding model and its vector output dimensions.
pub const Model = struct {
    name: []const u8,
    dims: u16,
};

/// Known embedding models.
pub const models = [_]Model{
    .{ .name = "nomic-embed-text", .dims = 768 },
    .{ .name = "mxbai-embed-large", .dims = 1024 },
    .{ .name = "all-minilm", .dims = 384 },
};

/// Returns the model matching `name`, or null if not found.
pub fn find(name: []const u8) ?Model {
    for (models) |m| {
        if (std.mem.eql(u8, m.name, name)) return m;
    }
    return null;
}
