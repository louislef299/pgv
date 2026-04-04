# Agents

## Pre-Commit

```bash
zig build --summary all
zig build test --summary all
zig fmt --check .
```

## System Dependencies

This is a Zig + C interop project. `zig build` will fail with linker errors
unless `libgit2` is installed on the system:

- **macOS:** `brew install libgit2`
- **Linux:** `apt-get install libgit2-dev build-essential`

Run `zig build --fetch` if remote Zig dependencies have not been fetched yet.

## Conventions

- New `.zig` source files must include the Apache 2.0 copyright header
  (see `src/main.zig` lines 1-13 for the exact text).

## Gotchas

- Tests in `src/lib/git.zig` run against the **live git repo** — they call
  libgit2 on the actual `.git` directory. Tests must be run inside the cloned
  repo with full history (`fetch-depth: 0` in CI).
