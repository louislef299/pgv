const std = @import("std");
const log = @import("log.zig").log;

/// Configuration for retry behavior with exponential backoff.
pub const Config = struct {
    /// Maximum number of attempts (including the initial call).
    max_retries: u4 = 3,

    /// Initial backoff duration in milliseconds before the first retry.
    initial_backoff_ms: u64 = 500,

    /// Multiplier applied to the backoff after each failed attempt.
    backoff_multiplier: u64 = 2,

    /// Upper bound on backoff duration in milliseconds.
    max_backoff_ms: u64 = 10_000,
};

/// Retries a fallible function with exponential backoff.
///
/// `requestFn` is called with `context` and must return `anyerror!ResultT`.
/// On failure the call is retried up to `config.max_retries` total attempts,
/// sleeping between attempts with exponentially increasing backoff. If all
/// attempts fail the last error is returned to the caller.
pub fn retry(
    comptime ResultT: type,
    config: Config,
    context: anytype,
    comptime requestFn: fn (@TypeOf(context)) anyerror!ResultT,
) anyerror!ResultT {
    var backoff_ms = config.initial_backoff_ms;
    var attempts: u4 = 0;

    while (true) {
        attempts += 1;
        if (requestFn(context)) |value| {
            if (attempts > 1)
                log.info("succeeded on attempt {d}", .{attempts});
            return value;
        } else |err| {
            if (attempts >= config.max_retries) {
                log.warn("failed after {d} attempts: {}", .{ attempts, err });
                return err;
            }
            log.warn("attempt {d}/{d} failed: {}, retrying in {d}ms...", .{
                attempts, config.max_retries, err, backoff_ms,
            });
            std.Thread.sleep(backoff_ms * std.time.ns_per_ms);
            backoff_ms = @min(backoff_ms * config.backoff_multiplier, config.max_backoff_ms);
        }
    }
}

// Tests //

test "retry succeeds on first attempt" {
    const ctx = CountingContext{ .fail_n = 0 };
    const result = try retry(u32, .{}, ctx, CountingContext.call);
    try std.testing.expectEqual(@as(u32, 42), result);
}

test "retry succeeds after transient failures" {
    const ctx = CountingContext{ .fail_n = 2 };
    const result = try retry(u32, .{
        .max_retries = 4,
        .initial_backoff_ms = 0, // no sleeping in tests
    }, ctx, CountingContext.call);
    try std.testing.expectEqual(@as(u32, 42), result);
}

test "retry returns last error when exhausted" {
    const ctx = CountingContext{ .fail_n = 10 };
    const result = retry(u32, .{
        .max_retries = 3,
        .initial_backoff_ms = 0,
    }, ctx, CountingContext.call);
    try std.testing.expectError(error.MockFailure, result);
}

/// A simple test helper that fails the first `fail_n` calls, then succeeds.
/// Uses a mutable pointer behind the scenes so the retry loop can observe
/// the changing counter through an immutable context value.
const CountingContext = struct {
    fail_n: u32,
    counter: *u32 = &shared_counter,

    // Shared mutable state for tests (single-threaded test runner).
    var shared_counter: u32 = 0;

    fn call(self: CountingContext) anyerror!u32 {
        const current = self.counter.*;
        self.counter.* = current + 1;
        if (current < self.fail_n) return error.MockFailure;
        // Reset for the next test.
        self.counter.* = 0;
        return 42;
    }
};
