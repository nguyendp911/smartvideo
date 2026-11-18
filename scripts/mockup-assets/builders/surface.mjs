import { Svg, f, rad, rng, pts, jaggedLine } from '../lib.mjs';

const S = 1280;
const full = (extra = '') => `<rect width="${S}" height="${S}" ${extra}/>`;

export const texture = {
  // Neutral light-grey surfaces: designed for Multiply (white = no change).
  'paper-texture'() {
    const svg = new Svg(S, S);
    const s = svg.surface([0.05, 0.05], 4, 3, 1.4, 66, '#ffffff', 1.12, 0.02);
    svg.add(full(`filter="url(#${s})"`));
    const fibers = svg.noise([0.9, 0.04].join(' '), 2, 6, 'alpha');
    svg.add(full(`filter="url(#${fibers})" opacity=".06"`));
    return svg.toString();
  },

  'torn-paper'() {
    const svg = new Svg(S, S);
    const r = rng(7);
    const top = 560;
    const edge = jaggedLine(r, -20, S + 20, top, 18, 8);
    const poly = (list) => pts([[-20, S + 20], ...list, [S + 20, S + 20]]);
    const outer = jaggedLine(rng(7), -20, S + 20, top - 10, 22, 8);
    const clip = svg.id('c');
    svg.def(`<clipPath id="${clip}"><polygon points="${poly(edge)}"/></clipPath>`);
    const shade = svg.blur(9);
    svg.add(`<polygon points="${poly(edge.map(([x, y]) => [x, y - 6]))}" fill="#000" fill-opacity=".38" filter="url(#${shade})"/>`);
    // Fibrous white rim, then the sheet.
    svg.add(`<polygon points="${poly(outer)}" fill="#fffdf7"/>`);
    const s = svg.surface([0.045, 0.06], 4, 9, 1.6, 64, '#fbf6ea', 1.12, 0.02);
    svg.add(`<g clip-path="url(#${clip})">${full(`filter="url(#${s})"`)}</g>`);
    const wash = svg.linear([[0, '#d9cdb4', 0.35], [0.25, '#d9cdb4', 0]], 0, 0.4, 0, 1);
    svg.add(`<g clip-path="url(#${clip})">${full(`fill="url(#${wash})"`)}</g>`);
    return svg.toString();
  },

  'folded-paper'() {
    const svg = new Svg(S, S);
    const s = svg.surface([0.05, 0.05], 4, 5, 1.3, 66, '#ffffff', 1.1, 0.03);
    svg.add(full(`filter="url(#${s})"`));
    const shadeA = svg.linear([[0, '#000', 0], [0.5, '#000', 0.04], [0.52, '#000', 0.24], [0.56, '#000', 0]], 0, 0, 1, 0);
    const shadeB = svg.linear([[0, '#fff', 0.38], [0.42, '#fff', 0], [0.46, '#000', 0.14], [0.5, '#000', 0], [1, '#000', 0.08]], 0, 0, 1, 0);
    // Letter fold: two horizontal creases + one vertical.
    for (const y of [427, 853]) {
      svg.add(`<rect x="0" y="${y - 40}" width="${S}" height="80" fill="url(#${svg.linear([[0, '#000', 0], [0.5, '#000', 0.2], [0.52, '#fff', 0.45], [1, '#fff', 0]], 0, 0, 0, 1)})"/>`);
    }
    svg.add(`<rect x="${S / 2 - 50}" y="0" width="100" height="${S}" fill="url(#${shadeB})"/>`);
    svg.add(`<rect x="${S / 2 - 3}" y="0" width="6" height="${S}" fill="#000" fill-opacity=".1"/>`);
    return svg.toString();
  },

  'crumpled-paper'() {
    const svg = new Svg(S, S);
    const s = svg.surface([0.007, 0.007], 6, 12, 14, 42, '#ffffff', 1.0, 0.0);
    svg.add(full(`filter="url(#${s})"`));
    const fine = svg.surface([0.03, 0.03], 3, 4, 3, 55, '#ffffff', 1.0, 0.0);
    svg.add(full(`filter="url(#${fine})" opacity=".4" style="mix-blend-mode:multiply"`));
    return svg.toString();
  },

  'concrete-texture'() {
    const svg = new Svg(S, S);
    const base = svg.surface([0.012, 0.012], 5, 22, 3, 60, '#e4e4e2', 1.0, 0.0);
    svg.add(full(`filter="url(#${base})"`));
    const grit = svg.noise(0.9, 2, 31, 'gray');
    svg.add(full(`filter="url(#${grit})" opacity=".18"`));
    const r = rng(41);
    let pits = '';
    for (let i = 0; i < 160; i++) pits += `<ellipse cx="${f(r.range(0, S))}" cy="${f(r.range(0, S))}" rx="${f(r.range(1, 5))}" ry="${f(r.range(0.8, 3.5))}" fill="#3a3a3c" fill-opacity="${f(r.range(0.25, 0.7))}"/>`;
    const b = svg.blur(0.6);
    svg.add(`<g filter="url(#${b})">${pits}</g>`);
    return svg.toString();
  },

  'plaster-wall'() {
    const svg = new Svg(S, S);
    const s = svg.surface([0.0055, 0.0055], 3, 33, 2.4, 58, '#f6f0e6', 1.0, 0.02);
    svg.add(full(`filter="url(#${s})"`));
    const r = rng(57);
    let arcs = '';
    for (let i = 0; i < 26; i++) {
      const cx = r.range(0, S), cy = r.range(0, S), rr = r.range(160, 460);
      arcs += `<path d="M${f(cx - rr)},${f(cy)} A${f(rr)},${f(rr * r.range(0.4, 0.8))} 0 0 1 ${f(cx + rr)},${f(cy)}" fill="none" stroke="#fff" stroke-opacity="${f(r.range(0.1, 0.3))}" stroke-width="${f(r.range(10, 36))}" stroke-linecap="round"/>`;
    }
    const b = svg.blur(14);
    svg.add(`<g filter="url(#${b})" opacity=".55">${arcs}</g>`);
    return svg.toString();
  },

  'linen-texture'() {
    const svg = new Svg(S, S);
    const weave = svg.id('p');
    svg.def(`<pattern id="${weave}" width="8" height="8" patternUnits="userSpaceOnUse">` +
      `<rect width="8" height="8" fill="#f2eee6"/><rect width="8" height="4" fill="#e3dccd"/><rect x="0" width="4" height="8" fill="#000" fill-opacity=".06"/>` +
      `<rect x="4" y="4" width="4" height="4" fill="#fff" fill-opacity=".35"/></pattern>`);
    svg.add(full(`fill="url(#${weave})"`));
    const slubs = svg.noise([0.02, 0.5].join(' '), 3, 17, 'gray');
    svg.add(full(`filter="url(#${slubs})" opacity=".22"`));
    const slubsV = svg.noise([0.5, 0.02].join(' '), 3, 18, 'gray');
    svg.add(full(`filter="url(#${slubsV})" opacity=".18"`));
    return svg.toString();
  },

  'canvas-texture'() {
    const svg = new Svg(S, S);
    const weave = svg.id('p');
    svg.def(`<pattern id="${weave}" width="5" height="5" patternUnits="userSpaceOnUse">` +
      `<rect width="5" height="5" fill="#f4f1ea"/><path d="M0,2.5 H5" stroke="#bdb6a6" stroke-width="1.1"/><path d="M2.5,0 V5" stroke="#cfc8b8" stroke-width="1.1"/>` +
      `<circle cx="2.5" cy="2.5" r="1.2" fill="#fff" fill-opacity=".7"/></pattern>`);
    svg.add(full(`fill="url(#${weave})"`));
    const mottle = svg.surface([0.01, 0.01], 3, 8, 1.2, 60, '#ffffff', 1.0, 0.0);
    svg.add(full(`filter="url(#${mottle})" opacity=".25"`));
    return svg.toString();
  },

  'vintage-texture'() {
    const svg = new Svg(S, S);
    svg.add(full(`fill="#eadcbd"`));
    const stains = svg.noise([0.0045, 0.0045].join(' '), 4, 19, 'alpha');
    svg.add(`<g style="isolation:isolate">${full(`filter="url(#${stains})" fill="#8a5a24" opacity=".42"`)}</g>`);
    const fibers = svg.surface([0.7, 0.05], 2, 5, 1.2, 60, '#ffffff', 1.0, 0.0);
    svg.add(full(`filter="url(#${fibers})" opacity=".18"`));
    const burn = svg.radial([[0.5, '#5a3414', 0], [0.82, '#5a3414', 0.35], [1, '#2e1a08', 0.78]], 0.5, 0.5, 0.74);
    svg.add(full(`fill="url(#${burn})"`));
    const speck = svg.noise(0.35, 2, 3, 'gray');
    svg.add(full(`filter="url(#${speck})" opacity=".12"`));
    return svg.toString();
  },
};

export const background = {
  'minimal-background'() {
    const svg = new Svg(S, S);
    const g = svg.linear([[0, '#f3f2ee'], [1, '#e4e2dc']]);
    svg.add(full(`fill="url(#${g})"`));
    const n = svg.noise(0.9, 2, 3, 'gray');
    svg.add(full(`filter="url(#${n})" opacity=".05"`));
    return svg.toString();
  },

  'studio-background'() {
    const svg = new Svg(S, S);
    const wall = svg.linear([[0, '#dcdee2'], [0.62, '#c4c8ce'], [0.64, '#b9bdc4'], [1, '#d4d7dc']]);
    svg.add(full(`fill="url(#${wall})"`));
    const spot = svg.radial([[0, '#fff', 0.7], [0.55, '#fff', 0.18], [1, '#fff', 0]], 0.5, 0.52, 0.62);
    svg.add(full(`fill="url(#${spot})"`));
    const floor = svg.linear([[0, '#000', 0.14], [0.45, '#000', 0]], 0, 1, 0, 0.6);
    svg.add(full(`fill="url(#${floor})"`));
    const vig = svg.radial([[0.55, '#000', 0], [1, '#000', 0.32]], 0.5, 0.5, 0.75);
    svg.add(full(`fill="url(#${vig})"`));
    return svg.toString();
  },

  'gradient-background'() {
    const svg = new Svg(S, S);
    svg.add(full(`fill="#fdf4ee"`));
    for (const [cx, cy, c, r] of [[0.15, 0.15, '#ffc9b0', 0.8], [0.9, 0.25, '#cfc0ff', 0.7], [0.3, 0.95, '#b6e1ff', 0.85], [0.85, 0.9, '#ffe3a6', 0.6]]) {
      const id = svg.radial([[0, c, 1], [1, c, 0]], cx, cy, r);
      svg.add(full(`fill="url(#${id})"`));
    }
    const n = svg.noise(0.9, 2, 5, 'gray');
    svg.add(full(`filter="url(#${n})" opacity=".04"`));
    return svg.toString();
  },

  'abstract-background'() {
    const svg = new Svg(S, S);
    svg.add(full(`fill="#f1e6d8"`));
    const b = svg.blur(46);
    svg.add(`<g filter="url(#${b})"><ellipse cx="260" cy="300" rx="420" ry="360" fill="#d98c6b"/><ellipse cx="1040" cy="260" rx="360" ry="300" fill="#a9b99a"/>` +
      `<ellipse cx="900" cy="1030" rx="520" ry="360" fill="#e8c9a0"/><ellipse cx="180" cy="1080" rx="300" ry="260" fill="#c47c5d"/></g>`);
    for (const [cx, cy, rr, w] of [[320, 360, 420, 3], [980, 900, 360, 2], [650, 650, 220, 2]]) {
      svg.add(`<circle cx="${cx}" cy="${cy}" r="${rr}" fill="none" stroke="#fff" stroke-opacity=".5" stroke-width="${w}"/>`);
    }
    const n = svg.noise(0.85, 2, 9, 'gray');
    svg.add(full(`filter="url(#${n})" opacity=".05"`));
    return svg.toString();
  },

  'beige-background'() {
    const svg = new Svg(S, S);
    const g = svg.linear([[0, '#dac8ad'], [1, '#c8b394']]);
    svg.add(full(`fill="url(#${g})"`));
    const n = svg.noise(0.8, 3, 11, 'gray');
    svg.add(full(`filter="url(#${n})" opacity=".07"`));
    const vig = svg.radial([[0.5, '#5b4630', 0], [1, '#5b4630', 0.28]], 0.5, 0.45, 0.78);
    svg.add(full(`fill="url(#${vig})"`));
    return svg.toString();
  },

  'paper-background'() {
    const svg = new Svg(S, S);
    svg.add(full(`fill="#f6f1e6"`));
    const s = svg.surface([0.05, 0.05], 4, 14, 1.5, 64, '#fbf7ee', 1.12, 0.02);
    svg.add(full(`filter="url(#${s})"`));
    const edge = svg.radial([[0.6, '#a98c5a', 0], [1, '#a98c5a', 0.22]], 0.5, 0.5, 0.78);
    svg.add(full(`fill="url(#${edge})"`));
    return svg.toString();
  },
};
