//! HTTP ingress app (F-1/M5, S4), part of the shared CLI folder `src/cmd/`
//! (ADR-011). The ingress is the only component allowed to speak HTTP: it
//! terminates the browser SDK's POST, validates integrity, wraps the body in
//! an FPKG frame, forwards it to a pooled worker over the `--transport=tcp`
//! path, and translates the FPKG reply back to HTTP.
//!
//! It contains **no engine code**: `engine` is not registered in this
//! module's import map (build.zig), so the rule is structurally enforced
//! (design §7, D16). It imports only `io` + `adapter` framing helpers.
//!
//! CLI (invoked standalone or via the combined `fingerprint` binary — the
//! argv contract is identical, see `parse`):
//!   ingress start --listen=host:port --worker=host:port [--worker=...]
//!                 [--max-body=bytes] [--log-level=level]
//!                 [--log-format=text|json]
//!   ingress version
//!   ingress help
//!
//! S4 status: CLI surface + parse are implemented and unit-tested; the
//! `start` server (HTTP termination, boundary checks, worker pool, status
//! mapping, graceful shutdown) is S4-c/d — specs/architecture/ingress-server.md.
//!
//! story: s4-ingress-http

const std = @import("std");
const io = @import("io");
const version_info = @import("version");
const shutdown = @import("shutdown");
const obs = @import("obs");
const log = @import("log");

/// Routes `std.log` (the AMQP client's `std.log.scoped(.amqp)`) through the
/// application logger (specs/architecture/logging.md, F-2/S3). The comptime
/// level stays `.debug` — the TigerBeetle pattern — so `--log-level` is the
/// only filter and debug messages are never compiled out.
pub const std_options = std.Options{
    .log_level = .debug,
    .logFn = log.logFn,
};

/// S4-c/d: the HTTP server (bounded parser + boundary checks) and the
/// worker pool. Exposed so the unit tests can exercise the pure parser and
/// the status mapping without sockets.
pub const http = @import("http.zig");
/// Request authentication (M7 W6-D3). Exposed so tests can sign requests with
/// the same canonical string the ingress verifies.
pub const hmac = @import("hmac.zig");
/// Worker pool and readiness re-probe. Exposed so tests can exercise the
/// stale-connection logic without spawning a full ingress.
pub const pool = @import("pool.zig");
/// Metrics registry (ADR-014 §2). Exposed so tests can pin the catalog.
pub const metrics = @import("metrics.zig");

/// Product version, injected from build.zig.zon as the `version`
/// build-options module (ADR-011/BUG-002).
pub const version = version_info.version;

/// Default cap on accepted POST bodies. Far below the 16 MiB FPKG cap and
/// comfortably above a real package (canvas/audio bytes are tens of KB).
pub const default_max_body: u64 = 1024 * 1024;

/// Default metrics + probe listener (ADR-014 §4). Enabled by default so a
/// deployment cannot silently have no observability; `off` disables it.
pub const default_metrics_listen = ":9090";

/// Bound on one readiness probe connect. Short enough that a dead worker
/// cannot stall the accept loop; the request path keeps its 5s budget.
const probe_timeout_ns: u64 = 250 * std.time.ns_per_ms;

/// Set by the shared shutdown handlers (src/cmd/shutdown.zig, H-2); the
/// accept loop polls it so the ingress drains and exits 0 on SIGTERM/SIGINT.
pub const shutdown_requested = &shutdown.requested;

/// Installs the shared shutdown handlers (src/cmd/shutdown.zig).
pub fn installShutdownHandlers() void {
    shutdown.install();
}

/// How long the accept loop waits for a client before re-checking the
/// shutdown flag while idle.
const accept_poll_ms: u32 = 250;

// ── CLI ──────────────────────────────────────────────────────────────

pub const StartOptions = struct {
    /// host:port to bind for HTTP; port 0 binds an ephemeral port.
    listen: ?[]const u8 = null,
    /// Worker pool seeds, each host:port (repeatable). The runtime also
    /// accepts FPKG_WORKERS (comma-separated) for containerized deploys.
    workers: [max_workers][]const u8 = undefined,
    worker_count: usize = 0,
    /// Content-Length cap for POST bodies (413 above it).
    max_body: u64 = default_max_body,
    /// --log-level (err|warn|info|debug); null = FPKG_LOG_LEVEL, then info.
    log_level: ?log.Level = null,
    /// --log-format (text|json); null = FPKG_LOG_FORMAT, then text.
    log_format: ?log.Format = null,
    /// --metrics-listen (host:port) for the scrape + probe surface; defaults
    /// to `:9090`. `off` disables the surface (ADR-014 §4).
    metrics_listen: []const u8 = default_metrics_listen,
};

/// Cap on CLI worker seeds. Parse is pure (no allocator); the S4 runtime
/// pool can grow beyond this from FPKG_WORKERS.
pub const max_workers: usize = 16;

pub const Command = union(enum) {
    start: StartOptions,
    version,
    help,
};

pub const CliError = error{ UnknownSubcommand, UnknownOption, InvalidOption, MissingListen, TooManyWorkers };

pub const usage =
    \\Usage:
    \\
    \\  ingress start --listen=host:port --worker=host:port [--worker=...]
    \\                [--max-body=bytes] [--log-level=level]
    \\                [--log-format=text|json]
    \\                [--metrics-listen=host:port|off]
    \\
    \\  ingress version
    \\  ingress help
    \\
    \\Options:
    \\  --listen      host:port to bind for HTTP; port 0 picks an ephemeral
    \\                port, announced on stderr
    \\  --worker      worker pool seed (repeatable); workers are also read
    \\                from FPKG_WORKERS (comma-separated) when not given
    \\  --max-body    accepted POST body cap in bytes (default 1048576)
    \\  --log-level   log verbosity: debug|info|warn|error (default info)
    \\  --log-format  log encoding: text|json (default text)
    \\  --metrics-listen  metrics + readiness listener (default :9090); never
    \\                the HTTP port; `off` disables the surface
    \\
    \\Environment:
    \\  FPKG_WORKERS               comma-separated worker seeds (when no --worker)
    \\  FPKG_HMAC_SECRET           require request authentication: every POST must
    \\                             carry x-fpkg-collected-at, x-fpkg-nonce and
    \\                             x-fpkg-signature (hmac-sha256=...); secret is at
    \\                             least 32 characters. Unset = authentication off
    \\                             (the ingress trusts the network, D-v1-2).
    \\  FPKG_HMAC_SECRET_PREVIOUS  previous secret, accepted during rotation
    \\  FPKG_HMAC_WINDOW_MS        freshness/replay window in ms (default 300000)
    \\
;

/// Parses argv (including argv[0]) into a Command.
/// Pure: errors are returned to the caller, which owns the diagnostics.
pub fn parse(args: []const []const u8) CliError!Command {
    const subcommand = if (args.len > 1) args[1] else "help";
    if (std.mem.eql(u8, subcommand, "help") or
        std.mem.eql(u8, subcommand, "-h") or
        std.mem.eql(u8, subcommand, "--help"))
    {
        return .help;
    }
    if (std.mem.eql(u8, subcommand, "version")) return .version;
    if (!std.mem.eql(u8, subcommand, "start")) return error.UnknownSubcommand;

    var options = StartOptions{};
    for (args[2..]) |arg| {
        if (std.mem.startsWith(u8, arg, "--listen=")) {
            options.listen = arg["--listen=".len..];
        } else if (std.mem.startsWith(u8, arg, "--worker=")) {
            if (options.worker_count >= max_workers) return error.TooManyWorkers;
            options.workers[options.worker_count] = arg["--worker=".len..];
            options.worker_count += 1;
        } else if (std.mem.startsWith(u8, arg, "--max-body=")) {
            options.max_body = std.fmt.parseInt(u64, arg["--max-body=".len..], 10) catch
                return error.InvalidOption;
        } else if (std.mem.startsWith(u8, arg, "--log-level=")) {
            options.log_level = log.parseLevel(arg["--log-level=".len..]) orelse
                return error.InvalidOption;
        } else if (std.mem.startsWith(u8, arg, "--log-format=")) {
            options.log_format = log.parseFormat(arg["--log-format=".len..]) orelse
                return error.InvalidOption;
        } else if (std.mem.startsWith(u8, arg, "--metrics-listen=")) {
            const value = arg["--metrics-listen=".len..];
            if (value.len == 0) return error.InvalidOption;
            options.metrics_listen = value;
        } else return error.UnknownOption;
    }
    if (options.listen == null) return error.MissingListen;
    return .{ .start = options };
}

// ── Entry points ─────────────────────────────────────────────────────

/// Runs the ingress CLI against an argv slice that includes argv[0] (the
/// subcommand name, e.g. `"ingress"`). Shared by the standalone `ingress`
/// binary (`main`) and the combined `fingerprint` binary
/// (`src/cmd/main.zig` passes `args[1..]`). The caller owns the args
/// allocation.
pub fn run(alloc: std.mem.Allocator, args: []const []const u8) !void {
    const command = parse(args) catch |err| {
        const message: []const u8 = switch (err) {
            error.UnknownSubcommand => "unknown subcommand",
            error.UnknownOption => "unknown option",
            error.InvalidOption => "invalid option",
            error.MissingListen => "start requires --listen=host:port",
            error.TooManyWorkers => "too many --worker seeds",
        };
        log.ingress.err("ingress: {s}\n\n{s}", .{ message, usage });
        std.process.exit(1);
    };
    switch (command) {
        .help => try std.io.getStdOut().writer().writeAll(usage),
        .version => try std.io.getStdOut().writer().print("ingress version {s}\n", .{version}),
        .start => |options| try start(options, alloc),
    }
}

// ── HTTP server (S4-c/d) ─────────────────────────────────────────────

/// True when the peer is done sending; the accept loop treats these as a
/// clean disconnect rather than an error.
fn peerGone(err: anyerror) bool {
    return switch (err) {
        error.EndOfStream, error.ConnectionClosedByPeer, error.BrokenPipe => true,
        else => false,
    };
}

/// Reads an optional environment value, distinguishing "absent" from a real
/// failure so a broken environment is reported instead of silently disabling
/// authentication.
fn envValue(alloc: std.mem.Allocator, name: []const u8) !?[]u8 {
    return std.process.getEnvVarOwned(alloc, name) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => err,
    };
}

/// FPKG_HMAC_WINDOW_MS, defaulted and bounded. A zero/negative window would
/// reject everything, and an unbounded one would defeat the replay cache, so
/// the accepted range is one second to one hour.
fn hmacWindow(alloc: std.mem.Allocator) i64 {
    const raw = envValue(alloc, "FPKG_HMAC_WINDOW_MS") catch |err| {
        log.ingress.err("ingress: cannot read FPKG_HMAC_WINDOW_MS: {s}", .{@errorName(err)});
        std.process.exit(1);
    };
    defer if (raw) |value| alloc.free(value);
    const value = raw orelse return hmac.default_window_ms;
    const window_ms = std.fmt.parseInt(i64, std.mem.trim(u8, value, " "), 10) catch {
        log.ingress.err("ingress: FPKG_HMAC_WINDOW_MS must be an integer number of milliseconds", .{});
        std.process.exit(1);
    };
    if (window_ms < 1000 or window_ms > 60 * 60 * 1000) {
        log.ingress.err("ingress: FPKG_HMAC_WINDOW_MS must be between 1000 and 3600000", .{});
        std.process.exit(1);
    }
    return window_ms;
}

fn splitHostPort(listen: []const u8) !struct { []const u8, u16 } {
    // R-7: support IPv6 bracket notation "[::1]:8080" in addition to IPv4 "0.0.0.0:8080".
    if (listen.len > 0 and listen[0] == '[') {
        const close = std.mem.indexOfScalar(u8, listen, ']') orelse return error.InvalidListen;
        if (close + 1 >= listen.len or listen[close + 1] != ':') return error.InvalidListen;
        const host = listen[1..close];
        const port = try std.fmt.parseInt(u16, listen[close + 2 ..], 10);
        return .{ host, port };
    }
    const idx = std.mem.lastIndexOfScalar(u8, listen, ':') orelse return error.InvalidListen;
    const host = listen[0..idx];
    const port = try std.fmt.parseInt(u16, listen[idx + 1 ..], 10);
    return .{ host, port };
}

/// Starts the HTTP server: terminate POSTs, boundary-check, wrap in an FPKG
/// frame, forward to the pooled workers, relay the reply. Exits 0 on
/// SIGTERM/SIGINT after draining in-flight requests (H-2).
fn start(options: StartOptions, alloc: std.mem.Allocator) !void {
    // Logging config: CLI flags > FPKG_LOG_LEVEL/FPKG_LOG_FORMAT > defaults
    // (specs/architecture/logging.md). Applied before any message is logged.
    log.initFromEnv(alloc, options.log_level, options.log_format);

    const listen = options.listen orelse unreachable; // parse enforces
    const host, const listen_port = splitHostPort(listen) catch {
        log.ingress.err("ingress: invalid --listen '{s}' (expected host:port)", .{listen});
        std.process.exit(1);
    };

    // Worker seeds: --worker (repeatable) or FPKG_WORKERS (comma-separated)
    // for containerized deploys (specs/architecture/ingress.md).
    var worker_seeds: []const []const u8 = options.workers[0..options.worker_count];
    var env_value: ?[]u8 = null;
    defer if (env_value) |value| alloc.free(value);
    var env_items: ?[][]const u8 = null;
    defer if (env_items) |items| alloc.free(items);
    if (worker_seeds.len == 0) {
        if (std.process.getEnvVarOwned(alloc, "FPKG_WORKERS")) |env| {
            env_value = env;
            var list = std.ArrayList([]const u8).init(alloc);
            defer list.deinit();
            var it = std.mem.splitScalar(u8, env, ',');
            while (it.next()) |part| {
                const trimmed = std.mem.trim(u8, part, " ");
                if (trimmed.len > 0) try list.append(trimmed);
            }
            env_items = try list.toOwnedSlice();
            worker_seeds = env_items.?;
        } else |_| {}
    }
    if (worker_seeds.len == 0) {
        log.ingress.err("ingress: no workers (pass --worker=host:port or set FPKG_WORKERS)", .{});
        std.process.exit(1);
    }

    var workers = try pool.WorkerPool.init(alloc, worker_seeds);
    defer workers.deinit();

    // M7 W6-D3: request authentication. Off unless a secret is configured;
    // when it is, an unsigned/stale/replayed/forged POST is rejected before it
    // is wrapped into a frame, so the worker only ever sees authenticated
    // traffic. The secret values stay in this scope (the verifier borrows
    // them) and are never logged.
    const secret = envValue(alloc, "FPKG_HMAC_SECRET") catch |err| {
        log.ingress.err("ingress: cannot read FPKG_HMAC_SECRET: {s}", .{@errorName(err)});
        std.process.exit(1);
    };
    defer if (secret) |value| alloc.free(value);
    const previous_secret = envValue(alloc, "FPKG_HMAC_SECRET_PREVIOUS") catch |err| {
        log.ingress.err("ingress: cannot read FPKG_HMAC_SECRET_PREVIOUS: {s}", .{@errorName(err)});
        std.process.exit(1);
    };
    defer if (previous_secret) |value| alloc.free(value);

    var verifier: ?hmac.Verifier = null;
    defer if (verifier) |*active| active.deinit();
    if (secret) |value| {
        const window_ms = hmacWindow(alloc);
        verifier = hmac.Verifier.init(alloc, value, previous_secret, window_ms) catch |err| {
            log.ingress.err("ingress: invalid HMAC configuration: {s}", .{@errorName(err)});
            std.process.exit(1);
        };
        log.ingress.info("ingress: request authentication enabled (hmac-sha256, window {d} ms, {d} secret(s))", .{
            window_ms,
            verifier.?.secret_count,
        });
    } else {
        log.ingress.warn("ingress: request authentication disabled (set FPKG_HMAC_SECRET to require HMAC)", .{});
    }

    var registry = metrics.Metrics{};
    registry.replay_cache_capacity.set(if (verifier) |*active| @intCast(active.slots.len) else 0);
    // Warm the pool before the probe starts serving: the pool connects
    // lazily, so an ingress that has not seen traffic would otherwise report
    // "no reachable worker" forever and /readyz could not gate a rollout.
    registry.worker_pool_healthy.set(@intCast(workers.refresh(alloc, probe_timeout_ns, pool.idle_probe_after_ns)));

    var server = try http.HttpServer.init(
        alloc,
        host,
        listen_port,
        options.max_body,
        pool.read_timeout_ns,
        &workers,
    );
    defer server.deinit();
    if (verifier) |*active| server.hmac = active;
    server.metrics = &registry;

    // ADR-014 §4: metrics + probes live on a dedicated port, served by their
    // own thread so a stalled scraper can never touch the request loop. Bound
    // before the API port is announced, so a supervisor never sees a listening
    // ingress whose observability surface failed to bind.
    var scrape_server: ?obs.scrape.Server = null;
    defer if (scrape_server) |*scrape| scrape.stop();
    if (std.mem.eql(u8, options.metrics_listen, "off")) {
        log.ingress.info("ingress: metrics disabled (--metrics-listen=off)", .{});
    } else {
        const metrics_address = obs.scrape.parseAddress(alloc, options.metrics_listen) catch {
            log.ingress.err("ingress: invalid --metrics-listen '{s}' (expected host:port or off)", .{options.metrics_listen});
            std.process.exit(1);
        };
        scrape_server = obs.scrape.listen(.{
            .address = metrics_address,
            .component = "ingress",
            .version = version,
            .metrics_context = &registry,
            .render_metrics = renderMetrics,
            .ready_context = &registry,
            .is_ready = isReady,
        }) catch |err| {
            // A deployment that believes it has metrics but silently does not
            // is worse than a failed start.
            log.ingress.err("ingress: cannot bind --metrics-listen '{s}': {s}", .{
                options.metrics_listen,
                @errorName(err),
            });
            std.process.exit(1);
        };
        if (scrape_server) |*scrape| {
            scrape.start() catch |err| {
                log.ingress.err("ingress: cannot start the metrics listener: {s}", .{@errorName(err)});
                std.process.exit(1);
            };
            log.ingress.info("ingress: metrics listening on port {d} (bind {s})", .{
                scrape.port(),
                options.metrics_listen,
            });
        }
    }

    // Announce the bound address so supervisors and tests can learn the
    // ephemeral port (--listen=...:0). The `ingress: listening on `
    // substring is an integration-test contract; --log-level=err suppresses
    // the line on purpose (specs/architecture/logging.md).
    log.ingress.info("ingress: listening on {s}:{d}", .{ host, server.port() });

    // H-2: acceptWait bounds the accept so the loop observes the shutdown
    // flag while idle. In-flight requests complete synchronously before the
    // loop exits; deinit closes the pool connections.
    //
    // Readiness (ADR-014 §5) is a cached gauge, not a live probe: only this
    // thread may touch the pool, and the scrape thread reads the atomic. Every
    // idle tick re-probes: reconnect missing slots and drop-and-reconnect
    // slots idle past the TTL, because a socket to a worker that died while
    // connected still looks live. That bounds /readyz staleness to roughly the
    // TTL plus one tick instead of "until the next request fails".
    var idle_ticks: u32 = 0;
    const health_refresh_interval: u32 = 8; // ~2s at accept_poll_ms
    while (!shutdown_requested.load(.acquire)) {
        if (!try server.acceptWait(accept_poll_ms)) {
            idle_ticks += 1;
            if (idle_ticks >= health_refresh_interval) {
                idle_ticks = 0;
                registry.worker_pool_healthy.set(@intCast(workers.refresh(
                    alloc,
                    probe_timeout_ns,
                    pool.idle_probe_after_ns,
                )));
            }
            continue;
        }
        idle_ticks = 0;
        server.handleConnection(alloc) catch |err| {
            if (!peerGone(err)) {
                // Protocol errors (malformed HTTP, bad magic, ...) are
                // per-connection: close the client and keep serving. A single
                // bad client must never take down the ingress.
                log.ingress.warn("ingress: client dropped: {s}", .{@errorName(err)});
            }
        };
        log.ingress.debug("ingress: connection closed", .{});
        registry.worker_pool_healthy.set(@intCast(workers.liveCount()));
        // HTTP/1.1 `connection: close` — the reply is complete; drop the
        // client now instead of waiting for the next accept.
        server.closeClient();
    }
}

/// Scrape callback: renders the ingress registry (ADR-014). The registry is
/// atomic, so this runs on the scrape thread without locking.
fn renderMetrics(context: *anyopaque, writer: std.io.AnyWriter) anyerror!void {
    const registry: *const metrics.Metrics = @ptrCast(@alignCast(context));
    try metrics.render(registry, writer);
}

/// Readiness callback: the ingress can serve when at least one worker slot
/// holds a live connection. Reads the cached gauge, never the pool.
fn isReady(context: *anyopaque) ?[]const u8 {
    const registry: *const metrics.Metrics = @ptrCast(@alignCast(context));
    return if (registry.worker_pool_healthy.get() > 0) null else "worker_pool";
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    // H-2: SIGTERM/SIGINT (POSIX) and Ctrl+C/Ctrl+Break (Windows) set the
    // shared shutdown flag; the accept loop drains and exits 0.
    installShutdownHandlers();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    try run(alloc, args);
}
