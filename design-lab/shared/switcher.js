/* Icarus design lab: the list of designs (used by index.html) and the floating switcher
   that every prototype loads with <script src="shared/switcher.js" defer></script>.
   The switcher lives in a shadow root, so a design's CSS cannot break it and it cannot
   break the design. It is a small tab on the right edge: tap for the list, drag to move. */
(function () {
  "use strict";
  var DESIGNS = [
    { n: 1, file: "d01-sundial.html", name: "Gnomon", idea: "A brass sundial you turn with your thumb.",
      swatch: ["#efe3c8", "#b8863b", "#3f7f6e", "#2a2118"],
      rationale: "Skeuomorphic instrument. The slot is set by dragging the gnomon's shadow around an engraved dial; the answer is engraved on the plate. Warm brass, verdigris and parchment, old-style serif numerals, heavy mechanical easing. Asks: should planning feel like handling a precise physical object?" },
    { n: 2, file: "d02-editorial.html", name: "The Daily Dose", idea: "Today's answer as a front-page broadsheet.",
      swatch: ["#f3efe6", "#151515", "#d6361f", "#8a8577"],
      rationale: "Editorial newspaper. Your answer is the lead story, the forecast is the weather box, Learn is the long read with drop caps and footnoted sources. Big condensed serif headlines, hairline rules, one spot red. Navigation by sections in a masthead. Asks: does honesty read best as journalism?" },
    { n: 3, file: "d03-corona.html", name: "Corona", idea: "A dark observatory where the sun is the interface.",
      swatch: ["#05060b", "#ff7a1a", "#ffd27a", "#3b2a6b"],
      rationale: "Night sky and solar physics. A glowing, living sun sits in a black field; the day's UV is an orbit arc you scrub along, and your slot is a lit segment of it. Particles, glow, slow orbital motion, an orbit-ring menu instead of tabs. Asks: can the app feel like looking at the sun itself, safely?" },
    { n: 4, file: "d04-dosimeter.html", name: "Dosimeter", idea: "A precise hardware instrument with knobs and an LCD.",
      swatch: ["#e7e4dc", "#ff5a1f", "#1d1d1b", "#a9b59a"],
      rationale: "Industrial device in the spirit of lab meters and pocket synths. Rotary knobs, toggle switches, a segment LCD readout, mode keys instead of a tab bar, a printed-receipt history. Off-white plastic, black and signal orange, monospace. Asks: should the number feel measured, not suggested?" },
    { n: 5, file: "d05-silhouette.html", name: "Silhouette", idea: "Your body is the screen: regions fill as dose builds.",
      swatch: ["#efe2d3", "#c9714f", "#3b2620", "#e9b48a"],
      rationale: "Spatial, body-first. A large sculpted figure turns front to back; each region (front, back, head and shoulders) fills with today's dose against its own budget, and tapping a region opens its numbers. The flip timer literally turns the figure. Clay, sand and umber, gallery calm. Asks: is the body the clearest way to show three budgets?" },
    { n: 6, file: "d06-chat.html", name: "Ask Helio", idea: "A conversation with a frank little sun.",
      swatch: ["#fff6e0", "#ffcf3f", "#ff6f91", "#6c5ce7"],
      rationale: "Conversational and playful. Planning is a short chat: quick-reply chips for the slot and posture, then the answer arrives as rich cards in the thread. An animated sun character with moods (squints at UVA, frowns at a warning) keeps the real, plain copy company. Candy colours, chunky rounded type, springy bubbles. Asks: does a dialogue make the questions feel lighter?" },
    { n: 7, file: "d07-brutalist.html", name: "RAW", idea: "Brutalist: giant numbers, hard edges, no decoration.",
      swatch: ["#ffffff", "#000000", "#d4ff00", "#ff2e00"],
      rationale: "Brutalist and Swiss. Full-bleed stacked blocks, 200-pixel numerals, thick black rules, monospace labels, acid yellow for the action and red for the line you must not cross. Instant cuts instead of easing, a stacked index instead of tabs. Asks: what if the app shouted the number and nothing else?" },
    { n: 8, file: "d08-riviera.html", name: "Riviera", idea: "A 1960s screen-printed beach poster that moves.",
      swatch: ["#f4e7cf", "#e8573d", "#1f7a7a", "#f2b134"],
      rationale: "Retro travel poster. Flat screen-print colours with halftone and grain, a parasol whose shadow tracks your slot, ticket-stub cards and luggage-tag tabs, a beach towel that flips for the timer. Display type with personality, cheerful but still exact. Asks: can the app have warmth and nostalgia without losing its honesty?" },
    { n: 9, file: "d09-hinata.html", name: "Hinata", idea: "Minimal Japanese: washi paper, ink, one vermilion seal.",
      swatch: ["#f5f0e6", "#23211f", "#c8402f", "#b9b1a3"],
      rationale: "Quiet and minimal, after Japanese print and book design. Washi texture, generous emptiness, a single ink brush arc for the day's UV, a vermilion hanko stamp to log a session, pages that slide horizontally like a scroll. Slow ink-bleed transitions, mincho serif. Asks: can calm and restraint carry a serious message?" },
    { n: 10, file: "d10-halo.html", name: "Halo", idea: "A glassy weather app with a live sky behind everything.",
      swatch: ["#3a7bd5", "#f6a15b", "#ffffff", "#7fd1ff"],
      rationale: "Atmospheric and native-feeling, after weather apps and visionOS. A full-screen sky that changes with the time of day, frosted-glass cards, thin oversized numerals, an hourly UV strip you can scrub, cards that stack and page vertically. The closest to iOS, but full of colour. Asks: is the fix just colour, light and depth?" }
  ];
  window.ICARUS_DESIGNS = DESIGNS;

  function current() {
    var f = (location.pathname.split("/").pop() || "").toLowerCase();
    for (var i = 0; i < DESIGNS.length; i++) if (DESIGNS[i].file === f) return i;
    return -1;
  }

  function mount() {
    if (document.body.hasAttribute("data-no-switcher")) return;
    var idx = current();
    if (idx < 0) return; // index.html renders its own list
    var host = document.createElement("div");
    host.id = "icarus-switcher";
    host.style.cssText = "position:fixed;inset:auto;z-index:2147483000;";
    document.body.appendChild(host);
    var root = host.attachShadow ? host.attachShadow({ mode: "open" }) : host;
    var d = DESIGNS[idx];
    var prev = DESIGNS[(idx + DESIGNS.length - 1) % DESIGNS.length];
    var next = DESIGNS[(idx + 1) % DESIGNS.length];
    var y = 0.42;
    try { var sv = sessionStorage.getItem("icarus-lab:switcher-y"); if (sv) y = Math.min(0.85, Math.max(0.12, +sv)); } catch (e) {}

    root.innerHTML =
      '<style>' +
      ':host{all:initial}' +
      '*{box-sizing:border-box;-webkit-tap-highlight-color:transparent;font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text","Segoe UI",Roboto,sans-serif}' +
      '.tab{position:fixed;right:0;width:30px;height:52px;border-radius:14px 0 0 14px;background:rgba(20,20,22,.72);' +
      '-webkit-backdrop-filter:blur(10px);backdrop-filter:blur(10px);color:#fff;display:flex;flex-direction:column;align-items:center;justify-content:center;' +
      'gap:3px;cursor:pointer;touch-action:none;user-select:none;-webkit-user-select:none;box-shadow:0 2px 10px rgba(0,0,0,.25),inset 0 0 0 .5px rgba(255,255,255,.25);' +
      'transition:transform .25s cubic-bezier(.2,.9,.3,1.2),opacity .2s;opacity:.82;z-index:2}' +
      '.tab:active{transform:scale(.94)}' +
      '.tab b{font-size:12px;font-weight:700;letter-spacing:.02em;line-height:1}' +
      '.tab i{display:block;width:12px;height:12px;border-radius:50%;background:conic-gradient(' + d.swatch.join(",") + ',' + d.swatch[0] + ');box-shadow:0 0 0 1.5px rgba(255,255,255,.7)}' +
      '.scrim{position:fixed;inset:0;background:rgba(0,0,0,.38);opacity:0;pointer-events:none;transition:opacity .25s;z-index:3}' +
      '.sheet{position:fixed;left:0;right:0;bottom:0;max-width:480px;margin:0 auto;background:rgba(24,24,27,.94);-webkit-backdrop-filter:blur(24px) saturate(1.4);' +
      'backdrop-filter:blur(24px) saturate(1.4);color:#f4f4f5;border-radius:22px 22px 0 0;padding:8px 14px calc(14px + env(safe-area-inset-bottom));' +
      'transform:translateY(105%);transition:transform .42s cubic-bezier(.2,.9,.25,1);z-index:4;max-height:86vh;overflow:auto;box-shadow:0 -10px 40px rgba(0,0,0,.35)}' +
      '.open .scrim{opacity:1;pointer-events:auto}.open .sheet{transform:none}' +
      '.grab{width:38px;height:5px;border-radius:3px;background:rgba(255,255,255,.28);margin:2px auto 10px}' +
      '.h{display:flex;align-items:baseline;justify-content:space-between;margin:0 4px 10px}' +
      '.h span{font-size:12px;letter-spacing:.08em;text-transform:uppercase;color:rgba(255,255,255,.55)}' +
      '.h a{font-size:14px;color:#ffcf6a;text-decoration:none;font-weight:600}' +
      '.nav{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-bottom:12px}' +
      '.nav a{display:flex;flex-direction:column;gap:2px;padding:10px 12px;border-radius:14px;background:rgba(255,255,255,.08);color:#fff;text-decoration:none}' +
      '.nav a small{font-size:11px;color:rgba(255,255,255,.55)}.nav a strong{font-size:15px}' +
      '.nav a:last-child{text-align:right;align-items:flex-end}' +
      '.list{display:grid;grid-template-columns:minmax(0,1fr);gap:4px}' +
      '.row{display:flex;min-width:0;align-items:center;gap:12px;padding:8px 8px;border-radius:12px;color:#fff;text-decoration:none}' +
      '.row:active{background:rgba(255,255,255,.1)}' +
      '.row.cur{background:rgba(255,207,106,.14);box-shadow:inset 0 0 0 1px rgba(255,207,106,.45)}' +
      '.sw{flex:0 0 40px;height:40px;border-radius:10px;overflow:hidden;display:grid;grid-template-columns:1fr 1fr;box-shadow:inset 0 0 0 .5px rgba(255,255,255,.2)}' +
      '.sw span{display:block}' +
      '.tx{min-width:0}.tx strong{display:block;font-size:15px}.tx small{display:block;font-size:12px;color:rgba(255,255,255,.6);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}' +
      '.num{margin-left:auto;font-size:12px;color:rgba(255,255,255,.45);font-variant-numeric:tabular-nums}' +
      '</style>' +
      '<div class="wrap">' +
      '<div class="tab" role="button" aria-label="Switch design (design ' + d.n + ' of ' + DESIGNS.length + ')"><i></i><b>' + d.n + '</b></div>' +
      '<div class="scrim"></div>' +
      '<div class="sheet" role="dialog" aria-label="Designs">' +
      '<div class="grab"></div>' +
      '<div class="h"><span>Design ' + d.n + ' of ' + DESIGNS.length + ' · ' + d.name + '</span><a href="index.html">All designs</a></div>' +
      '<div class="nav"><a href="' + prev.file + '"><small>‹ Previous</small><strong>' + prev.name + '</strong></a>' +
      '<a href="' + next.file + '"><small>Next ›</small><strong>' + next.name + '</strong></a></div>' +
      '<div class="list">' + DESIGNS.map(function (x, i) {
        return '<a class="row' + (i === idx ? " cur" : "") + '" href="' + x.file + '"><div class="sw">' +
          x.swatch.map(function (c) { return '<span style="background:' + c + '"></span>'; }).join("") +
          '</div><div class="tx"><strong>' + x.name + '</strong><small>' + x.idea + '</small></div><span class="num">' + String(x.n).padStart(2, "0") + '</span></a>';
      }).join("") + '</div></div></div>';

    var wrap = root.querySelector(".wrap"), tab = root.querySelector(".tab");
    function place() { tab.style.top = "calc(" + (y * 100) + "% - 26px)"; }
    place();
    function open() { wrap.classList.add("open"); try { window.ICARUS && ICARUS.haptic(); } catch (e) {} }
    function close() { wrap.classList.remove("open"); }
    root.querySelector(".scrim").addEventListener("click", close);

    // Drag vertically to move the tab out of the way; a tap opens the sheet.
    var startY = 0, startPos = 0, moved = false, down = false;
    tab.addEventListener("pointerdown", function (e) {
      down = true; moved = false; startY = e.clientY; startPos = y;
      try { tab.setPointerCapture(e.pointerId); } catch (er) {}
    });
    tab.addEventListener("pointermove", function (e) {
      if (!down) return;
      var dy = e.clientY - startY;
      if (Math.abs(dy) > 6) moved = true;
      if (moved) { y = Math.min(0.85, Math.max(0.12, startPos + dy / window.innerHeight)); place(); }
    });
    tab.addEventListener("pointerup", function () {
      if (!down) return; down = false;
      if (moved) { try { sessionStorage.setItem("icarus-lab:switcher-y", String(y)); } catch (e) {} }
      else open();
    });
    tab.addEventListener("pointercancel", function () { down = false; });

    // Swipe the sheet down to close it.
    var sheet = root.querySelector(".sheet"), sy = null;
    sheet.addEventListener("touchstart", function (e) { if (sheet.scrollTop <= 0) sy = e.touches[0].clientY; }, { passive: true });
    sheet.addEventListener("touchmove", function (e) {
      if (sy == null) return; var dy = e.touches[0].clientY - sy;
      if (dy > 0) { sheet.style.transition = "none"; sheet.style.transform = "translateY(" + dy + "px)"; }
    }, { passive: true });
    sheet.addEventListener("touchend", function (e) {
      if (sy == null) return; var dy = e.changedTouches[0].clientY - sy; sy = null;
      sheet.style.transition = ""; sheet.style.transform = "";
      if (dy > 90) close();
    });

    // Desktop: [ and ] jump between designs, Escape closes.
    document.addEventListener("keydown", function (e) {
      if (e.target && /input|textarea|select/i.test(e.target.tagName)) return;
      if (e.key === "]") location.href = next.file;
      else if (e.key === "[") location.href = prev.file;
      else if (e.key === "Escape") close();
    });
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", mount);
  else mount();
})();
