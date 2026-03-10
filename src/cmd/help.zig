const std = @import("std");

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

pub fn help() void {
    std.debug.print("{s}\n", .{usage});
}
