// https://ziglang.org/documentation/0.15.2/std
const std = @import("std");
const yazap = @import("yazap");

const App = yazap.App;
const Arg = yazap.Arg;

// https://codeberg.org/ziglang/zig/pulls/30644
pub fn main(init: std.process.Init) !void {
    var app = App.init(init.gpa, "pgv", "My pgvector tool");
    defer app.deinit();

    var pgv = app.rootCommand();
    pgv.setProperty(.help_on_empty_args);

    // pgv init -h
    var cmd_init = app.createCommand(
        "init",
        "Initialize the pg database with pgvector",
    );
    try cmd_init.addArg(Arg.singleValueOption("target", 't', "The name of the target db hostname"));
    try pgv.addSubcommand(cmd_init);

    const matches = try app.parseProcess(init.io, init.minimal.args);
    if (matches.containsArg("init")) {
        std.debug.print("Initilize pg database", .{});
        return;
    }
}
