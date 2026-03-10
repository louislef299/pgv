// Flags defines all CLI flags shared across commands.
const std = @import("std");
const zul = @import("zul");

const log = @import("../lib/log.zig").log;
const models = @import("../lib/models.zig");
const Model = @import("../lib/models.zig").Model;

const Flags = @This();

pub const IshiCmd = enum {
    init,
    seed,
    query,
};

cmd: IshiCmd,
target: []const u8,
username: []const u8,
password: []const u8,
database: []const u8,
model: Model,
path: []const u8,
query: []const u8,
allocator: std.mem.Allocator,

pub fn deinit(self: Flags) void {
    self.allocator.free(self.target);
    self.allocator.free(self.username);
    self.allocator.free(self.password);
    self.allocator.free(self.database);
    self.allocator.free(self.path);
    if (self.query.len > 0) self.allocator.free(self.query);
}

pub const help_flag = "help";
pub const usage =
    \\ishi - pgvector storage for git intelligence
    \\
    \\Usage: ishi <command> [flags] [args]
    \\
    \\Commands:
    \\  init    Initialize the pg database with pgvector
    \\  seed    Seed the pg database with embeddings
    \\  query   Semantic search: ishi query "your question here"
    \\
    \\Flags:
    \\  --target      target pg connection (default: localhost)
    \\  --username    pg username (default: postgres)
    \\  --password    pg password (default: ishi)
    \\  --database    pg database (default: postgres)
    \\  --model       ollama embedding model (default: nomic-embed-text)
    \\  --path        path to the JSON seed file (default: ./seed.json)
;

pub fn init(allocator: std.mem.Allocator) !Flags {
    const cmd = try parse(allocator);

    // https://www.goblgobl.com/zul/command_line_args/
    var args = try zul.CommandLineArgs.parse(allocator);
    defer args.deinit();

    if (args.contains(help_flag)) {
        help();
        std.posix.exit(0);
    }

    // Validate the model before running DDL.
    const model_name = args.get("model") orelse "nomic-embed-text";
    const mod = models.find(model_name) orelse {
        log.err("Unknown model '{s}'. Supported models:", .{model_name});
        for (models.models) |m| log.err("  {s}", .{m.name});
        std.posix.exit(1);
    };

    return .{
        .cmd = cmd,
        .target = try allocator.dupe(u8, args.get("target") orelse "localhost"),
        .username = try allocator.dupe(u8, args.get("username") orelse "postgres"),
        .password = try allocator.dupe(u8, args.get("password") orelse "ishi"),
        .database = try allocator.dupe(u8, args.get("database") orelse "postgres"),
        .model = mod,
        .path = try allocator.dupe(u8, args.get("path") orelse "./src/seed.json"),
        .query = if (args.tail.len >= 2) try allocator.dupe(u8, args.tail[1]) else "",
        .allocator = allocator,
    };
}

pub fn help() void {
    std.debug.print("{s}\n", .{usage});
}

// parse populates a command's flags struct from a slice of CLI args.
//
// `flags` is a pointer to any struct whose fields represent the supported
// flags for that command (e.g. `*InitFlags`). Field names map directly to
// flag names, and field default values serve as the defaults — no separate
// registry needed.
//
// `anytype` is Zig's way of accepting a generic pointer at comptime. The
// actual type is resolved at the call site, so this function is effectively
// monomorphized (compiled separately) for each flags struct that uses it.
//
// Only `--flag value` style is supported (no short flags, no `--flag=value`).
pub fn parse(allocator: std.mem.Allocator) !IshiCmd {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        help();
        std.posix.exit(1);
    }

    // Check for --help before attempting command dispatch so that
    // `ishi --help` exits cleanly with code 0 instead of failing
    // to match a command and exiting with code 1.
    if (std.mem.eql(u8, args[1], "--help")) {
        help();
        std.posix.exit(0);
    }

    // use tagged union to discover target command
    const tgt_cmd = std.meta.stringToEnum(IshiCmd, args[1]) orelse {
        help();
        std.posix.exit(1);
    };
    return tgt_cmd;
}
