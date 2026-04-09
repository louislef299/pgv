// Copyright 2026 Louis LeFebvre
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

const std = @import("std");
const pg = @import("pg");

const Flags = @import("./cmd/Flags.zig");
const git = @import("lib/git.zig");
const init_cmd = @import("cmd/init.zig");
pub const log = std.log.scoped(.ishi);
const query_cmd = @import("cmd/query.zig");
const seed_cmd = @import("cmd/seed.zig");

// Force the test runner to discover tests in transitively-imported modules.
test {
    @import("std").testing.refAllDecls(@This());
    _ = git;
}

pub const std_options: std.Options = .{
    .log_level = .info,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const f = try Flags.init(allocator);
    defer f.deinit();

    var pool = pg.Pool.init(allocator, .{
        .size = 1,
        .connect = .{ .host = f.target, .port = 5432 },
        .auth = .{ .username = f.username, .password = f.password, .database = f.database },
    }) catch |err| {
        log.err("Failed to connect to {s}(is the db running?): {}", .{ f.target, err });
        std.posix.exit(1);
    };
    defer pool.deinit();

    switch (f.cmd) {
        .init => try init_cmd.run(allocator, pool, f),
        .seed => seed_cmd.run(allocator, pool, f) catch |err| {
            log.err("seed command failed: {}", .{err});
            return;
        },
        .query => try query_cmd.run(allocator, pool, f),
    }
}
