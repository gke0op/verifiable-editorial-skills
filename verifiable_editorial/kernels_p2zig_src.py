"""Pure typed mathematical & editorial-dissection kernels for sovereign p2zig transpilation.

Every function in this module obeys the p2zig Phase-1 verified subset (`int`, `bool`, `list[int]` ABI
with full internal IEEE-754 float math) so `/path/to/p2zig --strict` compiles 100% of this file
into zero-Python Zig 0.17.0 (`zig/src/kernels_p2zig.zig`) with WRONG = 0 differential parity.
"""


def rel_channel_x1000000(v: int) -> int:
    s = v / 255.0
    if s <= 0.04045:
        return int((s / 12.92) * 1000000.0 + 0.5)
    return int((((s + 0.055) / 1.055) ** 2.4) * 1000000.0 + 0.5)


def wcag_contrast_x100(r1: int, g1: int, b1: int, r2: int, g2: int, b2: int) -> int:
    l1 = (
        0.2126 * (rel_channel_x1000000(r1) / 1000000.0)
        + 0.7152 * (rel_channel_x1000000(g1) / 1000000.0)
        + 0.0722 * (rel_channel_x1000000(b1) / 1000000.0)
    )
    l2 = (
        0.2126 * (rel_channel_x1000000(r2) / 1000000.0)
        + 0.7152 * (rel_channel_x1000000(g2) / 1000000.0)
        + 0.0722 * (rel_channel_x1000000(b2) / 1000000.0)
    )
    hi = l1 if l1 >= l2 else l2
    lo = l2 if l1 >= l2 else l1
    return int(((hi + 0.05) / (lo + 0.05)) * 100.0 + 0.5)


def wcag_passes_aa(cr_x100: int, size_x10: int, is_bold: bool) -> bool:
    if size_x10 >= 180 or (size_x10 >= 140 and is_bold):
        return cr_x100 >= 300
    return cr_x100 >= 450


def cmyk_gcr_tac_x10(r: int, g: int, b: int) -> int:
    rf = r / 255.0
    gf = g / 255.0
    bf = b / 255.0
    mx = rf
    if gf > mx:
        mx = gf
    if bf > mx:
        mx = bf
    k_raw = 1.0 - mx
    if k_raw >= 0.999:
        return 2600
    c0 = (1.0 - rf - k_raw) / (1.0 - k_raw)
    m0 = (1.0 - gf - k_raw) / (1.0 - k_raw)
    y0 = (1.0 - bf - k_raw) / (1.0 - k_raw)
    k = k_raw * 0.80
    rem = k_raw * 0.20
    c = c0 * (1.0 - k_raw) + rem
    m = m0 * (1.0 - k_raw) + rem
    y = y0 * (1.0 - k_raw) + rem
    if c > 1.0:
        c = 1.0
    if m > 1.0:
        m = 1.0
    if y > 1.0:
        y = 1.0
    return int((c + m + y + k) * 1000.0 + 0.5)


def span_collision_kind(
    ax0: int,
    ay0: int,
    ax1: int,
    ay1: int,
    bx0: int,
    by0: int,
    bx1: int,
    by1: int,
    same_line: bool,
) -> int:
    aw = ax1 - ax0
    ah = ay1 - ay0
    bw = bx1 - bx0
    bh = by1 - by0
    if aw < 10 or ah < 10 or bw < 10 or bh < 10:
        return 0
    ay_pad = (ah * 20) // 100
    ax_pad = (aw * 10) // 100
    if ax_pad > 10:
        ax_pad = 10
    by_pad = (bh * 20) // 100
    bx_pad = (bw * 10) // 100
    if bx_pad > 10:
        bx_pad = 10
    ca0 = ax0 + ax_pad
    cb0 = ay0 + ay_pad
    ca1 = ax1 - ax_pad
    cb1 = ay1 - ay_pad
    da0 = bx0 + bx_pad
    db0 = by0 + by_pad
    da1 = bx1 - bx_pad
    db1 = by1 - by_pad
    if ca1 <= ca0 or cb1 <= cb0 or da1 <= da0 or db1 <= db0:
        return 0
    left = ca0 if ca0 >= da0 else da0
    right = ca1 if ca1 <= da1 else da1
    top = cb0 if cb0 >= db0 else db0
    bottom = cb1 if cb1 <= db1 else db1
    iw = right - left
    ih = bottom - top
    if iw <= 0 or ih <= 0:
        return 0
    min_h = ah if ah <= bh else bh
    if same_line:
        if iw > 35 and (ih * 100) > (35 * min_h):
            return 1
        return 0
    if iw > 25 and ih > 25:
        return 2
    return 0


def is_orphan_headline(w0_x10: int, w_last_x10: int, words_last: int, word_len: int) -> bool:
    if w0_x10 < 2600 or words_last != 1 or word_len > 15:
        return False
    return (w_last_x10 * 100) < (w0_x10 * 38)


def rule10_is_grounded_x100(val_x100: int, authorized_x100: list[int]) -> bool:
    for a in authorized_x100:
        diff = val_x100 - a
        if diff < 0:
            diff = -diff
        if diff <= 5:
            return True
    return False


def effective_dpi_x10(native_w: int, native_h: int, placed_w_x10: int, placed_h_x10: int) -> int:
    if native_w <= 0 or native_h <= 0 or placed_w_x10 <= 0 or placed_h_x10 <= 0:
        return 0
    dpi_w = (native_w * 720.0) / placed_w_x10
    dpi_h = (native_h * 720.0) / placed_h_x10
    lo = dpi_w if dpi_w <= dpi_h else dpi_h
    return int(lo * 10.0 + 0.5)


def detect_grid_columns(span_x0s: list[int], span_x1s: list[int], page_w: int) -> int:
    n = len(span_x0s)
    if n == 0 or page_w <= 0:
        return 1
    third = page_w // 3
    two_third = (page_w * 2) // 3
    half = page_w // 2
    left_only = 0
    mid_only = 0
    right_only = 0
    left_half = 0
    right_half = 0
    full_span = 0
    for i in range(n):
        x0 = span_x0s[i]
        x1 = span_x1s[i]
        w = x1 - x0
        if w < 18:
            continue
        if (w * 100) >= (page_w * 68):
            full_span += 1
        elif x1 <= third + 20:
            left_only += 1
        elif x0 >= third - 20 and x1 <= two_third + 20:
            mid_only += 1
        elif x0 >= two_third - 20:
            right_only += 1
        if x1 <= half + 28:
            left_half += 1
        elif x0 >= half - 28:
            right_half += 1
    if left_only >= 3 and mid_only >= 3 and right_only >= 3:
        return 3
    if left_half >= 3 and right_half >= 3:
        return 2
    if full_span > 0:
        return 1
    return 1


def classify_page_archetype(
    photo_pct_x10: int,
    text_spans: int,
    max_font_x10: int,
    col_count: int,
    page_idx: int,
    page_count: int,
) -> int:
    # 0=cover_hero, 1=full_bleed_plate, 2=split_photo_editorial,
    # 3=data_exhibit_ledger, 4=asymmetric_monograph, 5=colophon_references, 6=narrative_spread
    if page_idx == 1 and (max_font_x10 >= 220 or photo_pct_x10 >= 550):
        return 0
    if photo_pct_x10 >= 750:
        return 1
    if photo_pct_x10 >= 300:
        return 2
    if page_idx == page_count and page_count >= 3:
        return 5
    if text_spans >= 45:
        return 3
    if col_count >= 2:
        return 4
    return 6


def bleed_edge_count(left_px: int, right_px: int, top_px: int, bot_px: int, w: int, h: int) -> int:
    cnt = 0
    if left_px * 4 >= h:
        cnt += 1
    if right_px * 4 >= h:
        cnt += 1
    if top_px * 4 >= w:
        cnt += 1
    if bot_px * 4 >= w:
        cnt += 1
    return cnt


def coverage_passes(changed_px: int, total_px: int, min_pct_x10: int, bleed_edges: int, min_bleed_edges: int) -> bool:
    if total_px <= 0:
        return False
    pct_x10 = (changed_px * 1000) // total_px
    return pct_x10 >= min_pct_x10 and bleed_edges >= min_bleed_edges

