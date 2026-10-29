/* Icarus design lab: shared helpers and one consistent, plausible scenario.
   Load order in every prototype:
     <script src="shared/copy.js"></script>     (ICARUS_COPY, ICARUS_SKIN_TYPES, ICARUS_QUIZ; generated)
     <script src="shared/learn.js"></script>    (ICARUS_LEARN, 12 modules, verbatim; generated)
     <script src="shared/icarus.js"></script>   (this file: ICARUS.*)
     <script src="shared/switcher.js" defer></script>  (floating design switcher)
   The numbers below are invented for the prototypes but self-consistent: a type III user,
   2 skin reports, conservative setting, a clear June Saturday, forecast peak UVI 6.1 at 13:20. */
(function () {
  "use strict";
  var C = window.ICARUS_COPY || {};

  /* ---------- text ---------- */
  // t('planBareSubWindow', {minutes: 34}) -> copy line with placeholders filled.
  function t(key, vars) {
    var s = C[key];
    if (s == null) { console.warn("missing copy key", key); return key; }
    return fill(s, vars);
  }
  function fill(s, vars) {
    return String(s).replace(/\{(\w+)\}/g, function (m, k) {
      return vars && vars[k] != null ? vars[k] : m;
    });
  }
  // Split "[Module 6]" references out of a line: returns {text, modules:[6]}.
  function modules(s) {
    var mods = [];
    var text = String(s).replace(/\s*\[Module (\d+)\]/g, function (m, n) { mods.push(+n); return ""; }).trim();
    return { text: text, modules: mods };
  }
  // Same, but turns "[Module 6]" into <a class="learn-link" data-module="6">Module 6</a>.
  function linkify(s, label) {
    return esc(s).replace(/\[Module (\d+)\]/g, function (m, n) {
      var title = label === "title" ? moduleTitle(+n) : "Module " + n;
      return '<a class="learn-link" href="#learn/' + n + '" data-module="' + n + '">' + esc(title) + "</a>";
    });
  }
  function esc(s) {
    return String(s).replace(/[&<>"]/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]; });
  }
  function moduleTitle(n) {
    var m = (window.ICARUS_LEARN || []).filter(function (x) { return x.n === n; })[0];
    return m ? m.title : "Module " + n;
  }

  /* ---------- tiny markdown renderer for the Learn modules ----------
     Output classes: .md-h3 .md-p .md-ul .md-ol .md-table .md-quote .md-sources .md-formula
     Wrap the result in your own container and style it per design. */
  function inline(s) {
    s = esc(s);
    s = s.replace(/`\[VERIFY\]`/g, '<span class="md-verify">[VERIFY]</span>');
    s = s.replace(/`([^`]+)`/g, "<code>$1</code>");
    s = s.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
    s = s.replace(/\*([^*]+)\*/g, "<em>$1</em>");
    s = s.replace(/(https?:\/\/[^\s<)]+)/g, '<a class="md-url" style="overflow-wrap:anywhere;word-break:break-all" href="$1" target="_blank" rel="noopener">$1</a>');
    return s;
  }
  function md(src) {
    var lines = String(src).split("\n"), out = [], i = 0;
    function para(buf) { if (buf.length) out.push('<p class="md-p">' + inline(buf.join(" ")) + "</p>"); }
    var buf = [];
    while (i < lines.length) {
      var ln = lines[i];
      if (/^\s*$/.test(ln)) { para(buf); buf = []; i++; continue; }
      if (/^### /.test(ln)) { para(buf); buf = []; out.push('<h3 class="md-h3">' + inline(ln.slice(4)) + "</h3>"); i++; continue; }
      if (/^\|/.test(ln)) {
        para(buf); buf = [];
        var rows = [];
        while (i < lines.length && /^\|/.test(lines[i])) { rows.push(lines[i]); i++; }
        var cells = rows.filter(function (r) { return !/^\|[-\s|:]+\|$/.test(r); }).map(function (r) {
          return r.replace(/^\||\|$/g, "").split("|").map(function (c) { return c.trim(); });
        });
        var h = "<table class=\"md-table\"><thead><tr>" + cells[0].map(function (c) { return "<th>" + inline(c) + "</th>"; }).join("") + "</tr></thead><tbody>";
        cells.slice(1).forEach(function (r) { h += "<tr>" + r.map(function (c) { return "<td>" + inline(c) + "</td>"; }).join("") + "</tr>"; });
        out.push(h + "</tbody></table>");
        continue;
      }
      if (/^> ?/.test(ln)) {
        para(buf); buf = [];
        var q = [];
        while (i < lines.length && /^> ?/.test(lines[i])) { q.push(lines[i].replace(/^> ?/, "")); i++; }
        var isSources = /^\*\*Sources\*\*/.test(q[0]);
        if (isSources) {
          var items = q.slice(1).filter(function (x) { return /^- /.test(x); }).map(function (x) { return "<li>" + inline(x.slice(2)) + "</li>"; });
          out.push('<aside class="md-sources"><div class="md-sources-h">Sources</div><ul>' + items.join("") + "</ul></aside>");
        } else {
          var isFormula = q.length === 1 && /^\*\*.+\*\*$/.test(q[0]);
          out.push('<blockquote class="' + (isFormula ? "md-formula" : "md-quote") + '">' + md(q.join("\n")) + "</blockquote>");
        }
        continue;
      }
      if (/^- /.test(ln)) {
        para(buf); buf = [];
        var li = [];
        while (i < lines.length && /^- /.test(lines[i])) { li.push("<li>" + inline(lines[i].slice(2)) + "</li>"); i++; }
        out.push('<ul class="md-ul">' + li.join("") + "</ul>");
        continue;
      }
      if (/^\d+\. /.test(ln)) {
        para(buf); buf = [];
        var ol = [];
        while (i < lines.length && /^\d+\. /.test(lines[i])) { ol.push("<li>" + inline(lines[i].replace(/^\d+\. /, "")) + "</li>"); i++; }
        out.push('<ol class="md-ol">' + ol.join("") + "</ol>");
        continue;
      }
      buf.push(ln); i++;
    }
    para(buf);
    return out.join("\n");
  }

  /* ---------- haptics ----------
     iOS 18+ Safari: toggling a <input type=checkbox switch> via its label gives a real
     system haptic tick, but only inside a user gesture (call from a click/touch handler).
     Android/desktop: navigator.vibrate when present. Silent elsewhere. */
  var hapticLabel = null;
  function haptic(kind) {
    try {
      if (navigator.vibrate) navigator.vibrate(kind === "heavy" ? 18 : kind === "double" ? [8, 40, 8] : 8);
      if (!hapticLabel) {
        hapticLabel = document.createElement("label");
        hapticLabel.setAttribute("aria-hidden", "true");
        hapticLabel.style.cssText = "position:fixed;left:-9999px;top:0;width:1px;height:1px;overflow:hidden;opacity:0;pointer-events:none";
        var inp = document.createElement("input");
        inp.type = "checkbox"; inp.setAttribute("switch", ""); inp.tabIndex = -1;
        hapticLabel.appendChild(inp);
        document.body.appendChild(hapticLabel);
      }
      hapticLabel.click();
      if (kind === "double") setTimeout(function () { try { hapticLabel.click(); } catch (e) {} }, 90);
    } catch (e) { /* no haptics here */ }
  }

  /* ---------- storage that never breaks the page ---------- */
  var store = {
    get: function (k, d) { try { var v = sessionStorage.getItem("icarus-lab:" + k); return v == null ? d : JSON.parse(v); } catch (e) { return d; } },
    set: function (k, v) { try { sessionStorage.setItem("icarus-lab:" + k, JSON.stringify(v)); } catch (e) {} }
  };

  /* ---------- the scenario ---------- */
  // Prototype clock: Saturday 13 June 2026, 11:42. Use ICARUS.now for "now".
  var now = { day: "Saturday 13 June", weekday: "Saturday", date: "13 June", time: "11:42", minutes: 11 * 60 + 42 };

  // Hourly UV index for today, local time (Northern Europe, clear June day, some high cloud after 16:00).
  var uvHourly = [
    { h: 5, uvi: 0.0 }, { h: 6, uvi: 0.2 }, { h: 7, uvi: 0.6 }, { h: 8, uvi: 1.4 }, { h: 9, uvi: 2.5 },
    { h: 10, uvi: 3.7 }, { h: 11, uvi: 4.8 }, { h: 12, uvi: 5.6 }, { h: 13, uvi: 6.0 }, { h: 14, uvi: 5.7 },
    { h: 15, uvi: 4.9 }, { h: 16, uvi: 3.8 }, { h: 17, uvi: 2.6 }, { h: 18, uvi: 1.5 }, { h: 19, uvi: 0.7 },
    { h: 20, uvi: 0.2 }, { h: 21, uvi: 0.0 }, { h: 22, uvi: 0.0 }
  ];
  // Smooth UVI at any minute of the day (cosine-ish bell around solar noon 13:20, peak 6.1).
  function uvAt(minuteOfDay) {
    var noon = 13 * 60 + 20, half = 7.6 * 60; // sunrise ~04:00, sunset ~22:40; UV meaningful ~06-20
    var x = (minuteOfDay - noon) / half;
    if (Math.abs(x) >= 1) return 0;
    var v = 6.1 * Math.pow(Math.cos(x * Math.PI / 2), 2.4);
    if (minuteOfDay > 16 * 60) v *= 0.93; // forecast cloud
    return Math.round(v * 10) / 10;
  }
  var forecast = {
    place: "your location",            // RES-2: the app never names the town for the phone's location
    manualPlaceExample: "Sandefjord",   // what a manual Change place search might return
    placeSearchResults: ["Sandefjord", "Sandnes", "Sandvika", "San Sebastián"],
    fetchedHoursAgo: 2,
    peakUVI: 6.1, peakTime: "13:20", solarNoon: "13:20",
    sunrise: "04:12", sunset: "22:38",
    timeZone: "Europe/Oslo (CEST)",
    hourly: uvHourly,
    // Next days, for "next slot that can" and the no-viable-window case.
    days: [
      { day: "Today", peakUVI: 6.1, sky: "clear" },
      { day: "Sunday", peakUVI: 5.2, sky: "high cloud" },
      { day: "Monday", peakUVI: 3.4, sky: "overcast" },
      { day: "Tuesday", peakUVI: 6.4, sky: "clear" }
    ]
  };

  var profile = {
    skinType: "III",
    reports: 2,
    reportsNeeded: 3,                   // conservative until this many reports
    setting: "Conservative",            // SET-4; Aggressive locked (aggressiveLocked, count 3)
    sensitivity: { percent: 8, direction: "more", count: 2 }, // sensitivitySentence
    manualValue: "1.00",
    notifications: true, location: true
  };

  // The slot the user enters by default, and what the engine answers for each toggle combination.
  var slot = { from: "12:30", until: "14:00", fromMin: 750, untilMin: 840, window: "12:30–14:00" };

  var results = {
    // Lying down, turning over; not covered; best minutes (the default answer).
    lyingBest: {
      outcome: "planBareSubWindow", minutes: 34, start: "13:04", end: "13:38",
      sides: [ { side: "Face up", minutes: 16, from: "13:04", to: "13:20" },
               { side: "Face down", minutes: 18, from: "13:20", to: "13:38" } ],
      range: { lower: 29, upper: 40, clipped: false },
      extraIfCovered: 6,
      regions: [
        { key: "front", label: "front", plan: 1.5, left: 2.4, cycle: 9.8 },
        { key: "back", label: "back", plan: 1.6, left: 2.4, cycle: 8.6 },
        { key: "headAndShoulders", label: "head and shoulders", plan: 2.2, left: 2.4, cycle: 11.4 }
      ],
      notices: ["boundByMelanogenic", "conservativeUntilCalibrated", "coverToRunLonger", "cloudCaveat"],
      sunscreen: "sunscreenNotNeeded",
      estimate: ["assumptionMelanogenicFraction", "assumptionShoulderFraction"]
    },
    // Same, head and shoulders covered: each side runs 6 minutes longer.
    lyingCovered: {
      outcome: "planBareSubWindow", minutes: 46, start: "12:58", end: "13:44",
      sides: [ { side: "Face up", minutes: 22, from: "12:58", to: "13:20" },
               { side: "Face down", minutes: 24, from: "13:20", to: "13:44" } ],
      range: { lower: 40, upper: 53, clipped: false },
      regions: [
        { key: "front", label: "front", plan: 2.1, left: 2.4, cycle: 9.8 },
        { key: "back", label: "back", plan: 2.2, left: 2.4, cycle: 8.6 },
        { key: "headAndShoulders", label: "head and shoulders", plan: 0.0, left: 2.4, cycle: 11.4 }
      ]
    },
    // Up and about; front and back each get part of the sun, no flip timer.
    upBest: {
      outcome: "planBareSubWindow", minutes: 41, start: "12:59", end: "13:40",
      range: { lower: 35, upper: 48, clipped: false },
      extraIfCovered: 9,
      regions: [
        { key: "front", label: "front", plan: 1.1, left: 2.4, cycle: 9.8 },
        { key: "back", label: "back", plan: 1.1, left: 2.4, cycle: 8.6 },
        { key: "headAndShoulders", label: "head and shoulders", plan: 2.3, left: 2.4, cycle: 11.4 }
      ]
    },
    // Staying the whole slot (CALC-9 on): sunscreen headline, bare-skin alternative below.
    stayWhole: {
      outcome: "planStayWearThis", spf: "SPF 15", application: "normally", window: "12:30–14:00",
      reapply: "13:15", uvaMultiple: 2.6,
      notices: ["uvaMultiple", "sunscreenApplicationBeatsLabel"],
      alternative: "lyingBest",
      // If the user picks SPF 10 normally in "I don't have that SPF":
      withSpf10: { line: "alternativeShadeForRest", spf: "SPF 10", application: "normally", coveredMinutes: 58 },
      // If SPF 10 thickly:
      withSpf10Thick: { line: "alternativeWholeWindow", spf: "SPF 10", application: "thickly" },
      // Staying with no sunscreen at all would take the head and shoulders past target:
      warnBare: { line: "warnPastTarget", region: "head and shoulders", sed: 3.4 }
    },
    // Edge cases a prototype can show (e.g. by entering other times):
    evening: { // slot 18:30-19:30
      outcome: "tooWeak", shortfall: 1.1, nextDay: "tomorrow", nextHour: "13:00", notices: ["uvaHeavy"]
    },
    passed: { outcome: "windowPassed" },       // until earlier than now (11:42)
    noForecast: { outcome: "missingForecast", reason: "the weather service did not answer" },
    budgetSpent: { outcome: "budgetSpent", region: "head and shoulders" }
  };

  var spfOptions = ["SPF 6", "SPF 10", "SPF 15", "SPF 20", "SPF 25", "SPF 30", "SPF 50", "SPF 50+"];

  // History: newest first. skin = SKIN-3..7 answer or null (no report yet).
  var history = [
    { day: "Friday 12 June", time: "13:02–13:31", posture: "Lying down, turning over", sunscreen: null,
      sed: { front: 1.4, back: 1.5, headAndShoulders: 2.1 }, skin: null, due: true, intent: "Best minutes", covered: false, setting: "Conservative", peakUVI: 5.9 },
    { day: "Thursday 11 June", time: "12:50–13:22", posture: "Lying down, turning over", sunscreen: null,
      sed: { front: 1.4, back: 1.5, headAndShoulders: 1.9 }, skin: "Normal, no redness", intent: "Best minutes", covered: false, setting: "Conservative", peakUVI: 6.0 },
    { day: "Tuesday 9 June", time: "13:10–13:41", posture: "Up and about", sunscreen: null,
      sed: { front: 1.1, back: 1.1, headAndShoulders: 2.0 }, skin: "Faint pink", intent: "Best minutes", covered: false, setting: "Conservative", peakUVI: 5.6 },
    { day: "Sunday 7 June", time: "11:30–14:30", posture: "Lying down, turning over", sunscreen: { spf: "15", application: "normally" },
      sed: { front: 1.6, back: 1.7, headAndShoulders: 2.2 }, skin: null, intent: "Whole slot", covered: true, setting: "Conservative", peakUVI: 6.2 },
    { day: "Saturday 6 June", time: "12:40–13:05", posture: "Lying down, turning over", sunscreen: null,
      sed: { front: 1.2, back: 1.2, headAndShoulders: 1.6 }, skin: null, intent: "Best minutes", covered: false, setting: "Conservative", peakUVI: 5.8 }
  ];
  var unreportedCount = 3;
  // Session detail extras (HIST-13), for the newest session.
  var detailFigures = [
    { region: "front", tanProtection: "×1.3", target: 1.5, received: 1.4 },
    { region: "back", tanProtection: "×1.2", target: 1.6, received: 1.5 },
    { region: "head and shoulders", tanProtection: "×1.4", target: 2.2, received: 2.1 }
  ];
  // Trajectory (trajectoryTitle): dose per tan cycle, SED, all regions summed per cycle.
  var cycles = [
    { label: "Cycle 1", from: "18 May", to: "29 May", sed: { front: 12.4, back: 11.0, headAndShoulders: 15.1 } },
    { label: "Cycle 2", from: "6 June", to: "now", sed: { front: 9.8, back: 8.6, headAndShoulders: 11.4 } }
  ];
  // Daily front dose for the last 14 days (oldest first), for sparklines.
  var daily = [
    { d: "31 May", front: 0 }, { d: "1 Jun", front: 0 }, { d: "2 Jun", front: 0 }, { d: "3 Jun", front: 0 },
    { d: "4 Jun", front: 0 }, { d: "5 Jun", front: 0 }, { d: "6 Jun", front: 1.2 }, { d: "7 Jun", front: 1.6 },
    { d: "8 Jun", front: 0 }, { d: "9 Jun", front: 1.1 }, { d: "10 Jun", front: 0 }, { d: "11 Jun", front: 1.4 },
    { d: "12 Jun", front: 1.4 }, { d: "13 Jun", front: 0 }
  ];
  var week = { front: 4.2, back: 4.3, headAndShoulders: 5.9 };
  var cycle = { front: 9.8, back: 8.6, headAndShoulders: 11.4 };

  // Due questions on the Plan screen (DUE-1, DUE-2).
  var due = [
    { kind: "skinCheck", key: "dueSkinCheck", day: "Friday", session: "13:02–13:31" },
    { kind: "lastingColour", key: "dueLastingColour", day: "Tuesday 9 June" }
  ];

  window.ICARUS = {
    t: t, fill: fill, esc: esc, modules: modules, linkify: linkify, moduleTitle: moduleTitle,
    md: md, haptic: haptic, store: store,
    now: now, forecast: forecast, uvAt: uvAt, profile: profile, slot: slot, results: results,
    spfOptions: spfOptions, history: history, unreportedCount: unreportedCount, detailFigures: detailFigures,
    cycles: cycles, daily: daily, week: week, cycle: cycle, due: due,
    learn: window.ICARUS_LEARN || [], skinTypes: window.ICARUS_SKIN_TYPES || [], quiz: window.ICARUS_QUIZ || []
  };
})();
