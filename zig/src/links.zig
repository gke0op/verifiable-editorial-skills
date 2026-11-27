//! Rule 11 — Clickable PDF Resource Link & Live Anti-Hallucination Auditor (`vedit links`).
//! Sovereign bare-metal Zig 0.17.0 implementation (v0.7.0-zig Zero-Fabrication Hardening):
//!   1. Extracts every clickable `/Subtype /Link` `/URI` annotation via libmupdf (`mutool run`),
//!      rejecting hidden `/F` flags, non-standard `/AA` links, off-page/clipped <2x2pt rects,
//!      private/loopback/RFC-1918/IPv4-aton/IPv6 SSRF hosts, and placeholder domains.
//!   2. Scans rendered PDF text for plain-text URLs, DOIs, `www.`, `arXiv:`, `PMID:`, and line-wrapped URLs
//!      (`Rule 11A`: every printed resource must have an exact canonical clickable annotation on the SAME page).
//!   3. Cross-checks declared resource URLs/DOIs in `background_citations.json` and `provenance_ledger.json`
//!      (`Rule 11B`: every declared resource must appear as a valid visible clickable link in the PDF).
//!   4. Resolves every unique clickable link LIVE before finalization (`Rule 11C`):
//!      - Academic/dataset DOIs via CNRI/IDF DOI Handle Registry (`https://doi.org/api/handles/<doi>`),
//!        with strict domain-suffix matching on publisher hosts and zero dead-subpath shortcuts.
//!      - Open-science portals (`gbif.org/species/<id>`, `inaturalist.org/taxa/<id>`) via public REST APIs
//!        only when no extra dead subpath follows the taxon ID.
//!      - General web URLs via live HTTP GET (`curl -g --proto =http,https --range 0-262143` or hardened
//!        pure-Zig `std.http.Client` fallback with socket timeouts, 64 KB body cap, and hop-by-hop SSRF validation),
//!        rejecting 404/410/403/5xx, DNS/TLS errors, Soft-404s, and HTTP-200 bot-challenge interstitials.

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

/// Strict domain-suffix match (exact domain or dot-delimited subdomain), immune to substring spoofing.
pub fn hostMatchesDomain(raw_host: []const u8, domain: []const u8) bool {
    const host = std.mem.trimEnd(u8, raw_host, ".");
    const dom = std.mem.trimEnd(u8, domain, ".");
    if (host.len < dom.len or dom.len == 0) return false;
    if (host.len == dom.len) return std.ascii.eqlIgnoreCase(host, dom);
    return host[host.len - dom.len - 1] == '.' and endsWithFold(host, dom);
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
        // After ']', either end or ':port'
        if (rb + 1 < host_port.len and host_port[rb + 1] != ':') return null;
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

/// Extract canonical DOI (`10.xxxx/...`) from bare DOI, `doi.org`, `nature.com/articles/<slug>`, or publisher DOI paths.
pub fn extractDoiFromUri(alloc: std.mem.Allocator, uri_raw: []const u8) !?[]u8 {
    const u = stripTrailingPunct(uri_raw);
    if (startsWithFold(u, "doi:")) {
        const rest = std.mem.trimStart(u8, u[4..], " \t");
        if (looksLikeDoi(rest)) return try alloc.dupe(u8, rest);
    }
    if (looksLikeDoi(u)) return try alloc.dupe(u8, u);

    const hp = splitUrl(u) orelse return null;
    const norm_host = std.mem.trimEnd(u8, hp.host, ".");
    const path_only = blk: {
        const q = std.mem.findAny(u8, hp.path, "?#") orelse hp.path.len;
        break :blk std.mem.trimStart(u8, hp.path[0..q], "/");
    };

    if (std.ascii.eqlIgnoreCase(norm_host, "doi.org") or
        std.ascii.eqlIgnoreCase(norm_host, "www.doi.org") or
        std.ascii.eqlIgnoreCase(norm_host, "dx.doi.org"))
    {
        if (looksLikeDoi(path_only)) return try alloc.dupe(u8, path_only);
    }

    if ((std.ascii.eqlIgnoreCase(norm_host, "nature.com") or std.ascii.eqlIgnoreCase(norm_host, "www.nature.com")) and
        std.mem.startsWith(u8, path_only, "articles/"))
    {
        const after = std.mem.trimEnd(u8, path_only["articles/".len..], "/");
        // Only map direct article URLs (no extra dead subpath like /articles/slug/fake-subpath)
        if (after.len > 0 and std.mem.findScalar(u8, after, '/') == null) {
            return try std.fmt.allocPrint(alloc, "10.1038/{s}", .{after});
        }
    }

    const pub_hosts = [_][]const u8{
        "aps.org",      "science.org", "wiley.com", "acs.org", "tandfonline.com",
        "springer.com", "sagepub.com", "iop.org",   "oup.com",
    };
    var is_pub = false;
    for (pub_hosts) |ph| {
        if (hostMatchesDomain(norm_host, ph)) {
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
        for (std.mem.trimEnd(u8, hp.host_port, ".")) |ch| try out.append(alloc, std.ascii.toLower(ch));
        try out.appendSlice(alloc, trimmed_rest);
        return out.toOwnedSlice(alloc);
    }
    var out = try alloc.alloc(u8, s.len);
    for (s, 0..) |ch, idx| out[idx] = std.ascii.toLower(ch);
    return out;
}

fn parseAtonPart(part: []const u8) ?u64 {
    if (part.len == 0) return null;
    if (part.len >= 3 and part[0] == '0' and (part[1] == 'x' or part[1] == 'X')) {
        return std.fmt.parseInt(u64, part[2..], 16) catch return null;
    }
    if (part.len >= 2 and part[0] == '0') {
        for (part[1..]) |ch| {
            if (ch < '0' or ch > '7') return null;
        }
        return std.fmt.parseInt(u64, part[1..], 8) catch return null;
    }
    for (part) |ch| {
        if (ch < '0' or ch > '9') return null;
    }
    return std.fmt.parseInt(u64, part, 10) catch return null;
}

/// Parse POSIX `inet_aton` IPv4 literals (4-part dotted, 2/3-part shorthand `127.1`, octal `0177.0.0.1`, hex `0x7f000001`, decimal integer).
fn parseIpv4Aton(host: []const u8) ?u32 {
    if (host.len == 0) return null;
    var parts: [4]u64 = undefined;
    var n: usize = 0;
    var it = std.mem.splitScalar(u8, host, '.');
    while (it.next()) |p| {
        if (n >= 4) return null;
        parts[n] = parseAtonPart(p) orelse return null;
        n += 1;
    }
    return switch (n) {
        1 => if (parts[0] <= 0xFFFF_FFFF) @intCast(parts[0]) else null,
        2 => if (parts[0] <= 0xFF and parts[1] <= 0xFF_FFFF)
            @intCast((parts[0] << 24) | parts[1])
        else
            null,
        3 => if (parts[0] <= 0xFF and parts[1] <= 0xFF and parts[2] <= 0xFFFF)
            @intCast((parts[0] << 24) | (parts[1] << 16) | parts[2])
        else
            null,
        4 => if (parts[0] <= 0xFF and parts[1] <= 0xFF and parts[2] <= 0xFF and parts[3] <= 0xFF)
            @intCast((parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3])
        else
            null,
        else => null,
    };
}

fn isPrivateOrLocalIpv4(ip: u32) bool {
    const b0: u8 = @intCast((ip >> 24) & 0xFF);
    const b1: u8 = @intCast((ip >> 16) & 0xFF);
    if (b0 == 0) return true; // 0.0.0.0/8
    if (b0 == 10) return true; // 10.0.0.0/8 (RFC 1918)
    if (b0 == 100 and (b1 >= 64 and b1 <= 127)) return true; // 100.64.0.0/10 (CGNAT)
    if (b0 == 127) return true; // 127.0.0.0/8 (Loopback)
    if (b0 == 169 and b1 == 254) return true; // 169.254.0.0/16 (Link-local / Cloud IMDS)
    if (b0 == 172 and (b1 >= 16 and b1 <= 31)) return true; // 172.16.0.0/12 (RFC 1918)
    if (b0 == 192 and b1 == 168) return true; // 192.168.0.0/16 (RFC 1918)
    if (b0 == 192 and b1 == 0 and ((ip >> 8) & 0xFF) == 2) return true; // TEST-NET-1
    if (b0 == 198 and b1 == 51 and ((ip >> 8) & 0xFF) == 100) return true; // TEST-NET-2
    if (b0 == 203 and b1 == 0 and ((ip >> 8) & 0xFF) == 113) return true; // TEST-NET-3
    if (b0 >= 224) return true; // Multicast & Reserved
    return false;
}

/// Parse RFC 4291 IPv6 address (with `::` compression and embedded IPv4 tail `::ffff:127.0.0.1`) into 16 bytes.
fn parseIpv6Bytes(raw_in: []const u8) ?[16]u8 {
    // Strip optional zone id (`%eth0` / `%25eth0`)
    const s = if (std.mem.findScalar(u8, raw_in, '%')) |p| raw_in[0..p] else raw_in;
    if (s.len == 0) return null;

    var head: [8]u16 = undefined;
    var tail: [8]u16 = undefined;
    var head_n: usize = 0;
    var tail_n: usize = 0;
    var saw_double = false;

    const dbl = std.mem.find(u8, s, "::");
    const left_s = if (dbl) |d| s[0..d] else s;
    const right_s = if (dbl) |d| s[d + 2 ..] else "";
    if (dbl != null) {
        saw_double = true;
        if (std.mem.find(u8, right_s, "::") != null) return null;
    }

    if (left_s.len > 0) {
        var it = std.mem.splitScalar(u8, left_s, ':');
        while (it.next()) |seg| {
            if (seg.len == 0 or seg.len > 4) {
                // Only allowed in tail as dotted IPv4 when no `::`
                if (!saw_double and std.mem.findScalar(u8, seg, '.') != null and it.next() == null) {
                    const v4 = parseIpv4Aton(seg) orelse return null;
                    if (head_n + 2 > 8) return null;
                    head[head_n] = @intCast((v4 >> 16) & 0xFFFF);
                    head[head_n + 1] = @intCast(v4 & 0xFFFF);
                    head_n += 2;
                    break;
                }
                return null;
            }
            if (head_n >= 8) return null;
            head[head_n] = std.fmt.parseInt(u16, seg, 16) catch return null;
            head_n += 1;
        }
    }
    if (right_s.len > 0) {
        var it = std.mem.splitScalar(u8, right_s, ':');
        while (it.next()) |seg| {
            if (std.mem.findScalar(u8, seg, '.') != null) {
                if (it.next() != null) return null;
                const v4 = parseIpv4Aton(seg) orelse return null;
                if (tail_n + 2 > 8) return null;
                tail[tail_n] = @intCast((v4 >> 16) & 0xFFFF);
                tail[tail_n + 1] = @intCast(v4 & 0xFFFF);
                tail_n += 2;
                break;
            }
            if (seg.len == 0 or seg.len > 4 or tail_n >= 8) return null;
            tail[tail_n] = std.fmt.parseInt(u16, seg, 16) catch return null;
            tail_n += 1;
        }
    }

    var words: [8]u16 = @splat(0);
    if (saw_double) {
        if (head_n + tail_n >= 8) return null;
        for (0..head_n) |i| words[i] = head[i];
        const start = 8 - tail_n;
        for (0..tail_n) |i| words[start + i] = tail[i];
    } else {
        if (head_n != 8) return null;
        words = head;
    }
    var out: [16]u8 = undefined;
    for (0..8) |i| {
        out[i * 2] = @intCast((words[i] >> 8) & 0xFF);
        out[i * 2 + 1] = @intCast(words[i] & 0xFF);
    }
    return out;
}

fn isPrivateOrLocalIpv6(b: [16]u8) bool {
    var all_zero = true;
    for (b) |v| {
        if (v != 0) {
            all_zero = false;
            break;
        }
    }
    if (all_zero) return true; // ::
    var lo_zero = true;
    for (b[0..15]) |v| {
        if (v != 0) {
            lo_zero = false;
            break;
        }
    }
    if (lo_zero and b[15] == 1) return true; // ::1
    if ((b[0] & 0xFE) == 0xFC) return true; // fc00::/7 ULA
    if (b[0] == 0xFE and (b[1] & 0xC0) == 0x80) return true; // fe80::/10 link-local
    if (b[0] == 0xFF) return true; // ff00::/8 multicast
    // ::ffff:0:0/96 IPv4-mapped IPv6
    var mapped = true;
    for (b[0..10]) |v| {
        if (v != 0) {
            mapped = false;
            break;
        }
    }
    if (mapped and b[10] == 0xFF and b[11] == 0xFF) {
        const v4: u32 = (@as(u32, b[12]) << 24) | (@as(u32, b[13]) << 16) | (@as(u32, b[14]) << 8) | @as(u32, b[15]);
        return isPrivateOrLocalIpv4(v4);
    }
    // ::0:0/96 IPv4-compatible legacy
    var compat = true;
    for (b[0..12]) |v| {
        if (v != 0) {
            compat = false;
            break;
        }
    }
    if (compat) {
        const v4: u32 = (@as(u32, b[12]) << 24) | (@as(u32, b[13]) << 16) | (@as(u32, b[14]) << 8) | @as(u32, b[15]);
        return isPrivateOrLocalIpv4(v4);
    }
    // 2001:db8::/32 documentation range
    if (b[0] == 0x20 and b[1] == 0x01 and b[2] == 0x0D and b[3] == 0xB8) return true;
    return false;
}

fn hasWholeLabelPlaceholder(norm_host: []const u8, tok: []const u8) bool {
    var it = std.mem.splitScalar(u8, norm_host, '.');
    while (it.next()) |lbl| {
        if (std.ascii.eqlIgnoreCase(lbl, tok)) return true;
    }
    return false;
}

fn hasWholePathSegmentPlaceholder(path_raw: []const u8, tok: []const u8) bool {
    const q = std.mem.findAny(u8, path_raw, "?#") orelse path_raw.len;
    const p = path_raw[0..q];
    var it = std.mem.splitScalar(u8, p, '/');
    while (it.next()) |seg| {
        if (std.ascii.eqlIgnoreCase(seg, tok)) return true;
    }
    return false;
}

pub fn validateUriSyntax(uri: []const u8, allow_localhost: bool) ?[]const u8 {
    if (uri.len == 0) return "INVALID_URI_WHITESPACE_OR_EMPTY";
    for (uri) |ch| {
        if (ch <= 32 or ch == 127 or ch == '\\') return "INVALID_URI_WHITESPACE_OR_EMPTY";
    }
    const hp = splitUrl(uri) orelse return "DISALLOWED_SCHEME";
    if (!std.ascii.eqlIgnoreCase(hp.scheme, "http") and !std.ascii.eqlIgnoreCase(hp.scheme, "https")) {
        return "DISALLOWED_SCHEME";
    }
    if (hp.host.len == 0) return "MISSING_HOST";

    const norm_host = std.mem.trimEnd(u8, hp.host, ".");
    if (norm_host.len == 0) return "MISSING_HOST";

    // 1. Bracketed IPv6 literal (`[::1]`, `[::ffff:127.0.0.1]`, `[2606:2800:...]`)
    if (norm_host[0] == '[' and norm_host[norm_host.len - 1] == ']') {
        const inner = norm_host[1 .. norm_host.len - 1];
        const b = parseIpv6Bytes(inner) orelse return "INVALID_HOST";
        if (isPrivateOrLocalIpv6(b)) {
            return if (allow_localhost) null else "LOCALHOST_OR_PRIVATE_IP_DISALLOWED";
        }
    } else if (parseIpv4Aton(norm_host)) |v4| {
        // 2. IPv4 literal in any POSIX inet_aton representation (127.1, 0177.0.0.1, 0x7f000001, 2130706433, 10/8, 169.254/16, ...)
        if (isPrivateOrLocalIpv4(v4)) {
            return if (allow_localhost) null else "LOCALHOST_OR_PRIVATE_IP_DISALLOWED";
        }
    } else {
        // 3. DNS hostname
        if (hostMatchesDomain(norm_host, "localhost")) {
            return if (allow_localhost) null else "LOCALHOST_URI_DISALLOWED";
        }
        const ph_hosts = [_][]const u8{
            "example.com",     "example.org",    "example.net",     "foo.bar",
            "your-domain.com", "yourdomain.com", "placeholder.com", "placeholder.org",
        };
        for (ph_hosts) |ph| {
            if (hostMatchesDomain(norm_host, ph)) return "PLACEHOLDER_HOST";
        }
        const ph_tlds = [_][]const u8{ ".invalid", ".test", ".local", ".example", ".localhost", ".internal" };
        for (ph_tlds) |tld| {
            if (endsWithFold(norm_host, tld)) return "PLACEHOLDER_HOST";
        }
        if (std.mem.findScalar(u8, norm_host, '.') == null) return "INVALID_HOST_NO_DOT";
        if (norm_host[0] == '.' or std.mem.find(u8, norm_host, "..") != null) return "INVALID_HOST";
    }

    // 4. Whole-label / whole-segment placeholder tokens (allows `mastodon.social` and `/Todos_los_santos`!)
    const ph_tokens = [_][]const u8{ "placeholder", "todo", "tbd", "insert-url", "your-link" };
    for (ph_tokens) |tok| {
        if (hasWholeLabelPlaceholder(norm_host, tok)) return "PLACEHOLDER_URI";
        if (hasWholePathSegmentPlaceholder(hp.path, tok)) return "PLACEHOLDER_URI";
    }
    return null;
}

fn decodeHtmlEntity(s: []const u8, consumed: *usize) u8 {
    const semi = std.mem.findScalar(u8, s, ';') orelse {
        consumed.* = 1;
        return s[0];
    };
    if (semi > 12) {
        consumed.* = 1;
        return s[0];
    }
    const ent = s[1..semi];
    consumed.* = semi + 1;
    if (std.ascii.eqlIgnoreCase(ent, "amp")) return '&';
    if (std.ascii.eqlIgnoreCase(ent, "lt")) return '<';
    if (std.ascii.eqlIgnoreCase(ent, "gt")) return '>';
    if (std.ascii.eqlIgnoreCase(ent, "quot")) return '"';
    if (std.ascii.eqlIgnoreCase(ent, "apos") or std.ascii.eqlIgnoreCase(ent, "rsquo") or std.ascii.eqlIgnoreCase(ent, "lsquo") or
        std.mem.eql(u8, ent, "#39") or std.ascii.eqlIgnoreCase(ent, "#x27") or std.mem.eql(u8, ent, "#8217"))
        return '\'';
    if (std.ascii.eqlIgnoreCase(ent, "nbsp")) return ' ';
    if (std.ascii.eqlIgnoreCase(ent, "ndash") or std.ascii.eqlIgnoreCase(ent, "mdash")) return '-';
    consumed.* = 1;
    return s[0];
}

fn extractTagInner(alloc: std.mem.Allocator, html_body: []const u8, open_prefix: []const u8, close_tag: []const u8) ![]u8 {
    var i: usize = 0;
    while (i + open_prefix.len < html_body.len) {
        // Skip HTML comments `<!-- ... -->`
        if (i + 4 <= html_body.len and std.mem.eql(u8, html_body[i .. i + 4], "<!--")) {
            i = if (std.mem.findPos(u8, html_body, i + 4, "-->")) |end_c| end_c + 3 else html_body.len;
            continue;
        }
        // Skip inline `<svg ...>...</svg>` so SVG icon `<title>` never shadows document `<title>`
        if (i + 4 <= html_body.len and std.ascii.eqlIgnoreCase(html_body[i .. i + 4], "<svg") and
            (i + 4 == html_body.len or html_body[i + 4] == '>' or html_body[i + 4] <= 32))
        {
            var k = i + 4;
            while (k + 6 <= html_body.len) : (k += 1) {
                if (std.ascii.eqlIgnoreCase(html_body[k .. k + 6], "</svg>")) {
                    k += 6;
                    break;
                }
            }
            i = k;
            continue;
        }
        // Skip `<script ...>...</script>` blocks
        if (i + 7 <= html_body.len and std.ascii.eqlIgnoreCase(html_body[i .. i + 7], "<script") and
            (i + 7 == html_body.len or html_body[i + 7] == '>' or html_body[i + 7] <= 32))
        {
            var k = i + 7;
            while (k + 9 <= html_body.len) : (k += 1) {
                if (std.ascii.eqlIgnoreCase(html_body[k .. k + 9], "</script>")) {
                    k += 9;
                    break;
                }
            }
            i = k;
            continue;
        }

        if (std.ascii.eqlIgnoreCase(html_body[i .. i + open_prefix.len], open_prefix)) {
            const next_ch = html_body[i + open_prefix.len];
            if (next_ch != '>' and next_ch != '/' and next_ch > 32) {
                i += 1;
                continue;
            }
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
            var ri: usize = 0;
            while (ri < raw.len) {
                const ch = raw[ri];
                if (ch == '<') {
                    in_tag = true;
                    ri += 1;
                    continue;
                }
                if (ch == '>') {
                    in_tag = false;
                    ri += 1;
                    continue;
                }
                if (in_tag) {
                    ri += 1;
                    continue;
                }
                var out_ch = ch;
                if (ch == '&') {
                    var step: usize = 1;
                    out_ch = decodeHtmlEntity(raw[ri..], &step);
                    ri += step;
                } else {
                    ri += 1;
                }
                if (out_ch <= 32) {
                    if (!prev_ws) {
                        try out.append(alloc, ' ');
                        prev_ws = true;
                    }
                } else {
                    try out.append(alloc, out_ch);
                    prev_ws = false;
                }
                if (out.items.len >= 160) break;
            }
            const trimmed = std.mem.trim(u8, out.items, " ");
            const res = try alloc.dupe(u8, trimmed);
            out.deinit(alloc);
            return res;
        }
        i += 1;
    }
    return try alloc.dupe(u8, "");
}

pub fn classifySoft404OrChallenge(title: []const u8, h1: []const u8, body: []const u8) ?[]const u8 {
    const bot_pats = [_][]const u8{
        "client challenge",        "just a moment",                             "attention required",
        "verify you are human",    "are you a robot",                           "bot detection",
        "pardon our interruption", "ddos-guard",                                "security check",
        "access denied",           "enable javascript and cookies to continue", "checking your browser",
        "one more step",           "human verification",
    };
    for (bot_pats) |pat| {
        if (containsFold(title, pat) or containsFold(h1, pat)) return "BOT_CHALLENGE_UNVERIFIED";
    }
    const sample = body[0..@min(body.len, 65536)];
    const body_bot_pats = [_][]const u8{
        "cf-browser-verification",   "challenge-platform", "window._cf_chl_opt",
        "challenges.cloudflare.com", "px-captcha",         "captcha-delivery.com",
        "aws-waf-captcha",           "ddos-guard",
    };
    for (body_bot_pats) |bp| {
        if (containsFold(sample, bp)) return "BOT_CHALLENGE_UNVERIFIED";
    }

    const s404_pats = [_][]const u8{
        "404 not found",           "error 404",                "404 error",
        "404 -",                   "- 404",                    "404 |",
        "| 404",                   "404:",                     "http 404",
        "page not found",          "article not found",        "document not found",
        "doi not found",           "file not found",           "resource not found",
        "record not found",        "item not found",           "content not found",
        "entry not found",         "url not found",            "cannot be found",
        "could not be found",      "couldn't be found",        "we couldn't find",
        "we could not find",       "sorry, we can't find",     "nothing was found",
        "this page doesn't exist", "this page does not exist", "page does not exist",
        "page doesn't exist",      "does not exist",           "no longer available",
        "broken link",             "missing page",             "not found",
    };
    for (s404_pats) |pat| {
        if (containsFold(title, pat) or containsFold(h1, pat)) return "SOFT_404_HALLUCINATED";
    }
    if (std.mem.eql(u8, std.mem.trim(u8, title, " \t"), "404") or
        std.mem.eql(u8, std.mem.trim(u8, h1, " \t"), "404"))
    {
        return "SOFT_404_HALLUCINATED";
    }

    // Meta-refresh or JS redirect to a 404 / not-found route
    if (containsFold(sample, "http-equiv=\"refresh\"") or containsFold(sample, "http-equiv='refresh'")) {
        if (containsFold(sample, "/404") or containsFold(sample, "not-found") or containsFold(sample, "not_found")) {
            return "SOFT_404_HALLUCINATED";
        }
    }
    if ((containsFold(sample, "window.location") or containsFold(sample, "location.replace")) and
        (containsFold(sample, "/404") or containsFold(sample, "not-found") or containsFold(sample, "not_found")))
    {
        return "SOFT_404_HALLUCINATED";
    }

    // Compact HTML error pages where <title> is a generic site brand and the 404 message sits in <h2>/<p>
    if (sample.len < 8192) {
        const body_404_pats = [_][]const u8{
            "404 not found",               "error 404",                                 "page not found",
            "article not found",           "document not found",                        "doi not found",
            "this page does not exist",    "this page doesn't exist",                   "we couldn't find the page",
            "requested url was not found", "the page you requested could not be found",
        };
        for (body_404_pats) |p4| {
            if (containsFold(sample, p4)) return "SOFT_404_HALLUCINATED";
        }
    }
    return null;
}

pub const HttpResponse = struct {
    status: i32,
    final_url: []const u8,
    body: []const u8,
    err_kind: ?[]const u8,
};

fn resolveRedirectUrl(alloc: std.mem.Allocator, base_url: []const u8, location_raw: []const u8) ![]u8 {
    const loc = std.mem.trim(u8, location_raw, " \t\r\n");
    if (startsWithFold(loc, "http://") or startsWithFold(loc, "https://")) {
        return try alloc.dupe(u8, loc);
    }
    const hp = splitUrl(base_url) orelse return try alloc.dupe(u8, loc);
    if (std.mem.startsWith(u8, loc, "//")) {
        return try std.fmt.allocPrint(alloc, "{s}:{s}", .{ hp.scheme, loc });
    }
    if (loc.len > 0 and loc[0] == '/') {
        return try std.fmt.allocPrint(alloc, "{s}://{s}{s}", .{ hp.scheme, hp.host_port, loc });
    }
    const q = std.mem.findAny(u8, hp.path, "?#") orelse hp.path.len;
    const base_path = hp.path[0..q];
    const dir_end = if (std.mem.findScalarLast(u8, base_path, '/')) |sl| sl + 1 else 0;
    const dir_prefix = if (dir_end > 0) base_path[0..dir_end] else "/";
    return try std.fmt.allocPrint(alloc, "{s}://{s}{s}{s}", .{ hp.scheme, hp.host_port, dir_prefix, loc });
}

fn applySocketTimeouts(handle: std.posix.socket_t, timeout_secs: u32) !void {
    const secs: isize = @intCast(@max(@as(u32, 1), @min(timeout_secs, 60)));
    const tv: std.posix.timeval = .{ .sec = secs, .usec = 0 };
    const tv_bytes = std.mem.asBytes(&tv);
    try std.posix.setsockopt(handle, std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO, tv_bytes);
    try std.posix.setsockopt(handle, std.posix.SOL.SOCKET, std.posix.SO.SNDTIMEO, tv_bytes);
}

/// Hardened pure-Zig `std.http.Client` GET fallback (bounded 64 KB body, socket RCV/SND timeouts, manual hop-by-hop SSRF redirect validation).
pub fn httpGetZigFallback(
    alloc: std.mem.Allocator,
    io: std.Io,
    url: []const u8,
    timeout_secs: u32,
    allow_localhost: bool,
) !HttpResponse {
    var client: std.http.Client = .{ .allocator = alloc, .io = io };
    defer client.deinit();

    var cur_url: []const u8 = try alloc.dupe(u8, url);
    var hop: usize = 0;
    while (hop <= 8) : (hop += 1) {
        if (validateUriSyntax(cur_url, allow_localhost)) |syn_err| {
            return .{ .status = -1, .final_url = cur_url, .body = "", .err_kind = syn_err };
        }
        const parsed_uri = std.Uri.parse(cur_url) catch {
            return .{ .status = -1, .final_url = cur_url, .body = "", .err_kind = "INVALID_REDIRECT_URI" };
        };

        var req = client.request(.GET, parsed_uri, .{
            .redirect_behavior = .unhandled,
            .keep_alive = false,
            .headers = .{
                .user_agent = .{ .override = "Mozilla/5.0 (compatible; verifiable-editorial-vedit/0.7)" },
            },
            .extra_headers = &.{
                .{ .name = "Accept", .value = "text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8" },
                .{ .name = "Accept-Encoding", .value = "identity" },
            },
        }) catch {
            return .{ .status = -1, .final_url = cur_url, .body = "", .err_kind = "UNREACHABLE_OR_HALLUCINATED" };
        };
        defer req.deinit();

        if (req.connection) |conn| {
            applySocketTimeouts(conn.stream_reader.stream.socket.handle, timeout_secs) catch {
                return .{ .status = -1, .final_url = cur_url, .body = "", .err_kind = "SOCKET_TIMEOUT_CONFIG_FAILED" };
            };
        }

        req.sendBodiless() catch {
            return .{ .status = -1, .final_url = cur_url, .body = "", .err_kind = "UNREACHABLE_OR_HALLUCINATED" };
        };

        var redir_buf: [16384]u8 = undefined;
        var resp = req.receiveHead(&redir_buf) catch {
            return .{ .status = -1, .final_url = cur_url, .body = "", .err_kind = "UNREACHABLE_OR_HALLUCINATED" };
        };
        const st: i32 = @backingInt(resp.head.status);

        if ((st == 301 or st == 302 or st == 303 or st == 307 or st == 308)) {
            const loc = resp.head.location orelse {
                return .{ .status = st, .final_url = cur_url, .body = "", .err_kind = "REDIRECT_WITHOUT_LOCATION" };
            };
            if (hop == 8) {
                return .{ .status = st, .final_url = cur_url, .body = "", .err_kind = "TOO_MANY_REDIRECTS" };
            }
            cur_url = try resolveRedirectUrl(alloc, cur_url, loc);
            continue;
        }

        // Bounded streaming body read capped strictly at 65,536 bytes (zero OOM on multi-MB/infinite streams)
        var transfer_buf: [8192]u8 = undefined;
        const reader = resp.reader(&transfer_buf);
        const cap_buf = try alloc.alloc(u8, 65536);
        var total_read: usize = 0;
        while (total_read < cap_buf.len) {
            const n = reader.readSliceShort(cap_buf[total_read..]) catch break;
            if (n == 0) break;
            total_read += n;
        }
        const body_slice = try alloc.dupe(u8, cap_buf[0..total_read]);
        alloc.free(cap_buf);

        return .{
            .status = st,
            .final_url = cur_url,
            .body = body_slice,
            .err_kind = if (st >= 200 and st <= 299) null else try std.fmt.allocPrint(alloc, "HTTP_{d}", .{st}),
        };
    }
    return .{ .status = -1, .final_url = cur_url, .body = "", .err_kind = "TOO_MANY_REDIRECTS" };
}

fn runCurlGet(alloc: std.mem.Allocator, io: std.Io, url: []const u8, timeout_secs: u32, use_range: bool) !std.process.RunResult {
    const t_str = try std.fmt.allocPrint(alloc, "{d}", .{@max(@as(u32, 1), @min(timeout_secs, 60))});
    if (use_range) {
        return std.process.run(alloc, io, .{
            .argv = &.{
                "curl",
                "-sS",
                "-g",
                "-L",
                "--proto",
                "=http,https",
                "--proto-redir",
                "=http,https",
                "--max-redirs",
                "8",
                "--connect-timeout",
                t_str,
                "--max-time",
                t_str,
                "--range",
                "0-262143",
                "-A",
                "Mozilla/5.0 (compatible; verifiable-editorial-vedit/0.7)",
                "-H",
                "Accept: text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8",
                "-w",
                "\n__VEDIT_HTTP__:%{http_code}\t%{url_effective}",
                "--",
                url,
            },
            .stdout_limit = .limited(512 * 1024),
            .stderr_limit = .limited(65536),
        });
    }
    return std.process.run(alloc, io, .{
        .argv = &.{
            "curl",
            "-sS",
            "-g",
            "-L",
            "--proto",
            "=http,https",
            "--proto-redir",
            "=http,https",
            "--max-redirs",
            "8",
            "--connect-timeout",
            t_str,
            "--max-time",
            t_str,
            "--max-filesize",
            "524288",
            "-A",
            "Mozilla/5.0 (compatible; verifiable-editorial-vedit/0.7)",
            "-H",
            "Accept: text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8",
            "-w",
            "\n__VEDIT_HTTP__:%{http_code}\t%{url_effective}",
            "--",
            url,
        },
        .stdout_limit = .limited(512 * 1024),
        .stderr_limit = .limited(65536),
    });
}

fn httpGetText(alloc: std.mem.Allocator, io: std.Io, url: []const u8, timeout_secs: u32, allow_localhost: bool) !HttpResponse {
    if (validateUriSyntax(url, allow_localhost)) |syn_err| {
        return .{ .status = -1, .final_url = url, .body = "", .err_kind = syn_err };
    }
    const marker = "\n__VEDIT_HTTP__:";
    var res = runCurlGet(alloc, io, url, timeout_secs, true) catch |err| {
        if (err == error.FileNotFound) {
            return try httpGetZigFallback(alloc, io, url, timeout_secs, allow_localhost);
        }
        return .{ .status = -1, .final_url = url, .body = "", .err_kind = "UNREACHABLE_OR_HALLUCINATED" };
    };

    var code: u8 = switch (res.term) {
        .exited => |c| c,
        else => 255,
    };
    var mpos = std.mem.findLast(u8, res.stdout, marker) orelse {
        return .{ .status = -1, .final_url = url, .body = "", .err_kind = "UNREACHABLE_OR_HALLUCINATED" };
    };
    var meta = std.mem.trim(u8, res.stdout[mpos + marker.len ..], " \t\r\n");
    var tab = std.mem.findScalar(u8, meta, '\t') orelse meta.len;
    var status = std.fmt.parseInt(i32, meta[0..tab], 10) catch -1;

    // Some endpoints return HTTP 416 when asked for a byte range on 0-byte or non-rangeable responses: retry once without --range.
    if (status == 416) {
        res = runCurlGet(alloc, io, url, timeout_secs, false) catch {
            return .{ .status = -1, .final_url = url, .body = "", .err_kind = "UNREACHABLE_OR_HALLUCINATED" };
        };
        code = switch (res.term) {
            .exited => |c| c,
            else => 255,
        };
        mpos = std.mem.findLast(u8, res.stdout, marker) orelse {
            return .{ .status = -1, .final_url = url, .body = "", .err_kind = "UNREACHABLE_OR_HALLUCINATED" };
        };
        meta = std.mem.trim(u8, res.stdout[mpos + marker.len ..], " \t\r\n");
        tab = std.mem.findScalar(u8, meta, '\t') orelse meta.len;
        status = std.fmt.parseInt(i32, meta[0..tab], 10) catch -1;
    }

    const raw_body = res.stdout[0..@min(mpos, 65536)];
    const eff_url = if (tab + 1 < meta.len) meta[tab + 1 ..] else url;
    // Post-redirect SSRF & placeholder guard: block open redirects to loopback / cloud IMDS / placeholder hosts
    if (validateUriSyntax(eff_url, allow_localhost)) |redir_err| {
        return .{ .status = status, .final_url = eff_url, .body = "", .err_kind = redir_err };
    }
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

/// Extract strict numeric taxon ID after prefix, refusing dead extra subpaths (e.g. `/taxa/47792/fake-subpath`).
fn extractStrictTaxonId(path_raw: []const u8, prefix: []const u8, allow_hyphen_slug: bool) ?[]const u8 {
    const q = std.mem.findAny(u8, path_raw, "?#") orelse path_raw.len;
    const path = std.mem.trimEnd(u8, path_raw[0..q], "/");
    if (!std.mem.startsWith(u8, path, prefix)) return null;
    const rest = path[prefix.len..];
    var k: usize = 0;
    while (k < rest.len and rest[k] >= '0' and rest[k] <= '9') : (k += 1) {}
    if (k == 0) return null;
    if (k == rest.len) return rest[0..k];
    if (allow_hyphen_slug and rest[k] == '-' and std.mem.findScalar(u8, rest[k + 1 ..], '/') == null) {
        return rest[0..k];
    }
    return null;
}

fn verifyLiveUri(alloc: std.mem.Allocator, io: std.Io, uri: []const u8, timeout_secs: u32, allow_localhost: bool) !LiveLinkResult {
    // 1. Authoritative CNRI/IDF DOI Handle Registry
    if (try extractDoiFromUri(alloc, uri)) |doi| {
        const handle_url = try std.fmt.allocPrint(alloc, "https://doi.org/api/handles/{s}", .{doi});
        const resp = try httpGetText(alloc, io, handle_url, timeout_secs, allow_localhost);
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

    // 2. Open-Science REST APIs (GBIF / iNaturalist — strict path matching so dead subpaths fall through to HTTP GET!)
    if (splitUrl(uri)) |hp| {
        const nh = std.mem.trimEnd(u8, hp.host, ".");
        if (std.ascii.eqlIgnoreCase(nh, "gbif.org") or std.ascii.eqlIgnoreCase(nh, "www.gbif.org")) {
            if (extractStrictTaxonId(hp.path, "/species/", false)) |sp_id| {
                const api_url = try std.fmt.allocPrint(alloc, "https://api.gbif.org/v1/species/{s}", .{sp_id});
                const resp = try httpGetText(alloc, io, api_url, timeout_secs, allow_localhost);
                if (resp.status == 200) {
                    var sci: []const u8 = try std.fmt.allocPrint(alloc, "GBIF:{s}", .{sp_id});
                    if (std.json.parseFromSliceLeaky(std.json.Value, alloc, resp.body, .{})) |pv| {
                        if (pv == .object) {
                            if (pv.object.get("scientificName")) |sv| if (sv == .string) {
                                sci = sv.string;
                            };
                        }
                    } else |err| {
                        std.log.debug("gbif api json parse skipped: {s}", .{@errorName(err)});
                    }
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
        if (std.ascii.eqlIgnoreCase(nh, "inaturalist.org") or std.ascii.eqlIgnoreCase(nh, "www.inaturalist.org")) {
            if (extractStrictTaxonId(hp.path, "/taxa/", true)) |tx_id| {
                const api_url = try std.fmt.allocPrint(alloc, "https://api.inaturalist.org/v1/taxa/{s}", .{tx_id});
                const resp = try httpGetText(alloc, io, api_url, timeout_secs, allow_localhost);
                if (resp.status == 200) {
                    var found_taxon = false;
                    if (std.json.parseFromSliceLeaky(std.json.Value, alloc, resp.body, .{})) |pv| {
                        if (pv == .object) {
                            if (pv.object.get("total_results")) |tr| {
                                if (tr == .integer and tr.integer >= 1) found_taxon = true;
                            }
                        }
                    } else |err| {
                        std.log.debug("inat api json parse failed: {s}", .{@errorName(err)});
                    }
                    if (found_taxon) {
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
    const resp = try httpGetText(alloc, io, uri, timeout_secs, allow_localhost);
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

fn isNullPlaceholderStr(s: []const u8) bool {
    const t = std.mem.trim(u8, s, " \t\r\n");
    return t.len == 0 or
        std.ascii.eqlIgnoreCase(t, "n/a") or
        std.ascii.eqlIgnoreCase(t, "[n/a]") or
        std.ascii.eqlIgnoreCase(t, "none") or
        std.ascii.eqlIgnoreCase(t, "null");
}

fn collectDeclaredUrls(alloc: std.mem.Allocator, val: std.json.Value, out: *std.ArrayList([]const u8)) !void {
    switch (val) {
        .object => |obj| {
            var it = obj.iterator();
            while (it.next()) |ent| {
                const k = ent.key_ptr.*;
                const is_url_key = std.mem.eql(u8, k, "doi_or_url") or
                    std.mem.eql(u8, k, "source_url") or
                    std.mem.eql(u8, k, "url") or
                    std.mem.eql(u8, k, "href") or
                    std.mem.eql(u8, k, "doi") or
                    std.mem.eql(u8, k, "uri") or
                    std.mem.eql(u8, k, "link");
                if (is_url_key and ent.value_ptr.* == .string) {
                    const s = stripTrailingPunct(ent.value_ptr.*.string);
                    if (!isNullPlaceholderStr(s)) {
                        // Never silently drop malformed non-empty URL strings — surface them to validateUriSyntax!
                        try out.append(alloc, try alloc.dupe(u8, s));
                    }
                } else if (std.mem.eql(u8, k, "urls") and ent.value_ptr.* == .array) {
                    for (ent.value_ptr.*.array.items) |uitem| {
                        if (uitem == .string) {
                            const s = stripTrailingPunct(uitem.string);
                            if (!isNullPlaceholderStr(s)) try out.append(alloc, try alloc.dupe(u8, s));
                        } else {
                            try collectDeclaredUrls(alloc, uitem, out);
                        }
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
    return ch > 32 and ch < 127 and ch != '<' and ch != '>' and ch != '"' and ch != '\'' and ch != '[' and ch != ']';
}

const TextRes = struct { page: usize, raw: []const u8, canonical: []const u8 };

fn stripInvisibleUtf8(alloc: std.mem.Allocator, raw_in: []const u8) ![]u8 {
    var norm: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < raw_in.len) {
        const b0 = raw_in[i];
        if (b0 < 0x80) {
            try norm.append(alloc, b0);
            i += 1;
            continue;
        }
        const seq_len = std.unicode.utf8ByteSequenceLength(b0) catch {
            i += 1;
            continue;
        };
        if (i + seq_len > raw_in.len) break;
        const cp = std.unicode.utf8Decode(raw_in[i .. i + seq_len]) catch {
            i += 1;
            continue;
        };
        if (cp == 0x00AD or (cp >= 0x200B and cp <= 0x200F) or (cp >= 0x2060 and cp <= 0x2064) or cp == 0xFEFF) {
            i += seq_len;
            continue;
        }
        try norm.appendSlice(alloc, raw_in[i .. i + seq_len]);
        i += seq_len;
    }
    return norm.toOwnedSlice(alloc);
}

fn scanUrlEndWithWrap(text: []const u8, start: usize) usize {
    var k = start;
    while (k < text.len and isUrlBodyChar(text[k])) : (k += 1) {}
    // Handle line-wrapped URLs/DOIs broken right after '/', '-', '_', '%', '&', '?', '='
    while (k < text.len and (text[k] == '\n' or text[k] == '\r')) {
        if (k == start) break;
        const prev = text[k - 1];
        if (prev != '/' and prev != '-' and prev != '_' and prev != '%' and prev != '&' and prev != '?' and prev != '=') break;
        var next_i = k;
        while (next_i < text.len and (text[next_i] == '\r' or text[next_i] == '\n' or text[next_i] == ' ' or text[next_i] == '\t')) : (next_i += 1) {}
        if (next_i >= text.len or !isUrlBodyChar(text[next_i])) break;
        if (startsWithFold(text[next_i..], "http://") or startsWithFold(text[next_i..], "https://")) break;
        k = next_i;
        while (k < text.len and isUrlBodyChar(text[k])) : (k += 1) {}
    }
    return k;
}

fn compactWrappedToken(alloc: std.mem.Allocator, slice: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    for (slice) |ch| {
        if (ch == '\r' or ch == '\n' or ch == ' ' or ch == '\t') continue;
        try out.append(alloc, ch);
    }
    return out.toOwnedSlice(alloc);
}

fn scanTextResources(alloc: std.mem.Allocator, page_num: usize, raw_in: []const u8, out: *std.ArrayList(TextRes)) !void {
    const text = try stripInvisibleUtf8(alloc, raw_in);
    defer alloc.free(text);

    var seen = std.StringHashMap(void).init(alloc);
    defer seen.deinit();

    var i: usize = 0;
    while (i < text.len) {
        if (startsWithFold(text[i..], "http://") or startsWithFold(text[i..], "https://")) {
            const k = scanUrlEndWithWrap(text, i);
            const joined = try compactWrappedToken(alloc, text[i..k]);
            defer alloc.free(joined);
            const u = stripTrailingPunct(joined);
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
        const prev_ok = (i == 0) or (!isAsciiAlnum(text[i - 1]) and text[i - 1] != '/' and text[i - 1] != '@' and text[i - 1] != '.');
        if (prev_ok and startsWithFold(text[i..], "www.")) {
            const k = scanUrlEndWithWrap(text, i);
            const joined = try compactWrappedToken(alloc, text[i..k]);
            defer alloc.free(joined);
            const bare = stripTrailingPunct(joined);
            // Must have at least 2 dots (www.domain.tld) and alphabetic TLD
            if (bare.len > 7 and std.mem.findScalarPos(u8, bare, 4, '.') != null) {
                const full = try std.fmt.allocPrint(alloc, "https://{s}", .{bare});
                defer alloc.free(full);
                const ck = try canonicalKey(alloc, full);
                if (!seen.contains(ck)) {
                    try seen.put(ck, {});
                    try out.append(alloc, .{ .page = page_num, .raw = try alloc.dupe(u8, bare), .canonical = ck });
                }
            }
            i = k;
            continue;
        }
        if (prev_ok and looksLikeDoi(text[i..])) {
            const k = scanUrlEndWithWrap(text, i);
            const joined = try compactWrappedToken(alloc, text[i..k]);
            defer alloc.free(joined);
            const d = stripTrailingPunct(joined);
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
    var valid_clickable_keys = std.StringHashMap(void).init(alloc);
    var valid_page_keys = std.StringHashMap(void).init(alloc);
    var unique_valid: std.ArrayList([]const u8) = .empty;
    var seen_probe = std.StringHashMap(void).init(alloc);
    var uri_to_page = std.StringHashMap(usize).init(alloc);
    var valid_clickable_count: usize = 0;

    for (clickable) |lnk| {
        if (!uri_to_page.contains(lnk.uri)) {
            try uri_to_page.put(lnk.uri, lnk.page);
        }
        const pw: f64 = if (lnk.page >= 1 and lnk.page <= pages.len) pages[lnk.page - 1].width else 612.0;
        const ph: f64 = if (lnk.page >= 1 and lnk.page <= pages.len) pages[lnk.page - 1].height else 792.0;

        // Visible clipped on-page hit-box check (defeats partially off-page 0.1pt overlap links)
        const vx0 = std.math.clamp(lnk.x0, 0.0, pw);
        const vx1 = std.math.clamp(lnk.x1, 0.0, pw);
        const vy0 = std.math.clamp(lnk.y0, 0.0, ph);
        const vy1 = std.math.clamp(lnk.y1, 0.0, ph);
        const vw = vx1 - vx0;
        const vh = vy1 - vy0;
        var link_valid = true;

        if (lnk.is_hidden) {
            link_valid = false;
            try failures.append(alloc, .{
                .page = lnk.page,
                .kind = "DEGENERATE_OR_HIDDEN_LINK_RECT",
                .uri = lnk.uri,
                .detail = try std.fmt.allocPrint(alloc, "Clickable link has PDF /F Hidden flag set: {s}", .{lnk.uri}),
            });
        }
        if (lnk.is_extra_action) {
            link_valid = false;
            try failures.append(alloc, .{
                .page = lnk.page,
                .kind = "NONSTANDARD_AA_LINK_ACTION",
                .uri = lnk.uri,
                .detail = try std.fmt.allocPrint(alloc, "Non-standard /AA link action is disallowed (use standard /A /URI): {s}", .{lnk.uri}),
            });
        }
        if (vw < 2.0 or vh < 2.0) {
            link_valid = false;
            try failures.append(alloc, .{
                .page = lnk.page,
                .kind = "DEGENERATE_OR_HIDDEN_LINK_RECT",
                .uri = lnk.uri,
                .detail = try std.fmt.allocPrint(alloc, "Visible on-page rect [{d:.1},{d:.1},{d:.1},{d:.1}] ({d:.1}x{d:.1}pt) is degenerate (<2x2 pt) or off-page", .{ lnk.x0, lnk.y0, lnk.x1, lnk.y1, vw, vh }),
            });
        }
        if (validateUriSyntax(lnk.uri, allow_localhost)) |syn_err| {
            link_valid = false;
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

        // Only genuinely visible, valid, non-hidden links satisfy Rule 11A / 11B and min_links!
        if (link_valid) {
            valid_clickable_count += 1;
            const ck = try canonicalKey(alloc, lnk.uri);
            try valid_clickable_keys.put(ck, {});
            const page_ck = try std.fmt.allocPrint(alloc, "{d}:{s}", .{ lnk.page, ck });
            try valid_page_keys.put(page_ck, {});
        }
    }

    if (valid_clickable_count < min_links) {
        try failures.append(alloc, .{
            .page = 0,
            .kind = "INSUFFICIENT_CLICKABLE_LINKS",
            .uri = "",
            .detail = try std.fmt.allocPrint(alloc, "Found {d} valid clickable external link(s), minimum required is {d}", .{ valid_clickable_count, min_links }),
        });
    }

    // Rule 11A: Every URL or DOI printed in PDF text MUST have an exact canonical clickable annotation on the SAME page
    var text_res: std.ArrayList(TextRes) = .empty;
    for (pages) |pg| {
        try scanTextResources(alloc, pg.page_num, pg.prose_text, &text_res);
    }
    for (text_res.items) |tr| {
        const page_ck = try std.fmt.allocPrint(alloc, "{d}:{s}", .{ tr.page, tr.canonical });
        if (!valid_page_keys.contains(page_ck)) {
            try failures.append(alloc, .{
                .page = tr.page,
                .kind = "UNLINKED_TEXT_RESOURCE",
                .uri = tr.raw,
                .detail = try std.fmt.allocPrint(alloc, "Printed URL/DOI '{s}' on page {d} has no matching clickable PDF /URI annotation on that page", .{ tr.raw, tr.page }),
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
        const check_uri = if (std.mem.find(u8, du, "://") != null)
            du
        else if (startsWithFold(du, "doi:"))
            try std.fmt.allocPrint(alloc, "https://doi.org/{s}", .{std.mem.trimStart(u8, du[4..], " \t")})
        else if (looksLikeDoi(du))
            try std.fmt.allocPrint(alloc, "https://doi.org/{s}", .{du})
        else
            du;
        if (validateUriSyntax(check_uri, allow_localhost)) |syn_err| {
            try failures.append(alloc, .{
                .page = 0,
                .kind = syn_err,
                .uri = du,
                .detail = try std.fmt.allocPrint(alloc, "Declared citation/ledger URI invalid: {s}", .{du}),
            });
            continue;
        }
        if (!valid_clickable_keys.contains(ck)) {
            try failures.append(alloc, .{
                .page = 0,
                .kind = "DECLARED_RESOURCE_NOT_CLICKABLE",
                .uri = du,
                .detail = try std.fmt.allocPrint(alloc, "Resource '{s}' declared in citations/ledger is missing a valid clickable link in the PDF", .{du}),
            });
        }
    }

    // Rule 11C: Live Anti-Hallucination Verification
    var live_results: std.ArrayList(LiveLinkResult) = .empty;
    if (live) {
        for (unique_valid.items) |u| {
            const lr = try verifyLiveUri(alloc, io, u, timeout_secs, allow_localhost);
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
        .clickable_links = valid_clickable_count,
        .unique_uris = unique_valid.items.len,
        .text_resources = text_res.items.len,
        .declared_resources = decl_count,
        .live_checked = live,
        .live_results = try live_results.toOwnedSlice(alloc),
        .failures = flist,
        .passed = flist.len == 0,
    };
}

test "validateUriSyntax rejects SSRF/placeholders/inet_aton/trailing-dot and accepts valid IPv6 and mastodon" {
    try std.testing.expect(validateUriSyntax("https://doi.org/10.1038/nature02417", false) == null);
    try std.testing.expect(validateUriSyntax("https://mastodon.social/@astro", false) == null);
    try std.testing.expect(validateUriSyntax("https://en.wikipedia.org/wiki/Todos_los_santos", false) == null);
    try std.testing.expect(validateUriSyntax("http://[2606:2800:220:1:248:1893:25c8:1946]/", false) == null);

    try std.testing.expect(validateUriSyntax("https://example.com/fake", false) != null);
    try std.testing.expect(validateUriSyntax("https://api.example.com/fake", false) != null);
    try std.testing.expect(validateUriSyntax("https://example.com./fake", false) != null);
    try std.testing.expect(validateUriSyntax("http://localhost./x", false) != null);
    try std.testing.expect(validateUriSyntax("http://127.0.0.1:8080/x", false) != null);
    try std.testing.expect(validateUriSyntax("http://127.1/x", false) != null);
    try std.testing.expect(validateUriSyntax("http://0177.0.0.1/x", false) != null);
    try std.testing.expect(validateUriSyntax("http://2130706433/x", false) != null);
    try std.testing.expect(validateUriSyntax("http://169.254.169.254/latest/meta-data/", false) != null);
    try std.testing.expect(validateUriSyntax("http://10.0.0.1/x", false) != null);
    try std.testing.expect(validateUriSyntax("http://[::ffff:127.0.0.1]/x", false) != null);
    try std.testing.expect(validateUriSyntax("http://[fc00::1]/x", false) != null);
    try std.testing.expect(validateUriSyntax("http://127.0.0.1:8080/x", true) == null);
    try std.testing.expect(validateUriSyntax("javascript:alert(1)", false) != null);
    try std.testing.expect(validateUriSyntax("https://site.invalid/paper", false) != null);
    try std.testing.expect(validateUriSyntax("https://site.org/todo", false) != null);
    try std.testing.expect(validateUriSyntax("https://todo.site.org/paper", false) != null);
}

test "extractDoiFromUri rejects spoofed publisher substrings and dead nature subpaths" {
    const alloc = std.testing.allocator;
    const d1 = (try extractDoiFromUri(alloc, "https://doi.org/10.1016/j.ejor.2005.12.009")).?;
    defer alloc.free(d1);
    try std.testing.expectEqualStrings("10.1016/j.ejor.2005.12.009", d1);

    const d2 = (try extractDoiFromUri(alloc, "https://www.nature.com/articles/s41586-026-99999-z")).?;
    defer alloc.free(d2);
    try std.testing.expectEqualStrings("10.1038/s41586-026-99999-z", d2);

    // Substring publisher spoof MUST NOT match as a DOI shortcut
    try std.testing.expect((try extractDoiFromUri(alloc, "https://evil-aps.org.attacker.com/10.1038/nature02417")) == null);
    // Dead subpath on nature.com MUST NOT shortcut to DOI handle API
    try std.testing.expect((try extractDoiFromUri(alloc, "https://www.nature.com/articles/nature02417/nonexistent")) == null);
    // Strict taxon ID rejects dead subpaths
    try std.testing.expect(extractStrictTaxonId("/taxa/47792/totally-fake-subpath", "/taxa/", true) == null);
    try std.testing.expectEqualStrings("47792", extractStrictTaxonId("/taxa/47792-Quercus-alba", "/taxa/", true).?);

    const k1 = try canonicalKey(alloc, "doi:10.1038/NATURE02417.");
    defer alloc.free(k1);
    const k2 = try canonicalKey(alloc, "https://dx.doi.org/10.1038/nature02417");
    defer alloc.free(k2);
    try std.testing.expectEqualStrings(k1, k2);
}

test "classifySoft404OrChallenge and extractTagInner defeat comments, SVG titles, entities, and soft-404s" {
    const alloc = std.testing.allocator;
    const html = "<!-- <title>Fake OK</title> --><svg><title>Icon</title></svg><title>404 &ndash; We Couldn&#39;t Find That Page</title>";
    const t = try extractTagInner(alloc, html, "<title", "</title>");
    defer alloc.free(t);
    try std.testing.expectEqualStrings("404 - We Couldn't Find That Page", t);
    try std.testing.expect(classifySoft404OrChallenge(t, "", html) != null);
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
