# Zoi

Zoi is an HTTP server template written in Zig that depends only on the standard library. It is not a library — it is a starting point for building your own Zig server. Clone it, edit `src/routes.zig`, and go.

## Philosophy

Most web frameworks are built around the assumption that you should not have to think about the server. Zoi takes the opposite position: the server is simple enough that you should just own it.

Rather than hiding routing, request parsing, and memory management behind a versioned API, Zoi gives you a small, readable codebase that you can read in an afternoon and modify freely. There is no framework to update, no breaking changes to absorb, and no behavior you cannot inspect. When something does not work the way you want, you fix it directly rather than waiting for an upstream maintainer.

The entire implementation — routing, middleware, static files, templating, JSON parsing, cookie handling, and JWT verification — fits in a handful of files totalling a few hundred lines. Every piece of functionality is there because a server will likely need it.

On the technical side, Zig's comptime type system lets the parser accept any struct type at the call site without runtime reflection or code generation. Each request is handled inside an arena allocator that is reset between requests, which means memory management is handled structurally rather than requiring individual frees in handler code. Connections are managed through an async queue — an acceptor task feeds incoming connections to a pool of worker tasks via `std.Io.Queue`, and keep-alive connections are requeued after each request rather than pinned to a single worker.

## Production Readiness

Zoi has been running in production for over a year. Zoi's site is self-hosted, and benchmarks show Zoi can sustain over 16,000 requests per second on commodity hardware. That is well above the throughput of an equivalent Bun server on the same machine. See the [performance writeup](https://github.com/AndrewGossage/Thanatos/blob/main/pages/sql.html) for the full breakdown.

The architecture is straightforward under load: an acceptor task feeds incoming connections into a bounded `std.Io.Queue`, worker tasks drain the queue concurrently, and keep-alive connections are requeued after each request. Each worker uses an arena allocator that resets between requests, and the router is a simple linear scan with no heap allocation per match. There is no runtime, no garbage collector, and no framework overhead.

Two things to know before deploying:

- **No TLS.** Zoi does not terminate HTTPS. Run it behind nginx, Caddy, or any TLS-terminating proxy — the same setup you would use for any backend.
- **Zig is pre-1.0.** The language and standard library are still evolving. Zig updates almost always require changes to the server code. Because you own the code rather than depending on a versioned package, those changes are yours to make on your own schedule. Zoi tracks the current stable version of Zig.

## Requirements

- Zig 0.16

## Getting Started

```sh
git clone https://github.com/AndrewGossage/Zoi
cd Zoi
zig build run
```

The server will start on the address and port configured in `config.json`.

## Project Structure

```
src/
  main.zig    — entry point, wires config and routes together
  routes.zig  — define your routes here
  server.zig  — core server, router, and parser
  config.zig  — loads config.json
  fmt.zig     — template rendering
  auth.zig    — JWT verification utilities
static/       — static files served by the built-in static handler
config.json   — server configuration
```

## Configuration

`config.json` controls the server:

```json
{
    "address": "127.0.0.1",
    "port": "8081",
    "workers": 3
}
```

| Field     | Description                          | Default |
|-----------|--------------------------------------|---------|
| `address` | Bind address                         | —       |
| `port`    | Port to listen on                    | —       |
| `workers` | Number of async worker tasks         | `1`     |

## Routing

Routes are defined in `src/routes.zig` as a slice of `Route` structs.

```zig
pub const routes = &[_]server.Route{
    .{ .path = "/",              .callback = index },
    .{ .path = "/static/*",     .callback = server.static },
    .{ .path = "/:param",       .callback = param_test },
    .{ .path = "/api/:endpoint", .method = .POST, .callback = postEndpoint },
};
```

- **`:name`** — matches a single path segment and makes it available via `Parser.params`
- **`*`** — wildcard, matches the rest of the path (use for static file routes)
- **`method`** — defaults to `.GET`; set to any `std.http.Method` value

### Middleware

Routes can have a middleware chain that runs before the main callback. Middleware receives the same `Context` and can store values for the handler using `c.put`.

```zig
.{ .path = "/", .middleware = &[_]Callback{ auth_check }, .callback = index }
```

```zig
fn auth_check(c: *Context) !void {
    try c.put("user", "alice");
}

fn index(c: *Context) !void {
    const user = c.get("user").?;
    // ...
}
```

## Parsing

`server.Parser` provides helpers for extracting data from requests.

### URL Parameters

```zig
const Params = struct { id: []const u8 };
const p = try server.Parser.params(Params, c);
```

### Query String

```zig
const Query = struct { value: ?[]const u8 };
const q = server.Parser.query(Query, c.allocator, c.request);
```

### JSON Body

```zig
const Body = struct { name: []const u8 };
const body = try server.Parser.json(Body, c.allocator, c.request);
```

### Cookies

```zig
var cookies = try server.Parser.parseCookies(c.allocator, c.request);
const token = cookies.get("session");
```

### URL Decoding

```zig
const decoded = try server.Parser.urlDecode(raw, c.allocator);
```

## Sending Responses

```zig
// Plain response — c.keep_alive is set automatically based on the request and server load
try c.request.respond(body, .{ .status = .ok, .keep_alive = c.keep_alive });

// JSON response
const headers = &[_]std.http.Header{
    .{ .name = "Content-Type", .value = "application/json" },
};
try server.sendJson(c.allocator, c.request, my_struct, .{
    .status = .ok,
    .keep_alive = c.keep_alive,
    .extra_headers = headers,
});
```

## Templating

`fmt.renderTemplate` reads an HTML file and replaces `$field$` placeholders with values from an anonymous struct.

```zig
const body = try fmt.renderTemplate(c.io, "./static/index.html", .{
    .username = "alice",
    .title = "Dashboard",
}, c.allocator);
defer c.allocator.free(body);
```

In your HTML:
```html
<h1>Welcome, $username$</h1>
<title>$title$</title>
```

## Static Files

Use `server.static` as the callback on any route ending with `*`. Files are served from the current working directory, and dotfiles are blocked by default.

```zig
.{ .path = "/static/*", .callback = server.static }
```

A request to `/static/styles/main.css` will serve `static/styles/main.css`. If the path has no extension, `index.html` is appended automatically.

## Authentication

`auth.zig` provides JWT verification using HMAC-SHA256. Set the `JWT_SECRET` environment variable and call `auth.decodeAuth` to verify and decode a token from a cookie value.

```zig
const claims = try auth.decodeAuth(c.allocator, token);
```

## Example Project

[Thanatos](https://github.com/AndrewGossage/Thanatos) demonstrates using Zoi as a lightweight alternative to Tauri or Electron for desktop applications.
