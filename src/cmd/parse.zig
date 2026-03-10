const std = @import("std");
const help = @import("./help.zig");

pub const IshiCmd = enum {
    init,
    seed,
};

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
pub fn parse(flags: anytype, args: []const []const u8) !IshiCmd {
    if (args.len < 2) {
        help.help();
        std.posix.exit(1);
    }

    // Check for --help before attempting command dispatch so that
    // `ishi --help` exits cleanly with code 0 instead of failing
    // to match a command and exiting with code 1.
    if (std.mem.eql(u8, args[1], "--help")) {
        help.help();
        std.posix.exit(0);
    }

    // use tagged union to discover target command
    const tgt_cmd = std.meta.stringToEnum(IshiCmd, args[1]) orelse {
        help.help();
        std.posix.exit(1);
    };

    // Capture the concrete type of the dereferenced pointer (e.g. InitFlags).
    // This is needed so std.meta.fields can inspect its fields at comptime.
    const T = @TypeOf(flags.*);

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        // Strip the "--" prefix to get the bare flag name (e.g. "target").
        // If the arg doesn't start with "--", it isn't a flag — skip it.
        const name = if (std.mem.startsWith(u8, arg, "--"))
            arg[2..]
        else
            continue;

        // any instance of the help flag should trigger the help usage.
        if (std.mem.eql(u8, name, help.help_flag)) {
            help.help();
            std.posix.exit(0);
        }

        // `inline for` unrolls this loop at comptime over the struct's fields.
        // At runtime it behaves like a chain of if/else checks, but the field
        // list is resolved statically — no reflection overhead at runtime.
        inline for (std.meta.fields(T)) |field| {
            if (std.mem.eql(u8, name, field.name)) {
                if (i + 1 < args.len) {
                    // `@field` is a comptime builtin that reads or writes a
                    // struct field by name as a string literal. Equivalent to
                    // `flags.target = args[i+1]` when field.name is "target".
                    @field(flags.*, field.name) = args[i + 1];
                    i += 1;
                }
            }
        }
    }

    return tgt_cmd;
}
