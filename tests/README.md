# Sovereign Zig 0.17.0 Test Court

All adversarial sabotage, differential kernel, live local HTTP Rule 11, flagship regression, and zero-Python closed-loop synthesis tests live in pure Zig 0.17.0:

- **Fast Unit & Differential Kernel Tests:** [`zig/src/main.zig`](../zig/src/main.zig), [`zig/src/mupdf.zig`](../zig/src/mupdf.zig), [`zig/src/audit.zig`](../zig/src/audit.zig), [`zig/src/links.zig`](../zig/src/links.zig), [`zig/src/media.zig`](../zig/src/media.zig)
- **Full Adversarial Sabotage & Flagship Court (`33` test blocks):** [`zig/src/court_tests.zig`](../zig/src/court_tests.zig)

```bash
cd zig
zig build test && zig build test --release=safe
zig build test-court && zig build test-court --release=safe
```
