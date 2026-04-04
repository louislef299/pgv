const std = @import("std");
const zul = @import("zul");

const log = @import("log.zig").log;

const OllamaResponse = struct {
    embedding: []f64,
};

/// Calls the Ollama /api/embeddings endpoint and returns the raw embedding
/// vector. Caller owns the returned slice.
pub fn getEmbedding(
    allocator: std.mem.Allocator,
    model_name: []const u8,
    text: []const u8,
) ![]f64 {
    // Build the JSON request body for Ollama with proper escaping.
    const Payload = struct { model: []const u8, prompt: []const u8 };
    const body = try std.json.Stringify.valueAlloc(
        allocator,
        Payload{ .model = model_name, .prompt = text },
        .{},
    );
    defer allocator.free(body);

    // https://www.goblgobl.com/zul/http/client/
    var client = zul.http.Client.init(allocator);
    defer client.deinit();

    const endpoint: []const u8 = "http://localhost:11434/api/embeddings";
    var req = client.request(endpoint) catch |err| {
        log.err("Failed to build embedding POST request: {}", .{err});
        return err;
    };
    defer req.deinit();
    req.method = .POST;
    try req.header("Content-Type", "application/json");
    req.body(body);

    var res = req.getResponse(.{}) catch |err| {
        log.err("Failed to POST to {s}: {}", .{ endpoint, err });
        return err;
    };
    if (res.status != 200) {
        log.err("Ollama request failed with status {d}", .{res.status});
        return error.OllamaRequestFailed;
    }

    const managed = try res.json(OllamaResponse, allocator, .{});
    defer managed.deinit();

    // Dupe so the slice outlives the managed response.
    return try allocator.dupe(f64, managed.value.embedding);
}
