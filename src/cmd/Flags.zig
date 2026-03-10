// Flags defines all CLI flags shared across commands.
const std = @import("std");
const zul = @import("zul");

const Flags = @This();

pub const IshiCmd = enum {
    init,
    seed,
};

cmd: IshiCmd,
target: []const u8,
username: []const u8,
password: []const u8,
database: []const u8,
model: []const u8,
path: []const u8,

pub const help_flag = "help";
pub const usage =
    \\ishi - pgvector storage for git intelligence
    \\
    \\Usage: git ishi <command> [flags]
    \\
    \\Commands:
    \\  init    Initialize the pg database with pgvector
    \\  seed    Seed the pg database with embeddings
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

    return .{
        .cmd = cmd,
        .target = args.get("target") orelse "localhost",
        .username = args.get("username") orelse "postgres",
        .password = args.get("password") orelse "ishi",
        .database = args.get("database") orelse "postgres",
        .model = args.get("model") orelse "nomic-embed-text",
        .path = args.get("path") orelse "./src/seed.json",
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
