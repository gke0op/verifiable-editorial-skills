//! Rule 11 — Clickable PDF Resource Link & Live Anti-Hallucination Auditor (`vedit links`).
//! Mirrors `verifiable_editorial/links.py` 1:1 in sovereign bare-metal Zig 0.17.0:
//!   1. Extracts every clickable `/Subtype /Link` `/URI` annotation (rejecting degenerate <2x2pt or off-page rects
//!      and malformed/placeholder/local domains).
//!   2. Scans rendered PDF text for plain-text URLs and DOIs (`Rule 11A`: every printed URL/DOI must be clickable).
//!   3. Cross-checks declared resource URLs/DOIs in `background_citations.json` and `provenance_ledger.json`
//!      (`Rule 11B`: every declared resource must appear as a clickable link in the PDF).
//!   4. Resolves every unique clickable link LIVE before finalization (`Rule 11C`):
//!      - Academic/dataset DOIs (incl. `doi.org`, `nature.com/articles/`, `aps.org`, etc.) via the
//!        authoritative CNRI/IDF DOI Handle Registry (`https://doi.org/api/handles/<doi>`).
//!      - Open-science portals (`gbif.org/species/<id>`, `inaturalist.org/taxa/<id>`) via public REST APIs.
//!      - General web URLs via live HTTP GET inspecting HTTP status, `<title>`, and `<h1>` to reject
//!        404/410/403/5xx, DNS/TLS errors, Soft-404 pages, and HTTP-200 bot-challenge interstitials.

const std = @import("std");
const mupdf = @import("mupdf.zig");

pub const LinkFailure = struct {
    page: usize,
    kind: []const u8,
    uri: []const u8,
    detail: []const u8,
};

pub const LiveLinkResult = struct {
    uri: []const u8,
    method: []const u8,
    status: i32,
    final_url: []const u8,
    title: []const u8,
    verdict: []const u8,
    passed: bool,
};

pub const LinksReport = struct {
    pages: usize,
    clickable_links: usize,
    unique_uris: usize,
    text_resources: usize,
    declared_resources: usize,
    live_checked: bool,
    live_results: []const LiveLinkResult,
    failures: []const LinkFailure,
    passed: bool,
};

fn isAsciiAlnum(ch: u8) bool {
    return (ch >= 'A' and ch <= 'Z') or (ch >= 'a' and ch <= 'z') or (ch >= '0' and ch <= '9');
}

fn containsFold(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[i .. i + needle.len], needle)) return true;
    }
    return false;
}

fn endsWithFold(haystack: []const u8, suffix: []const u8) bool {
    if (suffix.len > haystack.len) return false;
    return std.ascii.eqlIgnoreCase(haystack[haystack.len - suffix.len ..], suffix);
}

fn startsWithFold(haystack: []const u8, prefix: []const u8) bool {
    if (prefix.len > haystack.len) return false;
    return std.ascii.eqlIgnoreCase(haystack[0..prefix.len], prefix);
}

pub fn stripTrailingPunct(raw: []const u8) []const u8 {
    var s = std.mem.trim(u8, raw, " \t\r\n");
    while (s.len > 0) {
        const last = s[s.len - 1];
        if (last == '.' or last == ',' or last == ';' or last == ':' or last == '!' or last == '?' or last == '\'' or last == '"') {
            s = s[0 .. s.len - 1];
            continue;
        }
        if (last == ')') {
            var opens: usize = 0;
            var closes: usize = 0;
            for (s) |c| {
                if (c == '(') opens += 1 else if (c == ')') closes += 1;
            }
            if (closes > opens) {
                s = s[0 .. s.len - 1];
                continue;
            }
        }
        if (last == ']') {
            var opens: usize = 0;
            var closes: usize = 0;
            for (s) |c| {
                if (c == '[') opens += 1 else if (c == ']') closes += 1;
            }
            if (closes > opens) {
                s = s[0 .. s.len - 1];
                continue;
            }
        }
        break;
    }
    return s;
}

const ParsedHostPath = struct {
    scheme: []const u8,
    host: []const u8,
    host_port: []const u8,
    path: []const u8,
};

fn splitUrl(uri: []const u8) ?ParsedHostPath {
    const sep = std.mem.find(u8, uri, "://") orelse return null;
    const scheme = uri[0..sep];
    const rest = uri[sep + 3 ..];
    const path_start = std.mem.findAny(u8, rest, "/?#") orelse rest.len;
    const authority = rest[0..path_start];
    const at_pos = std.mem.findScalarLast(u8, authority, '@');
    const host_port = if (at_pos) |a| authority[a + 1 ..] else authority;
    if (host_port.len == 0) return null;
    const host = if (host_port[0] == '[') blk: {
        const rb = std.mem.findScalar(u8, host_port, ']') orelse return null;
        break :blk host_port[0 .. rb + 1];
    } else if (std.mem.findScalar(u8, host_port, ':')) |col|
        host_port[0..col]
    else
        host_port;
    const path = if (path_start < rest.len and rest[path_start] == '/') rest[path_start..] else "";
    return .{ .scheme = scheme, .host = host, .host_port = host_port, .path = path };
}

fn looksLikeDoi(s: []const u8) bool {
    if (!std.mem.startsWith(u8, s, "10.")) return false;
    var k: usize = 3;
    while (k < s.len and s[k] >= '0' and s[k] <= '9') : (k += 1) {}
    return (k - 3 >= 4) and (k - 3 <= 9) and k + 1 < s.len and s[k] == '/' and isUrlBodyChar(s[k + 1]);
}

/// Extract canonical DOI (`10.xxxx/...`) from bare DOI, `doi.org`, `nature.com/articles/`, or publisher DOI paths.
pub fn extractDoiFromUri(alloc: std.mem.Allocator, uri_raw: []const u8) !?[]u8 {
    const u = stripTrailingPunct(uri_raw);
    if (startsWithFold(u, "doi:")) {
        const rest = std.mem.trimStart(u8, u[4..], " \t");
        if (looksLikeDoi(rest)) return try alloc.dupe(u8, rest);
    }
    if (looksLikeDoi(u)) return try alloc.dupe(u8, u);

    const hp = splitUrl(u) orelse return null;
    const path_only = blk: {
        const q = std.mem.findAny(u8, hp.path, "?#") orelse hp.path.len;
        break :blk std.mem.trimStart(u8, hp.path[0..q], "/");
    };

    if (std.ascii.eqlIgnoreCase(hp.host, "doi.org") or
        std.ascii.eqlIgnoreCase(hp.host, "www.doi.org") or
        std.ascii.eqlIgnoreCase(hp.host, "dx.doi.org"))
    {
        if (looksLikeDoi(path_only)) return try alloc.dupe(u8, path_only);
    }

    if ((std.ascii.eqlIgnoreCase(hp.host, "nature.com") or std.ascii.eqlIgnoreCase(hp.host, "www.nature.com")) and
        std.mem.startsWith(u8, path_only, "articles/"))
    {
        const after = path_only["articles/".len..];
        const slash = std.mem.findScalar(u8, after, '/') orelse after.len;
        const slug = after[0..slash];
        if (slug.len > 0) {
            return try std.fmt.allocPrint(alloc, "10.1038/{s}", .{slug});
        }
    }

    const pub_hosts = [_][]const u8{
        "aps.org",      "science.org", "wiley.com", "acs.org", "tandfonline.com",
        "springer.com", "sagepub.com", "iop.org",   "oup.com",
    };
    var is_pub = false;
    for (pub_hosts) |ph| {
        if (containsFold(hp.host, ph)) {
            is_pub = true;
            break;
        }
    }
    if (is_pub) {
        var pos: usize = 0;
        while (std.mem.findPos(u8, path_only, pos, "10.")) |idx| {
            if ((idx == 0 or path_only[idx - 1] == '/') and looksLikeDoi(path_only[idx..])) {
                return try alloc.dupe(u8, path_only[idx..]);
            }
            pos = idx + 3;
        }
    }
    return null;
}

pub fn canonicalKey(alloc: std.mem.Allocator, raw: []const u8) ![]u8 {
    const s = stripTrailingPunct(raw);
    if (try extractDoiFromUri(alloc, s)) |doi| {
        defer alloc.free(doi);
        var out = try alloc.alloc(u8, 4 + doi.len);
        @memcpy(out[0..4], "doi:");
        for (doi, 0..) |ch, idx| out[4 + idx] = std.ascii.toLower(ch);
        return out;
    }
    if (splitUrl(s)) |hp| {
        const rest_after_host = blk: {
            const sep = std.mem.find(u8, s, "://").?;
            const after = s[sep + 3 ..];
            const pstart = std.mem.findAny(u8, after, "/?#") orelse after.len;
            break :blk after[pstart..];
        };
        const trimmed_rest = std.mem.trimEnd(u8, rest_after_host, "/");
        var out: std.ArrayList(u8) = .empty;
        for (hp.scheme) |ch| try out.append(alloc, std.ascii.toLower(ch));
        try out.appendSlice(alloc, "://");
        for (hp.host_port) |ch| try out.append(alloc, std.ascii.toLower(ch));
        try out.appendSlice(alloc, trimmed_rest);
        return out.toOwnedSlice(alloc);
    }
    var out = try alloc.alloc(u8, s.len);
    for (s, 0..) |ch, idx| out[idx] = std.ascii.toLower(ch);
    return out;
}

pub fn validateUriSyntax(uri: []const u8, allow_localhost: bool) ?[]const u8 {
    if (uri.len == 0) return "INVALID_URI_WHITESPACE_OR_EMPTY";
    for (uri) |ch| {
        if (ch <= 32) return "INVALID_URI_WHITESPACE_OR_EMPTY";
    }
    const hp = splitUrl(uri) orelse return "DISALLOWED_SCHEME";
    if (!std.ascii.eqlIgnoreCase(hp.scheme, "http") and !std.ascii.eqlIgnoreCase(hp.scheme, "https")) {
        return "DISALLOWED_SCHEME";
    }
    if (hp.host.len == 0) return "MISSING_HOST";

    const local_hosts = [_][]const u8{ "localhost", "127.0.0.1", "0.0.0.0", "::1", "[::1]" };
    for (local_hosts) |lh| {
        if (std.ascii.eqlIgnoreCase(hp.host, lh)) {
            return if (allow_localhost) null else "LOCALHOST_URI_DISALLOWED";
        }
    }

    const ph_hosts = [_][]const u8{
        "example.com",    "www.example.com", "example.org",     "www.example.org",
        "example.net",    "www.example.net", "foo.bar",         "your-domain.com",
        "yourdomain.com", "placeholder.com", "placeholder.org",
    };
    for (ph_hosts) |ph| {
        if (std.ascii.eqlIgnoreCase(hp.host, ph)) return "PLACEHOLDER_HOST";
    }
    const ph_tlds = [_][]const u8{ ".invalid", ".test", ".local", ".example", ".localhost" };
    for (ph_tlds) |tld| {
        if (endsWithFold(hp.host, tld)) return "PLACEHOLDER_HOST";
    }
    if (std.mem.findScalar(u8, hp.host, '.') == null) return "INVALID_HOST_NO_DOT";

    const ph_tokens = [_][]const u8{ "placeholder", "todo", "tbd", "insert-url", "your-link" };
    for (ph_tokens) |tok| {
        if (containsFold(hp.host, tok)) return "PLACEHOLDER_URI";
        var sl_buf: [32]u8 = undefined;
        const sl_tok = std.fmt.bufPrint(&sl_buf, "/{s}", .{tok}) catch continue;
        if (containsFold(uri, sl_tok)) return "PLACEHOLDER_URI";
    }
    return null;
}

fn extractTagInner(alloc: std.mem.Allocator, html_body: []const u8, open_prefix: []const u8, close_tag: []const u8) ![]u8 {
    var i: usize = 0;
    while (i + open_prefix.len < html_body.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(html_body[i .. i + open_prefix.len], open_prefix)) {
            const gt = std.mem.findScalarPos(u8, html_body, i + open_prefix.len, '>') orelse return try alloc.dupe(u8, "");
            var j = gt + 1;
            var end_pos: ?usize = null;
            while (j + close_tag.len <= html_body.len) : (j += 1) {
                if (std.ascii.eqlIgnoreCase(html_body[j .. j + close_tag.len], close_tag)) {
                    end_pos = j;
                    break;
                }
            }
            const raw = html_body[gt + 1 .. (end_pos orelse @min(html_body.len, gt + 1 + 256))];
            var out: std.ArrayList(u8) = .empty;
            var in_tag = false;
            var prev_ws = true;
            for (raw) |ch| {
                if (ch == '<') {
                    in_tag = true;
                    continue;
                }
                if (ch == '>') {
                    in_tag = false;
                    continue;
                }
                if (in_tag) continue;
                if (ch <= 32) {
                    if (!prev_ws) {
                        try out.append(alloc, ' ');
                        prev_ws = true;
                    }
                } else {
                    try out.append(alloc, ch);
                    prev_ws = false;
                }
                if (out.items.len >= 140) break;
            }
            const trimmed = std.mem.trim(u8, out.items, " ");
            const res = try alloc.dupe(u8, trimmed);
            out.deinit(alloc);
            return res;
        }
    }
    return try alloc.dupe(u8, "");
}

pub fn classifySoft404OrChallenge(title: []const u8, h1: []const u8, body: []const u8) ?[]const u8 {
    const bot_pats = [_][]const u8{
        "client challenge",        "just a moment",                             "attention required",
        "verify you are human",    "are you a robot",                           "bot detection",
        "pardon our interruption", "ddos-guard",                                "security check",
        "access denied",           "enable javascript and cookies to continue",
    };
    for (bot_pats) |pat| {
        if (containsFold(title, pat) or containsFold(h1, pat)) return "BOT_CHALLENGE_UNVERIFIED";
    }
    const sample = body[0..@min(body.len, 4096)];
    if (containsFold(sample, "cf-browser-verification") or
        containsFold(sample, "challenge-platform") or
        containsFold(sample, "window._cf_chl_opt"))
    {
        return "BOT_CHALLENGE_UNVERIFIED";
    }
    const s404_pats = [_][]const u8{
        "404 not found",           "error 404",                "404 error",
        "404 -",                   "404 |",                    "page not found",
        "article not found",       "document not found",       "doi not found",
        "file not found",          "resource not found",       "record not found",
        "cannot be found",         "could not be found",       "couldn't be found",
        "this page doesn't exist", "this page does not exist", "page does not exist",
        "no longer available",     "broken link",
    };
    for (s404_pats) |pat| {
        if (containsFold(title, pat) or containsFold(h1, pat)) return "SOFT_404_HALLUCINATED";
    }
    return null;
}

const HttpResponse = struct {
    status: i32,
    final_url: []const u8,
    body: []const u8,
    err_kind: ?[]const u8,
};

fn httpGetText(alloc: std.mem.Allocator, io: std.Io, url: []const u8, timeout_secs: u32) !HttpResponse {
    const t_str = try std.fmt.allocPrint(alloc, "{d}", .{timeout_secs});
    const marker = "\n__VEDIT_HTTP__:";
    const res = std.process.run(alloc, io, .{
        .argv = &.{
            "curl",
            "-sS",
            "-L",
            "--max-redirs",
            "8",
            "--connect-timeout",
            t_str,
            "--max-time",
            t_str,
            "-A",
            "Mozilla/5.0 (compatible; verifiable-editorial-vedit/0.6)",
            "-H",
            "Accept: text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8",
            "-w",
            "\n__VEDIT_HTTP__:%{http_code}\t%{url_effective}",
            url,
        },
        .stdout_limit = .limited(8 * 1024 * 1024),
        .stderr_limit = .limited(65536),
    }) catch |err| {
        if (err == error.FileNotFound) {
            // Pure-Zig std.http.Client fallback for minimal containers without curl
            var client: std.http.Client = .{ .allocator = alloc, .io = io };
            defer client.deinit();
            var body_w: std.Io.Writer.Allocating = .init(alloc);
            const fres = client.fetch(.{
                .location = .{ .url = url },
                .response_writer = &body_w.writer,
            }) catch {
                return .{ .status = -1, .final_url = url, .body = "", .err_kind = "UNREACHABLE_OR_HALLUCINATED" };
            };
            const st: i32 = @backingInt(fres.status);
            const raw_b = body_w.written();
            const cap_b = raw_b[0..@min(raw_b.len, 65536)];
            return .{
                .status = st,
                .final_url = url,
                .body = try alloc.dupe(u8, cap_b),
                .err_kind = if (st >= 200 and st <= 299) null else try std.fmt.allocPrint(alloc, "HTTP_{d}", .{st}),
            };
        }
        return .{ .status = -1, .final_url = url, .body = "", .err_kind = "UNREACHABLE_OR_HALLUCINATED" };
    };

    const code: u8 = switch (res.term) {
        .exited => |c| c,
        else => 255,
    };
    const mpos = std.mem.findLast(u8, res.stdout, marker) orelse {
        return .{ .status = -1, .final_url = url, .body = "", .err_kind = "UNREACHABLE_OR_HALLUCINATED" };
    };
    const raw_body = res.stdout[0..@min(mpos, 65536)];
    const meta = std.mem.trim(u8, res.stdout[mpos + marker.len ..], " \t\r\n");
    const tab = std.mem.findScalar(u8, meta, '\t') orelse meta.len;
    const status = std.fmt.parseInt(i32, meta[0..tab], 10) catch -1;
    const eff_url = if (tab + 1 < meta.len) meta[tab + 1 ..] else url;
    if (code != 0 or status <= 0) {
        return .{ .status = status, .final_url = eff_url, .body = raw_body, .err_kind = "UNREACHABLE_OR_HALLUCINATED" };
    }
    return .{
        .status = status,
        .final_url = eff_url,
        .body = raw_body,
        .err_kind = if (status >= 200 and status <= 299) null else try std.fmt.allocPrint(alloc, "HTTP_{d}", .{status}),
    };
}

fn extractDigitsAfterPrefix(path: []const u8, prefix: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, path, prefix)) return null;
    const rest = path[prefix.len..];
    var k: usize = 0;
    while (k < rest.len and rest[k] >= '0' and rest[k] <= '9') : (k += 1) {}
    if (k == 0) return null;
    if (k < rest.len and rest[k] != '/' and rest[k] != '-' and rest[k] != '?') return null;
    return rest[0..k];
}

fn verifyLiveUri(alloc: std.mem.Allocator, io: std.Io, uri: []const u8, timeout_secs: u32) !LiveLinkResult {
    // 1. Authoritative CNRI/IDF DOI Handle Registry
    if (try extractDoiFromUri(alloc, uri)) |doi| {
        const handle_url = try std.fmt.allocPrint(alloc, "https://doi.org/api/handles/{s}", .{doi});
        const resp = try httpGetText(alloc, io, handle_url, timeout_secs);
        if (resp.status == 200) {
            const parsed = std.json.parseFromSliceLeaky(std.json.Value, alloc, resp.body, .{}) catch null;
            if (parsed) |pv| {
                if (pv == .object) {
                    const rc_ok = if (pv.object.get("responseCode")) |rc| (rc == .integer and rc.integer == 1) else false;
                    if (rc_ok) {
                        var target: []const u8 = uri;
                        if (pv.object.get("values")) |vv| {
                            if (vv == .array) {
                                for (vv.array.items) |it| {
                                    if (it != .object) continue;
                                    const tval = it.object.get("type") orelse continue;
                                    if (tval == .string and std.mem.eql(u8, tval.string, "URL")) {
                                        if (it.object.get("data")) |dv| {
                                            if (dv == .object) {
                                                if (dv.object.get("value")) |uv| {
                                                    if (uv == .string) {
                                                        target = uv.string;
                                                        break;
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        return .{
                            .uri = uri,
                            .method = "doi_handle_api",
                            .status = 200,
                            .final_url = target,
                            .title = try std.fmt.allocPrint(alloc, "DOI {s}", .{doi}),
                            .verdict = "VERIFIED_DOI",
                            .passed = true,
                        };
                    }
                }
            }
            return .{
                .uri = uri,
                .method = "doi_handle_api",
                .status = resp.status,
                .final_url = handle_url,
                .title = "",
                .verdict = "HALLUCINATED_DOI",
                .passed = false,
            };
        }
        if (resp.status == 404) {
            return .{
                .uri = uri,
                .method = "doi_handle_api",
                .status = 404,
                .final_url = handle_url,
                .title = "",
                .verdict = "HALLUCINATED_DOI:handle_not_found_404",
                .passed = false,
            };
        }
    }

    // 2. Open-Science REST APIs (GBIF / iNaturalist)
    if (splitUrl(uri)) |hp| {
        if (std.ascii.eqlIgnoreCase(hp.host, "gbif.org") or std.ascii.eqlIgnoreCase(hp.host, "www.gbif.org")) {
            if (extractDigitsAfterPrefix(hp.path, "/species/")) |sp_id| {
                const api_url = try std.fmt.allocPrint(alloc, "https://api.gbif.org/v1/species/{s}", .{sp_id});
                const resp = try httpGetText(alloc, io, api_url, timeout_secs);
                if (resp.status == 200) {
                    var sci: []const u8 = try std.fmt.allocPrint(alloc, "GBIF:{s}", .{sp_id});
                    if (std.json.parseFromSliceLeaky(std.json.Value, alloc, resp.body, .{})) |pv| {
                        if (pv == .object) {
                            if (pv.object.get("scientificName")) |sv| if (sv == .string) {
                                sci = sv.string;
                            };
                        }
                    } else |_| {}
                    return .{
                        .uri = uri,
                        .method = "gbif_api",
                        .status = 200,
                        .final_url = api_url,
                        .title = sci,
                        .verdict = "VERIFIED_API",
                        .passed = true,
                    };
                }
                return .{
                    .uri = uri,
                    .method = "gbif_api",
                    .status = resp.status,
                    .final_url = api_url,
                    .title = "",
                    .verdict = resp.err_kind orelse "HALLUCINATED_GBIF_TAXON",
                    .passed = false,
                };
            }
        }
        if (std.ascii.eqlIgnoreCase(hp.host, "inaturalist.org") or std.ascii.eqlIgnoreCase(hp.host, "www.inaturalist.org")) {
            if (extractDigitsAfterPrefix(hp.path, "/taxa/")) |tx_id| {
                const api_url = try std.fmt.allocPrint(alloc, "https://api.inaturalist.org/v1/taxa/{s}", .{tx_id});
                const resp = try httpGetText(alloc, io, api_url, timeout_secs);
                if (resp.status == 200 and std.mem.find(u8, resp.body, "\"total_results\":1") != null) {
                    return .{
                        .uri = uri,
                        .method = "inat_api",
                        .status = 200,
                        .final_url = api_url,
                        .title = try std.fmt.allocPrint(alloc, "iNat:{s}", .{tx_id}),
                        .verdict = "VERIFIED_API",
                        .passed = true,
                    };
                }
                return .{
                    .uri = uri,
                    .method = "inat_api",
                    .status = resp.status,
                    .final_url = api_url,
                    .title = "",
                    .verdict = resp.err_kind orelse "HALLUCINATED_INAT_TAXON",
                    .passed = false,
                };
            }
        }
    }

    // 3. Direct live HTTP GET with Soft-404 & Bot-Challenge checks
    const resp = try httpGetText(alloc, io, uri, timeout_secs);
    const title = try extractTagInner(alloc, resp.body, "<title", "</title>");
    const h1 = try extractTagInner(alloc, resp.body, "<h1", "</h1>");
    if (resp.err_kind != null or resp.status < 200 or resp.status > 299) {
        return .{
            .uri = uri,
            .method = "http_get",
            .status = resp.status,
            .final_url = resp.final_url,
            .title = title,
            .verdict = resp.err_kind orelse "HTTP_ERROR",
            .passed = false,
        };
    }
    if (classifySoft404OrChallenge(title, h1, resp.body)) |trap| {
        return .{
            .uri = uri,
            .method = "http_get",
            .status = resp.status,
            .final_url = resp.final_url,
            .title = if (title.len > 0) title else h1,
            .verdict = trap,
            .passed = false,
        };
    }
    return .{
        .uri = uri,
        .method = "http_get",
        .status = resp.status,
        .final_url = resp.final_url,
        .title = if (title.len > 0) title else if (h1.len > 0) h1 else "(verified 200 OK)",
        .verdict = "VERIFIED_HTTP",
        .passed = true,
    };
}

fn collectDeclaredUrls(alloc: std.mem.Allocator, val: std.json.Value, out: *std.ArrayList([]const u8)) !void {
    switch (val) {
        .object => |obj| {
            var it = obj.iterator();
            while (it.next()) |ent| {
                const k = ent.key_ptr.*;
                if ((std.mem.eql(u8, k, "doi_or_url") or std.mem.eql(u8, k, "source_url") or
                    std.mem.eql(u8, k, "url") or std.mem.eql(u8, k, "href")) and ent.value_ptr.* == .string)
                {
                    const s = stripTrailingPunct(ent.value_ptr.*.string);
                    if (startsWithFold(s, "http://") or startsWithFold(s, "https://") or startsWithFold(s, "doi:") or looksLikeDoi(s)) {
                        try out.append(alloc, try alloc.dupe(u8, s));
                    }
                } else {
                    try collectDeclaredUrls(alloc, ent.value_ptr.*, out);
                }
            }
        },
        .array => |arr| {
            for (arr.items) |it| try collectDeclaredUrls(alloc, it, out);
        },
        else => {},
    }
}

fn isUrlBodyChar(ch: u8) bool {
    return ch > 32 and ch != '<' and ch != '>' and ch != '"' and ch != '\'' and ch != '[' and ch != ']';
}

const TextRes = struct { page: usize, raw: []const u8, canonical: []const u8 };

fn scanTextResources(alloc: std.mem.Allocator, page_num: usize, raw_in: []const u8, out: *std.ArrayList(TextRes)) !void {
    // Strip UTF-8 soft hyphens (U+00AD) first
    var norm: std.ArrayList(u8) = .empty;
    defer norm.deinit(alloc);
    var ni: usize = 0;
    while (ni < raw_in.len) {
        if (ni + 1 < raw_in.len and raw_in[ni] == 0xC2 and raw_in[ni + 1] == 0xAD) {
            ni += 2;
            continue;
        }
        try norm.append(alloc, raw_in[ni]);
        ni += 1;
    }
    const text = norm.items;
    var seen = std.StringHashMap(void).init(alloc);
    defer seen.deinit();

    var i: usize = 0;
    while (i < text.len) {
        if (startsWithFold(text[i..], "http://") or startsWithFold(text[i..], "https://")) {
            var k = i;
            while (k < text.len and isUrlBodyChar(text[k])) : (k += 1) {}
            const u = stripTrailingPunct(text[i..k]);
            if (u.len > 8) {
                const ck = try canonicalKey(alloc, u);
                if (!seen.contains(ck)) {
                    try seen.put(ck, {});
                    try out.append(alloc, .{ .page = page_num, .raw = try alloc.dupe(u8, u), .canonical = ck });
                }
            }
            i = k;
            continue;
        }
        const prev_ok = (i == 0) or !isAsciiAlnum(text[i - 1]);
        if (prev_ok and looksLikeDoi(text[i..])) {
            var k = i;
            while (k < text.len and isUrlBodyChar(text[k])) : (k += 1) {}
            const d = stripTrailingPunct(text[i..k]);
            const ck = try canonicalKey(alloc, d);
            if (!seen.contains(ck)) {
                try seen.put(ck, {});
                try out.append(alloc, .{ .page = page_num, .raw = try alloc.dupe(u8, d), .canonical = ck });
            }
            i = k;
            continue;
        }
        i += 1;
    }
}

/// Gate 6 (Rule 11): Clickable PDF resource link coverage & live anti-hallucination verification.
pub fn auditLinks(
    alloc: std.mem.Allocator,
    io: std.Io,
    pdf_path: []const u8,
    pages: []const mupdf.PageData,
    citations_path: ?[]const u8,
    ledger_path: ?[]const u8,
    min_links: usize,
    live: bool,
    timeout_secs: u32,
    allow_localhost: bool,
) !LinksReport {
    const clickable = try mupdf.extractPageLinks(alloc, io, pdf_path);
    var failures: std.ArrayList(LinkFailure) = .empty;
    var clickable_keys = std.StringHashMap(void).init(alloc);
    var clickable_key_list: std.ArrayList([]const u8) = .empty;
    var unique_valid: std.ArrayList([]const u8) = .empty;
    var seen_probe = std.StringHashMap(void).init(alloc);
    var uri_to_page = std.StringHashMap(usize).init(alloc);

    for (clickable) |lnk| {
        const ck = try canonicalKey(alloc, lnk.uri);
        if (!clickable_keys.contains(ck)) {
            try clickable_keys.put(ck, {});
            try clickable_key_list.append(alloc, ck);
        }
        if (!uri_to_page.contains(lnk.uri)) {
            try uri_to_page.put(lnk.uri, lnk.page);
        }
        const pw: f64 = if (lnk.page >= 1 and lnk.page <= pages.len) pages[lnk.page - 1].width else 612.0;
        const ph: f64 = if (lnk.page >= 1 and lnk.page <= pages.len) pages[lnk.page - 1].height else 792.0;
        const rw = lnk.x1 - lnk.x0;
        const rh = lnk.y1 - lnk.y0;
        const on_page = lnk.x1 > 0.0 and lnk.y1 > 0.0 and lnk.x0 < pw and lnk.y0 < ph;
        if (rw < 2.0 or rh < 2.0 or !on_page) {
            try failures.append(alloc, .{
                .page = lnk.page,
                .kind = "DEGENERATE_OR_HIDDEN_LINK_RECT",
                .uri = lnk.uri,
                .detail = try std.fmt.allocPrint(alloc, "Clickable rect [{d:.1},{d:.1},{d:.1},{d:.1}] is degenerate (<2x2 pt) or off-page", .{ lnk.x0, lnk.y0, lnk.x1, lnk.y1 }),
            });
        }
        if (validateUriSyntax(lnk.uri, allow_localhost)) |syn_err| {
            try failures.append(alloc, .{
                .page = lnk.page,
                .kind = syn_err,
                .uri = lnk.uri,
                .detail = try std.fmt.allocPrint(alloc, "Invalid/placeholder clickable link: {s}", .{lnk.uri}),
            });
        } else if (!seen_probe.contains(lnk.uri)) {
            try seen_probe.put(lnk.uri, {});
            try unique_valid.append(alloc, lnk.uri);
        }
    }

    if (clickable.len < min_links) {
        try failures.append(alloc, .{
            .page = 0,
            .kind = "INSUFFICIENT_CLICKABLE_LINKS",
            .uri = "",
            .detail = try std.fmt.allocPrint(alloc, "Found {d} clickable external link(s), minimum required is {d}", .{ clickable.len, min_links }),
        });
    }

    // Rule 11A: Every URL or DOI printed in PDF text MUST have a matching clickable PDF /URI annotation
    var text_res: std.ArrayList(TextRes) = .empty;
    for (pages) |pg| {
        try scanTextResources(alloc, pg.page_num, pg.prose_text, &text_res);
    }
    for (text_res.items) |tr| {
        var matched = clickable_keys.contains(tr.canonical);
        if (!matched) {
            for (clickable_key_list.items) |ck| {
                if (std.mem.startsWith(u8, ck, tr.canonical)) {
                    matched = true;
                    break;
                }
            }
        }
        if (!matched) {
            try failures.append(alloc, .{
                .page = tr.page,
                .kind = "UNLINKED_TEXT_RESOURCE",
                .uri = tr.raw,
                .detail = try std.fmt.allocPrint(alloc, "Printed URL/DOI '{s}' has no clickable PDF /URI annotation", .{tr.raw}),
            });
        }
    }

    // Rule 11B: Every resource URL/DOI declared in background_citations.json / provenance_ledger.json MUST be clickable in PDF
    var declared: std.ArrayList([]const u8) = .empty;
    const json_paths = [_]?[]const u8{ citations_path, ledger_path };
    for (json_paths) |opt_p| {
        if (opt_p) |jp| {
            const raw = try std.Io.Dir.cwd().readFileAlloc(io, jp, alloc, .unlimited);
            const parsed = try std.json.parseFromSliceLeaky(std.json.Value, alloc, raw, .{});
            try collectDeclaredUrls(alloc, parsed, &declared);
        }
    }
    var seen_decl = std.StringHashMap(void).init(alloc);
    var decl_count: usize = 0;
    for (declared.items) |du| {
        const ck = try canonicalKey(alloc, du);
        if (seen_decl.contains(ck)) continue;
        try seen_decl.put(ck, {});
        decl_count += 1;
        const check_uri = if (std.mem.find(u8, du, "://") != null) du else try std.fmt.allocPrint(alloc, "https://doi.org/{s}", .{du});
        if (validateUriSyntax(check_uri, allow_localhost)) |syn_err| {
            try failures.append(alloc, .{
                .page = 0,
                .kind = syn_err,
                .uri = du,
                .detail = try std.fmt.allocPrint(alloc, "Declared citation/ledger URI invalid: {s}", .{du}),
            });
            continue;
        }
        if (!clickable_keys.contains(ck)) {
            try failures.append(alloc, .{
                .page = 0,
                .kind = "DECLARED_RESOURCE_NOT_CLICKABLE",
                .uri = du,
                .detail = try std.fmt.allocPrint(alloc, "Resource '{s}' declared in citations/ledger is missing a clickable link in the PDF", .{du}),
            });
        }
    }

    // Rule 11C: Live Anti-Hallucination Verification
    var live_results: std.ArrayList(LiveLinkResult) = .empty;
    if (live) {
        for (unique_valid.items) |u| {
            const lr = try verifyLiveUri(alloc, io, u, timeout_secs);
            try live_results.append(alloc, lr);
            if (!lr.passed) {
                try failures.append(alloc, .{
                    .page = uri_to_page.get(u) orelse 0,
                    .kind = lr.verdict,
                    .uri = u,
                    .detail = try std.fmt.allocPrint(alloc, "Live check failed ({s}, status={d}): {s}", .{ lr.method, lr.status, lr.verdict }),
                });
            }
        }
    }

    const flist = try failures.toOwnedSlice(alloc);
    return .{
        .pages = pages.len,
        .clickable_links = clickable.len,
        .unique_uris = unique_valid.items.len,
        .text_resources = text_res.items.len,
        .declared_resources = decl_count,
        .live_checked = live,
        .live_results = try live_results.toOwnedSlice(alloc),
        .failures = flist,
        .passed = flist.len == 0,
    };
}

test "validateUriSyntax rejects placeholders, localhost, bad schemes, and accepts real URLs" {
    try std.testing.expect(validateUriSyntax("https://doi.org/10.1038/nature02417", false) == null);
    try std.testing.expect(validateUriSyntax("https://example.com/fake", false) != null);
    try std.testing.expect(validateUriSyntax("http://127.0.0.1:8080/x", false) != null);
    try std.testing.expect(validateUriSyntax("http://127.0.0.1:8080/x", true) == null);
    try std.testing.expect(validateUriSyntax("javascript:alert(1)", false) != null);
    try std.testing.expect(validateUriSyntax("https://site.invalid/paper", false) != null);
}

test "extractDoiFromUri and canonicalKey normalize doi.org and nature.com article slugs" {
    const alloc = std.testing.allocator;
    const d1 = (try extractDoiFromUri(alloc, "https://doi.org/10.1016/j.ejor.2005.12.009")).?;
    defer alloc.free(d1);
    try std.testing.expectEqualStrings("10.1016/j.ejor.2005.12.009", d1);

    const d2 = (try extractDoiFromUri(alloc, "https://www.nature.com/articles/s41586-026-99999-z")).?;
    defer alloc.free(d2);
    try std.testing.expectEqualStrings("10.1038/s41586-026-99999-z", d2);

    const k1 = try canonicalKey(alloc, "doi:10.1038/NATURE02417.");
    defer alloc.free(k1);
    const k2 = try canonicalKey(alloc, "https://dx.doi.org/10.1038/nature02417");
    defer alloc.free(k2);
    try std.testing.expectEqualStrings(k1, k2);
}

test "classifySoft404OrChallenge catches HTTP-200 Soft-404 and Bot-Challenge walls" {
    try std.testing.expect(classifySoft404OrChallenge("Client Challenge", "", "") != null);
    try std.testing.expect(classifySoft404OrChallenge("404 - Page Not Found", "", "") != null);
    try std.testing.expect(classifySoft404OrChallenge("Just a moment...", "", "") != null);
    try std.testing.expect(classifySoft404OrChallenge("Global Monitoring Laboratory - Carbon Cycle", "Mauna Loa CO2", "<html>ok</html>") == null);
}

test "parsePdfUriField decodes PDF literal and hex URI strings" {
    const alloc = std.testing.allocator;
    const uri1 = (try mupdf.parsePdfUriField(alloc, "<< /S /URI /URI (https://doi.org/10.1016/0305-0548\\(90\\)90090-X) >>")).?;
    defer alloc.free(uri1);
    try std.testing.expectEqualStrings("https://doi.org/10.1016/0305-0548(90)90090-X", uri1);

    const uri2 = (try mupdf.parsePdfUriField(alloc, "<< /S /URI /URI <68747470733a2f2f646f692e6f7267> >>")).?;
    defer alloc.free(uri2);
    try std.testing.expectEqualStrings("https://doi.org", uri2);
}
