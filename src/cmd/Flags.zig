// Flags defines all CLI flags shared across commands.
const std = @import("std");

const log = @import("../lib/log.zig").log;
const models = @import("../lib/models.zig");
const Model = @import("../lib/models.zig").Model;

const Flags = @This();

pub const IshiCmd = enum {
    init,
    seed,
    query,
};

pub const Runner = enum {
    docker,
    ollama,
};

cmd: IshiCmd,
target: []const u8,
username: []const u8,
password: []const u8,
database: []const u8,
model: Model,
path: []const u8,
query: []const u8,
git: bool,
limit: usize,
runner: Runner,
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
    \\  --git         seed from git commit history instead of JSON
    \\  --limit       max commits to ingest with --git (default: 50)
    \\  --runner      local model runner to use (default: ollama)
;

pub fn init(allocator: std.mem.Allocator) !Flags {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        help();
        std.posix.exit(1);
    }

    if (std.mem.eql(u8, args[1], "--help")) {
        help();
        std.posix.exit(0);
    }

    const cmd = std.meta.stringToEnum(IshiCmd, args[1]) orelse {
        help();
        std.posix.exit(1);
    };

    // Parse --key value pairs and boolean flags from args[2..]
    var target: []const u8 = "localhost";
    var username: []const u8 = "postgres";
    var password: []const u8 = "ishi";
    var database: []const u8 = "postgres";
    var model_name: []const u8 = "nomic-embed-text";
    var path: []const u8 = "./src/seed.json";
    var query: []const u8 = "";
    var git = false;
    var limit: usize = 50;
    var runner: Runner = Runner.ollama;

    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help")) {
            help();
            std.posix.exit(0);
        } else if (std.mem.eql(u8, arg, "--git")) {
            git = true;
        } else if (std.mem.eql(u8, arg, "--target")) {
            i += 1;
            target = if (i < args.len) args[i] else target;
        } else if (std.mem.eql(u8, arg, "--username")) {
            i += 1;
            username = if (i < args.len) args[i] else username;
        } else if (std.mem.eql(u8, arg, "--password")) {
            i += 1;
            password = if (i < args.len) args[i] else password;
        } else if (std.mem.eql(u8, arg, "--database")) {
            i += 1;
            database = if (i < args.len) args[i] else database;
        } else if (std.mem.eql(u8, arg, "--model")) {
            i += 1;
            model_name = if (i < args.len) args[i] else model_name;
        } else if (std.mem.eql(u8, arg, "--path")) {
            i += 1;
            path = if (i < args.len) args[i] else path;
        } else if (std.mem.eql(u8, arg, "--limit")) {
            i += 1;
            if (i < args.len) {
                limit = std.fmt.parseInt(usize, args[i], 10) catch {
                    log.err("Invalid --limit value '{s}'", .{args[i]});
                    std.posix.exit(1);
                };
            }
        } else if (std.mem.eql(u8, arg, "--runner")) {
            i += 1;
            if (i < args.len) {
                runner = std.meta.stringToEnum(Runner, args[i]) orelse {
                    log.err("Unknown runner '{s}'. Supported: docker, ollama", .{args[i]});
                    std.posix.exit(1);
                };
            }
        } else {
            // Positional arg (e.g. query string)
            query = arg;
        }
    }

    const mod = models.find(model_name) orelse {
        log.err("Unknown model '{s}'. Supported models:", .{model_name});
        for (models.models) |m| log.err("  {s}", .{m.name});
        std.posix.exit(1);
    };

    return .{
        .cmd = cmd,
        .target = try allocator.dupe(u8, target),
        .username = try allocator.dupe(u8, username),
        .password = try allocator.dupe(u8, password),
        .database = try allocator.dupe(u8, database),
        .model = mod,
        .path = try allocator.dupe(u8, path),
        .query = if (query.len > 0) try allocator.dupe(u8, query) else "",
        .git = git,
        .limit = limit,
        .allocator = allocator,
        .runner = runner,
    };
}

pub fn help() void {
    std.debug.print("{s}\n", .{usage});
}
