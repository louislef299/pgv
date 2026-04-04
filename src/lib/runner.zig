const std = @import("std");
const zul = @import("zul");

const Runner = @import("../cmd/Flags.zig").Runner;
const log = @import("log.zig").log;

const EmbeddingResponse = struct {
    embedding: []f64,
};

pub const Opts = struct {
    text: []const u8,
    model_name: []const u8 = "nomic-embed-text",
    runner: Runner = Runner.ollama,
};

/// Calls the model runner's embeddings endpoint and returns the raw embedding
/// vector. Caller owns the returned slice.
pub fn getEmbedding(
    allocator: std.mem.Allocator,
    opts: Opts,
) ![]f64 {
    // Build the JSON request body with proper escaping.
    const Payload = struct { model: []const u8, prompt: []const u8 };
    const body = try std.json.Stringify.valueAlloc(
        allocator,
        Payload{ .model = opts.model_name, .prompt = opts.text },
        .{},
    );
    defer allocator.free(body);

    // https://www.goblgobl.com/zul/http/client/
    var client = zul.http.Client.init(allocator);
    defer client.deinit();

    const endpoint: []const u8 = switch (opts.runner) {
        .ollama => "http://localhost:11434/api/embeddings",
        .docker => "http://localhost:12434/engines/llama.cpp/v1/embeddings",
    };

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
        log.err("{s} request to {s} failed with status {d}", .{
            @tagName(opts.runner),
            endpoint,
            res.status,
        });
        return error.RunnerRequestFailed;
    }

    const managed = try res.json(EmbeddingResponse, allocator, .{});
    defer managed.deinit();

    // Dupe so the slice outlives the managed response.
    return try allocator.dupe(f64, managed.value.embedding);
}
