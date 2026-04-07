# Writergate: Zig I/O API Changes

Zig's stdout API has changed significantly across versions as part of a
deliberate I/O overhaul nicknamed "Writergate" introduced in 0.15.1.

## Version History

| Version | Pattern |
|---------|---------|
| ≤ 0.14  | `std.io.getStdOut().writer()` |
| 0.15.x  | `std.fs.File.stdout().writer(&buf)` |
| master  | `std.Io.File.stdout().writer(&buf)` |

## Why It Changed

The old unbuffered API issued a syscall per write. The new design batches writes
into a user-provided buffer and flushes on demand, reducing syscall overhead.
The buffer is stored directly in the `Writer` struct rather than as a separate
`BufferedWriter` wrapper.

As a consequence, **forgetting to call `.flush()` will silently drop output.**

## Current Pattern (0.15.x)

```zig
var buf: [4096]u8 = undefined;
var file_writer = std.fs.File.stdout().writer(&buf);
const stdout = &file_writer.interface;

try stdout.print("hello {s}\n", .{name});
try stdout.flush();
```

## In Master

`File` moved from `std.fs` into `std.Io`, so the handle becomes
`std.Io.File.stdout()`. The `std.io` namespace (lowercase) is entirely gone —
replaced by `std.Io` (capitalized), following Zig's convention where a
capitalized name signals a file that defines a primary type/namespace.

## The Broader std.Io Reorganization (master)

Writergate wasn't just about buffering — it triggered a full reorganization of
the standard library's I/O and concurrency primitives. As of 0.16.0-dev, the
following have moved or been removed:

### Moved to `std.Io`
| Old location | New location |
|---|---|
| `std.Thread.Mutex` | `std.Io.Mutex` |
| `std.Thread.Condition` | `std.Io.Condition` |
| `std.net` (entire module) | `std.Io.net` |
| `std.fs.File` | `std.Io.File` |
| `std.fs.Dir` | `std.Io.Dir` |
| Random bytes (`std.crypto.random`) | `std.Io.random(io, buf)` |

### Removed builtins
| Removed | Replacement |
|---|---|
| `@Type(.{ .int = .{ ... } })` | `std.meta.Int(signedness, bits)` (wraps new `@Int` builtin) |

### New `std.Io.Mutex` / `std.Io.Condition` initialization
The new structs use a named `init` constant instead of zero-initialization:
```zig
// old
var mu: std.Thread.Mutex = .{};

// new
var mu: std.Io.Mutex = .init;
var cond: std.Io.Condition = .init;
```

### `std.Io` requires an `io: Io` context
The most significant architectural change: many operations that previously took
only an allocator now require an `Io` context parameter. This includes:
- `std.Io.net` connect functions
- `std.Io.Condition.wait` / `signal`
- Random byte generation
- File and directory operations

The `Io` context is obtained from `std.process.Init` in `main`:
```zig
// new Zig master main signature
pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
}
```

## Ecosystem Impact

The `Io` context requirement cascades through any library that touches
networking, threading, or randomness. Libraries targeting Zig stable (0.15.x)
are incompatible with master until they thread `Io` through their APIs.
Real-world examples encountered during this project:

- **pg.zig** (karlseguin): `Thread.Mutex`, `std.net`, `std.crypto.random` all
  broke on master. PR #100 is an in-progress port but incomplete as of Feb 2026.
- **metrics** (karlseguin): `@Type` builtin removed; fix is `std.meta.Int`.
- **yazap** 0.7.0: requires master (uses `std.Io.Threaded` in build.zig),
  making it incompatible with 0.15.x.

The practical consequence: **you cannot mix a master-only library with a
stable-only library**. Pick a Zig version and find deps that target it.

## Sources

- [Zig 0.15.1 I/O Overhaul - DEV Community](https://dev.to/bkataru/zig-0151-io-overhaul-understanding-the-new-readerwriter-interfaces-30oe)
- [i need to flush my toilet bro - bkataru](https://bkataru.bearblog.dev/zig-said-muh-buffers/)
- [Inside Zig's New Writer - Joe Mckay](https://joegm.github.io/blog/inside-zigs-new-writer-interface/)
- [GitHub Issue #24675: stdout in master is weaker](https://github.com/ziglang/zig/issues/24675)
- [GitHub Issue #24412: Buffered Write to stdout fails to flush](https://github.com/ziglang/zig/issues/24412)
- [Zig 0.15.1 Release Notes](https://ziglang.org/download/0.15.1/release-notes.html)
- [karlseguin/pg.zig Issue #102: build.zig uses removed Build API](https://github.com/karlseguin/pg.zig/issues/102)
- [karlseguin/pg.zig Issue #108: std.posix.close() removed](https://github.com/karlseguin/pg.zig/issues/108)
- [karlseguin/pg.zig PR #100: update to new zig async io](https://github.com/karlseguin/pg.zig/pull/100)
