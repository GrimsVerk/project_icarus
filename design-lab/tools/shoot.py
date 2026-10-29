"""Render a design-lab page at iPhone 16 size and take screenshots along a click path.

Usage:
  python shoot.py <page.html> <out_prefix> [step ...]
Steps (run in order):
  shot:<name>          screenshot -> <out_prefix>-<name>.png
  click:<css>          click first match (use text=Foo for Playwright text selectors)
  tap:<x>,<y>          click at viewport coordinates
  wait:<ms>            sleep
  scroll:<css>:<px>    scroll element (or 'page') by px
  js:<code>            evaluate JS
Always prints console errors, page errors and horizontal overflow at the end.
"""
import sys, pathlib
from playwright.sync_api import sync_playwright

page_path, prefix, steps = sys.argv[1], sys.argv[2], sys.argv[3:]
url = pathlib.Path(page_path).resolve().as_uri()
errors = []
with sync_playwright() as p:
    b = p.chromium.launch(channel="chrome", headless=True)
    ctx = b.new_context(viewport={"width": 390, "height": 844}, device_scale_factor=1,
                        is_mobile=True, has_touch=True,
                        user_agent="Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1")
    pg = ctx.new_page()
    pg.on("console", lambda m: errors.append(f"console.{m.type}: {m.text}") if m.type in ("error", "warning") else None)
    pg.on("pageerror", lambda e: errors.append(f"pageerror: {e}"))
    pg.goto(url, wait_until="networkidle", timeout=30000)
    pg.wait_for_timeout(800)
    if not steps:
        steps = ["shot:home"]
    for s in steps:
        kind, _, arg = s.partition(":")
        try:
            if kind == "shot":
                pg.screenshot(path=f"{prefix}-{arg}.png")
                print("saved", f"{prefix}-{arg}.png")
            elif kind == "click":
                pg.locator(arg).first.click(timeout=5000)
                pg.wait_for_timeout(500)
            elif kind == "tap":
                x, y = arg.split(",")
                pg.mouse.click(float(x), float(y))
                pg.wait_for_timeout(500)
            elif kind == "wait":
                pg.wait_for_timeout(int(arg))
            elif kind == "scroll":
                sel, _, px = arg.rpartition(":")
                if sel == "page":
                    pg.mouse.wheel(0, int(px))
                else:
                    pg.locator(sel).first.evaluate(f"e => e.scrollBy(0, {int(px)})")
                pg.wait_for_timeout(400)
            elif kind == "js":
                print("js ->", pg.evaluate(arg))
        except Exception as e:
            errors.append(f"step {s!r} failed: {str(e).splitlines()[0]}")
    ov = pg.evaluate("() => [document.documentElement.scrollWidth, document.body.scrollWidth]")
    if max(ov) > 391:
        errors.append(f"HORIZONTAL OVERFLOW: scrollWidth={ov}")
    b.close()
print("\n".join(errors) if errors else "no errors, no overflow")
