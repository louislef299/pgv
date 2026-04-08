const std = @import("std");
const zul = @import("zul");

const Runner = @import("../cmd/Flags.zig").Runner;
const log = @import("log.zig").log;
const retry = @import("retry.zig");

/// Ollama /api/embeddings response: { "embedding": [...] }
const OllamaEmbeddingResponse = struct {
    embedding: []f64,
};

/// OpenAI /v1/embeddings response: { "data": [{ "embedding": [...] }] }
const OpenAIEmbeddingData = struct {
    embedding: []f64,
};

const OpenAIEmbeddingResponse = struct {
    data: []OpenAIEmbeddingData,
};

pub const Opts = struct {
    text: []const u8,
    model_name: []const u8 = "ai/nomic-embed-text-v1.5",
    runner: Runner = Runner.docker,
};

/// Captures the arguments needed by a single embedding attempt so the
/// function can be passed to `retry.retry` which takes `fn(Context) !T`.
const EmbeddingContext = struct {
    allocator: std.mem.Allocator,
    opts: Opts,
};

/// Calls the configured model runner's embeddings endpoint and returns the
/// raw embedding vector, retrying with exponential backoff on transient
/// failures. Caller owns the returned slice.
pub fn getEmbedding(
    allocator: std.mem.Allocator,
    opts: Opts,
) ![]f64 {
    const ctx = EmbeddingContext{ .allocator = allocator, .opts = opts };
    return switch (opts.runner) {
        .ollama => retry.retry([]f64, .{}, ctx, attemptOllamaEmbedding),
        .docker => retry.retry([]f64, .{}, ctx, attemptDockerEmbedding),
    };
}

fn attemptOllamaEmbedding(ctx: EmbeddingContext) anyerror![]f64 {
    return getOllamaEmbedding(ctx.allocator, ctx.opts);
}

fn attemptDockerEmbedding(ctx: EmbeddingContext) anyerror![]f64 {
    return getDockerEmbedding(ctx.allocator, ctx.opts);
}

fn getOllamaEmbedding(allocator: std.mem.Allocator, opts: Opts) ![]f64 {
    const Payload = struct { model: []const u8, prompt: []const u8 };
    const body = try buildBody(allocator, Payload, .{
        .model = opts.model_name,
        .prompt = opts.text,
    });
    defer allocator.free(body);

    const endpoint = "http://localhost:11434/api/embeddings";

    var client = zul.http.Client.init(allocator);
    defer client.deinit();

    var req = client.request(endpoint) catch |err| {
        log.err("Failed to create request for {s}: {}", .{ endpoint, err });
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
        const err_body = res.allocBody(allocator, .{ .max_size = 4096 }) catch |err| {
            log.err("ollama request to {s} failed with status {d} (could not read body: {})", .{ endpoint, res.status, err });
            return error.RunnerRequestFailed;
        };
        defer err_body.deinit();
        log.err("ollama request to {s} failed with status {d}: {s}", .{
            endpoint,
            res.status,
            err_body.string(),
        });
        return error.RunnerRequestFailed;
    }

    const managed = try res.json(OllamaEmbeddingResponse, allocator, .{});
    defer managed.deinit();

    return try allocator.dupe(f64, managed.value.embedding);
}

fn getDockerEmbedding(allocator: std.mem.Allocator, opts: Opts) ![]f64 {
    const Payload = struct { model: []const u8, input: []const u8 };
    const body = try buildBody(allocator, Payload, .{
        .model = opts.model_name,
        .input = opts.text,
    });
    defer allocator.free(body);

    const endpoint = "http://localhost:12434/engines/llama.cpp/v1/embeddings";

    var client = zul.http.Client.init(allocator);
    defer client.deinit();

    var req = client.request(endpoint) catch |err| {
        log.err("Failed to create request for {s}: {}", .{ endpoint, err });
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
        const err_body = res.allocBody(allocator, .{ .max_size = 4096 }) catch |err| {
            log.err("docker request to {s} failed with status {d} (could not read body: {})", .{ endpoint, res.status, err });
            return error.RunnerRequestFailed;
        };
        defer err_body.deinit();
        log.err("docker request to {s} failed with status {d}: {s}", .{
            endpoint,
            res.status,
            err_body.string(),
        });
        return error.RunnerRequestFailed;
    }

    const managed = try res.json(OpenAIEmbeddingResponse, allocator, .{
        .ignore_unknown_fields = true,
    });
    defer managed.deinit();

    if (managed.value.data.len == 0) {
        log.err("docker response contained no embedding data", .{});
        return error.RunnerRequestFailed;
    }

    return try allocator.dupe(f64, managed.value.data[0].embedding);
}

/// Serializes a struct value to a JSON byte string. Caller owns the result.
fn buildBody(
    allocator: std.mem.Allocator,
    comptime T: type,
    value: T,
) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, value, .{});
}
