#!/usr/bin/env node
// Builds assets/demo.svg, the animated terminal demo at the top of the README.
//
//   node assets/demo/build.mjs            writes assets/demo.svg
//   node assets/demo/build.mjs --at 9.5   prints a frame frozen at 9.5 s
//
// Pure CSS keyframes, no script: GitHub strips JavaScript from SVG images.
// Every line uses textLength, so columns stay aligned whatever monospace
// font the viewer has. Output text comes from ./scenario.sh, which runs wt.

import { writeFileSync } from "node:fs";

const FONT = 14.5;
const CW = 8.7; // forced advance per character
const LH = 25;
const W = 860;
const PAD = 20; // margin around the window, room for the shadow
const BAR = 40; // title bar height
const X0 = 46; // first text column
const Y0 = BAR + 34; // baseline of the first row
const ROWS = 12;
const H = BAR + 34 + (ROWS - 1) * LH + 26;

const C = {
  bg: "#0f1117", bar: "#161922", border: "#262b36",
  text: "#d5dae4", dim: "#7b8496", path: "#7aa2f7", sigil: "#4f5872",
  cmd: "#7dcfff", wt: "#c4a0ff", red: "#ff7a90", green: "#9ece6a",
  yellow: "#e8b86b", cursor: "#c4a0ff",
};

const HOME = "~/code/app";
const WTREE = "~/code/app.worktrees/feature/login";

// --- timeline ---------------------------------------------------------------

const screens = [];
let t = 0;
let scr;

function screen(caption, build) {
  scr = { caption, start: t, rows: [] };
  t += 0.35;
  build();
  t += 2.3; // hold the final state
  scr.end = t;
  screens.push(scr);
}

function row(segs, extra = {}) {
  const r = { segs, at: t, ...extra };
  scr.rows.push(r);
  return r;
}

const prompt = (dir) => [[dir, "path"], [" $ ", "sigil"]];

function cmd(dir, text, extra = {}) {
  const [head, ...rest] = text.split(" ");
  const segs = [...prompt(dir), [head, head === "wt" ? "wt" : "cmd"]];
  if (rest.length) segs.push([" " + rest.join(" "), "text"]);
  const r = row(segs, extra);
  r.col = dir.length + 3;
  r.typeStart = t + 0.45;
  r.typeEnd = r.typeStart + text.length * 0.048;
  r.n = text.length;
  r.enter = r.typeEnd + 0.22;
  t = r.enter + 0.2;
  return r;
}

function out(segs, extra = {}, gap = 0.07) {
  const r = row(typeof segs === "string" ? [[segs, "text"]] : segs, extra);
  t += gap;
  return r;
}

function idle(dir) {
  const r = row(prompt(dir));
  r.col = dir.length + 3;
  r.idle = true;
}

screen("The problem: a branch can be checked out in only one place", () => {
  cmd(HOME, "git checkout feature/login");
  out([["fatal:", "red b"], [` 'feature/login' is already checked out at '${WTREE}'`, "red"]],
    { badge: "err", hl: ["red", 0, 85] });
  t += 0.6;
  idle(HOME);
});

screen("wt go: land in the worktree that holds the branch", () => {
  cmd(HOME, "wt go feature/login");
  t += 0.1;
  cmd(WTREE, "wt ls", { badge: "ok", hl: ["green", 0, WTREE.length] });
  out([["   main                           ", "dim"], [HOME, "dim"]]);
  out([["*", "green b"], ["  feature/login                  ", "text"], [WTREE, "text"]],
    { hl: ["violet", 0, 69] });
  idle(WTREE);
});

screen("wt finish: refuse excluded paths, then rebase onto origin/develop", () => {
  cmd(WTREE, "git add -A");
  cmd(WTREE, "wt finish");
  out([["wt: refusing to finish: excluded paths are staged:", "red"]], { badge: "err" });
  out([["  docs/notes.md", "red b"]], { hl: ["red", 2, 15] });
  out([["unstage them with: git restore --staged <path>", "dim"]]);
  t += 0.9;
  cmd(WTREE, "git restore --staged docs");
  cmd(WTREE, 'git commit -qm "Add login"');
  cmd(WTREE, "wt finish");
  out([["wt: fetching origin", "dim"]], {}, 0.55);
  out([["wt: rebasing feature/login onto origin/develop", "dim"]], {}, 0.6);
  out([["wt: ", "green"], ["feature/login is up to date with origin/develop", "green b"]],
    { badge: "ok", hl: ["green", 0, 51] });
  idle(WTREE);
});

const T = +t.toFixed(2);

// --- rendering --------------------------------------------------------------

const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const pct = (s) => `${Math.min(100, Math.max(0, (s / T) * 100)).toFixed(3)}%`;
const len = (segs) => segs.reduce((n, [s]) => n + s.length, 0);

let css = "";
let k = 0;

// Declares keyframes from [time, declarations, timing?] stops; returns a class.
function anim(stops, extra = "") {
  const name = `k${k++}`;
  const all = [[0, stops[0][1]], ...stops, [T, stops[stops.length - 1][1]]];
  css += `@keyframes ${name}{${all
    .map(([s, d, fn]) => `${pct(s)}{${d}${fn ? `;animation-timing-function:${fn}` : ""}}`)
    .join("")}}\n.${name}{animation:${name} ${T}s linear infinite${extra}}\n`;
  return name;
}

const show = (at, fade = 0.12) => anim([[at, "opacity:0"], [at + fade, "opacity:1"]]);
const span = (a, b, fade = 0.3) =>
  anim([[a, "opacity:0"], [a + fade, "opacity:1"], [b - fade, "opacity:1"], [b, "opacity:0"]]);

function text(segs, x, y) {
  const body = segs.map(([s, cls]) => `<tspan class="${cls}">${esc(s)}</tspan>`).join("");
  return `<text xml:space="preserve" x="${x}" y="${y}" textLength="${(len(segs) * CW).toFixed(1)}" lengthAdjust="spacing">${body}</text>`;
}

const HL = { red: "rgba(255,122,144,.13)", green: "rgba(158,206,106,.14)", violet: "rgba(196,160,255,.12)" };

function badge(kind, y, at) {
  const pop = anim([
    [at, "transform:scale(0)", "cubic-bezier(.3,1.6,.6,1)"],
    [at + 0.28, "transform:scale(1)"],
  ]);
  const color = kind === "ok" ? C.green : C.red;
  const mark = kind === "ok"
    ? `<path d="M-3.4 0.2 L-1 2.6 L3.6 -2.4" />`
    : `<path d="M-2.6 -2.6 L2.6 2.6 M2.6 -2.6 L-2.6 2.6" />`;
  return `<g transform="translate(24 ${y - 4.5})"><g class="${pop}">` +
    `<circle r="8" fill="${color}" fill-opacity=".16" stroke="${color}" stroke-width="1.2"/>` +
    `<g fill="none" stroke="${color}" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${mark}</g></g></g>`;
}

function highlight([color, from, to], y, at) {
  const sweep = anim([
    [at, "transform:scaleX(0)", "cubic-bezier(.2,.8,.2,1)"],
    [at + 0.45, "transform:scaleX(1)"],
  ]);
  return `<g transform="translate(${X0 + from * CW - 5} ${y - 17})"><rect class="${sweep}" ` +
    `width="${((to - from) * CW + 10).toFixed(1)}" height="23" rx="5" fill="${HL[color]}"/></g>`;
}

function renderRow(r, i) {
  const y = Y0 + i * LH;
  let g = "";
  if (r.hl) g += highlight(r.hl, y, r.at + 0.1);
  g += text(r.segs, X0, y);
  if (r.n) g += typing(r, y);
  if (r.idle) {
    g += `<g class="${anim([[r.at, "opacity:1"]])}"><rect class="blink" x="${X0 + r.col * CW}" ` +
      `y="${y - 14}" width="${CW}" height="18" rx="1.5" fill="${C.cursor}"/></g>`;
  }
  if (r.badge) g += badge(r.badge, y, r.at + 0.08);
  return `<g class="${show(r.at)}">${g}</g>`;
}

// A cursor followed by a mask the colour of the background slides right one
// character per step, uncovering the command as if it were being typed.
function typing(r, y) {
  const slide = anim([
    [r.typeStart, "transform:translateX(0)", `steps(${r.n},end)`],
    [r.typeEnd, `transform:translateX(${(r.n * CW).toFixed(1)}px)`],
  ]);
  const caret = anim([[r.enter, "opacity:1"], [r.enter + 0.01, "opacity:0"]]);
  return `<g transform="translate(${X0 + r.col * CW} 0)"><g class="${slide}">` +
    `<rect x="${CW}" y="${y - 17}" width="${W}" height="23" fill="${C.bg}"/>` +
    `<rect class="${caret}" y="${y - 14}" width="${CW}" height="18" rx="1.5" fill="${C.cursor}"/></g></g>`;
}

function render() {
  const body = screens.map((s) =>
    `<g class="${span(s.start, s.end)}">${s.rows.map((r, i) => renderRow(r, i)).join("")}</g>`).join("\n");

  const captions = screens.map((s) =>
    `<text class="cap ${span(s.start, s.end)}" x="${W / 2}" y="${BAR / 2 + 4.5}" text-anchor="middle">${esc(s.caption)}</text>`).join("");

  const dots = screens.map((s, i) => {
    const x = W - 64 + i * 16;
    return `<circle cx="${x}" cy="${BAR / 2}" r="3.5" fill="${C.border}"/>` +
      `<circle class="${span(s.start, s.end, 0.2)}" cx="${x}" cy="${BAR / 2}" r="3.5" fill="${C.wt}"/>`;
  }).join("");

  const progress = anim([[0, "transform:scaleX(0)"], [T, "transform:scaleX(1)"]]);

  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W + 2 * PAD} ${H + 2 * PAD}" width="${W + 2 * PAD}" height="${H + 2 * PAD}" xml:space="preserve" role="img" aria-label="wt demo: git checkout fails because the branch is checked out in another worktree; wt go opens that worktree; wt ls lists worktrees; wt finish refuses a staged docs file, then rebases onto origin/develop.">
<style>
${css}text{font-family:ui-monospace,SFMono-Regular,"SF Mono",Menlo,Consolas,"Liberation Mono",monospace;font-size:${FONT}px;fill:${C.text};white-space:pre;font-variant-ligatures:none}
.cap{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif;font-size:12.5px;fill:#8d96a8;letter-spacing:.01em}
.path{fill:${C.path}}.sigil{fill:${C.sigil}}.cmd{fill:${C.cmd}}.wt{fill:${C.wt};font-weight:700}
.text{fill:${C.text}}.dim{fill:${C.dim}}.red{fill:${C.red}}.green{fill:${C.green}}.b{font-weight:700}
.blink{animation:blink 1.05s steps(1) infinite}@keyframes blink{50%{opacity:0}}
</style>
<defs>
<filter id="shadow" x="-10%" y="-10%" width="120%" height="130%"><feDropShadow dx="0" dy="6" stdDeviation="8" flood-color="#000" flood-opacity=".35"/></filter>
<clipPath id="win"><rect width="${W}" height="${H}" rx="11"/></clipPath>
</defs>
<g transform="translate(${PAD} ${PAD})">
<rect width="${W}" height="${H}" rx="11" fill="${C.bg}" filter="url(#shadow)"/>
<g clip-path="url(#win)">
<rect width="${W}" height="${H}" fill="${C.bg}"/>
<rect width="${W}" height="${BAR}" fill="${C.bar}"/>
<rect y="${BAR}" width="${W}" height="1" fill="${C.border}"/>
<circle cx="22" cy="${BAR / 2}" r="6" fill="#ff5f57"/><circle cx="42" cy="${BAR / 2}" r="6" fill="#febc2e"/><circle cx="62" cy="${BAR / 2}" r="6" fill="#28c840"/>
${captions}
${dots}
${body}
<rect class="${progress}" y="${H - 2}" width="${W}" height="2" fill="${C.wt}" fill-opacity=".55"/>
</g>
<rect x=".5" y=".5" width="${W - 1}" height="${H - 1}" rx="10.5" fill="none" stroke="${C.border}"/>
</g>
</svg>
`;
}

let svg = render();
const at = process.argv.indexOf("--at");
if (at !== -1) {
  const s = Number(process.argv[at + 1]);
  svg = svg.replace("</style>", `*{animation-play-state:paused!important;animation-delay:-${s}s!important}\n</style>`);
  process.stdout.write(svg);
} else {
  const file = new URL("../demo.svg", import.meta.url);
  writeFileSync(file, svg);
  console.error(`wrote assets/demo.svg: ${T}s loop, ${svg.length} bytes`);
}
