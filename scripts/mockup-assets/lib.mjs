// Tiny SVG authoring kit used by every builder. All artwork is generated here
// from code (shapes, gradients, procedural noise): no third-party imagery.

export function hashSeed(text) {
  let h = 2166136261;
  for (const ch of text) { h ^= ch.charCodeAt(0); h = Math.imul(h, 16777619); }
  return h >>> 0;
}

/** Deterministic PRNG (mulberry32) so regenerated assets are byte-stable. */
export function rng(seed) {
  let a = seed >>> 0;
  const next = () => {
    a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  next.range = (lo, hi) => lo + next() * (hi - lo);
  next.int = (lo, hi) => Math.floor(lo + next() * (hi - lo + 1));
  next.pick = (list) => list[Math.floor(next() * list.length)];
  return next;
}

export const f = (n) => Math.round(n * 100) / 100;
export const rad = (deg) => (deg * Math.PI) / 180;

export class Svg {
  constructor(w, h) {
    this.w = w; this.h = h;
    this.defs = []; this.body = []; this.count = 0;
  }
  id(prefix = 'i') { return `${prefix}${this.count++}`; }
  add(markup) { this.body.push(markup); return this; }
  def(markup) { this.defs.push(markup); return this; }

  blur(std) {
    const id = this.id('b');
    this.def(`<filter id="${id}" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="${std}"/></filter>`);
    return id;
  }
  /** stops: [[offset, color, opacity?], ...]; coordinates are bounding-box fractions. */
  linear(stops, x1 = 0, y1 = 0, x2 = 0, y2 = 1) {
    const id = this.id('l');
    this.def(`<linearGradient id="${id}" x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}">${stopsMarkup(stops)}</linearGradient>`);
    return id;
  }
  radial(stops, cx = 0.5, cy = 0.5, r = 0.5, fx = cx, fy = cy) {
    const id = this.id('r');
    this.def(`<radialGradient id="${id}" cx="${cx}" cy="${cy}" r="${r}" fx="${fx}" fy="${fy}">${stopsMarkup(stops)}</radialGradient>`);
    return id;
  }
  /** Grey/colour noise filter. mode: 'gray' | 'color' | 'alpha' (white with noisy alpha). */
  noise(freq = 0.8, octaves = 2, seed = 1, mode = 'gray', alpha = 1) {
    const id = this.id('n');
    const matrix = {
      gray: `0.333 0.333 0.333 0 0  0.333 0.333 0.333 0 0  0.333 0.333 0.333 0 0  0 0 0 0 ${alpha}`,
      color: `1 0 0 0 0  0 1 0 0 0  0 0 1 0 0  0 0 0 0 ${alpha}`,
      alpha: `0 0 0 0 1  0 0 0 0 1  0 0 0 0 1  1 0 0 0 0`,
    }[mode];
    this.def(`<filter id="${id}" x="0" y="0" width="100%" height="100%" color-interpolation-filters="sRGB">` +
      `<feTurbulence type="fractalNoise" baseFrequency="${freq}" numOctaves="${octaves}" seed="${seed}"/>` +
      `<feColorMatrix type="matrix" values="${matrix}"/></filter>`);
    return id;
  }
  /** Embossed paper-like surface from turbulence. */
  surface(freq, octaves, seed, scale = 2, elevation = 62, tint = '#ffffff', contrast = 1, lift = 0) {
    const id = this.id('s');
    const fx = Array.isArray(freq) ? `${freq[0]} ${freq[1]}` : freq;
    this.def(`<filter id="${id}" x="0" y="0" width="100%" height="100%" color-interpolation-filters="sRGB">` +
      `<feTurbulence type="fractalNoise" baseFrequency="${fx}" numOctaves="${octaves}" seed="${seed}" result="t"/>` +
      `<feDiffuseLighting in="t" lighting-color="${tint}" surfaceScale="${scale}" diffuseConstant="1" result="l">` +
      `<feDistantLight azimuth="225" elevation="${elevation}"/></feDiffuseLighting>` +
      `<feComponentTransfer in="l"><feFuncR type="linear" slope="${contrast}" intercept="${lift}"/>` +
      `<feFuncG type="linear" slope="${contrast}" intercept="${lift}"/><feFuncB type="linear" slope="${contrast}" intercept="${lift}"/></feComponentTransfer></filter>`);
    return id;
  }
  /** Cut a transparent window through EVERYTHING drawn so far/after (scene mockups). */
  cutWindow(slot, radius = 0) { this.hole = { slot, radius }; return this; }
  toString() {
    let body = this.body.join('');
    let defs = this.defs.join('');
    if (this.hole) {
      const { slot, radius } = this.hole;
      defs += `<mask id="hole" maskUnits="userSpaceOnUse" x="0" y="0" width="${this.w}" height="${this.h}">` +
        `<rect width="${this.w}" height="${this.h}" fill="#fff"/>` +
        `<rect x="${slot.x}" y="${slot.y}" width="${slot.w}" height="${slot.h}" rx="${radius}" fill="#000"/></mask>`;
      body = `<g mask="url(#hole)">${body}</g>`;
    }
    return `<svg xmlns="http://www.w3.org/2000/svg" width="${this.w}" height="${this.h}" viewBox="0 0 ${this.w} ${this.h}">` +
      `<defs>${defs}</defs>${body}</svg>`;
  }
}

function stopsMarkup(stops) {
  return stops.map(([o, c, a = 1]) => `<stop offset="${o}" stop-color="${c}" stop-opacity="${a}"/>`).join('');
}

export const pts = (list) => list.map(([x, y]) => `${f(x)},${f(y)}`).join(' ');

/** Pointed leaf pointing "up" from the origin. */
export function leafPath(len, wid, bend = 0) {
  const w = wid / 2;
  return `M0,0 C${f(w * 1.1 + bend)},${f(-len * 0.22)} ${f(w * 1.05 + bend)},${f(-len * 0.7)} ${f(bend)},${f(-len)} ` +
    `C${f(-w * 1.05 + bend)},${f(-len * 0.7)} ${f(-w * 1.1 + bend)},${f(-len * 0.22)} 0,0 Z`;
}

/** Rough torn/irregular edge as a list of points along a horizontal line. */
export function jaggedLine(r, x0, x1, y, amp, step = 7) {
  const out = [];
  let drift = 0;
  for (let x = x0; x <= x1; x += step) {
    drift += r.range(-amp * 0.35, amp * 0.35);
    drift = Math.max(-amp, Math.min(amp, drift));
    out.push([x, y + drift + r.range(-amp * 0.25, amp * 0.25)]);
  }
  return out;
}
