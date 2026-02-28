// https://ziglang.org/documentation/0.15.2/std
const std = @import("std");
const App = @import("yazap").App;

const init_cmd = @import("cmd/init.zig");

// https://codeberg.org/ziglang/zig/pulls/30644
pub fn main(init: std.process.Init) !void {
    var app = App.init(init.gpa, "pgv", "My pgvector tool");
    defer app.deinit();

    var pgv = app.rootCommand();
    pgv.setProperty(.help_on_empty_args);

    // pgv init -h
    const cmd_init = try init_cmd.create(&app);
    try pgv.addSubcommand(cmd_init);

    const matches = try app.parseProcess(init.io, init.minimal.args);
    if (matches.subcommandMatches("init")) |init_matches| {
        try init_cmd.run(&init_matches);
    }
}
