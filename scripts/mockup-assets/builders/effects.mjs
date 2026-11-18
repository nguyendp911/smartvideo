import { Svg, f, rad, rng, pts } from '../lib.mjs';

const S = 1280;
const full = (svg, extra = '') => `<rect width="${S}" height="${S}" ${extra}/>`;

export const photography = {
  'film-grain'() {
    const svg = new Svg(S, S);
    // Neutral mid-grey noise: invisible under Overlay/Soft Light except as grain.
    const a = svg.noise(0.85, 2, 7, 'gray');
    const b = svg.noise(0.35, 2, 9, 'gray', 1);
    svg.add(full(svg, `filter="url(#${a})"`));
    svg.add(full(svg, `filter="url(#${b})" opacity=".35"`));
    return svg.toString();
  },

  'light-leak'() {
    const svg = new Svg(S, S);
    const b = svg.blur(46);
    const blobs = [
      ['#ff6a1a', 1, -60, 340, 520, 700], ['#ff2d55', 0.9, -20, 720, 420, 520],
      ['#ffc23a', 1, 120, 90, 380, 380], ['#ff8f1f', 0.9, 1340, 1000, 520, 560],
      ['#ff3d9a', 0.75, 1290, 700, 320, 420],
    ];
    let g = '';
    for (const [c, op, cx, cy, rx, ry] of blobs) g += `<ellipse cx="${cx}" cy="${cy}" rx="${rx}" ry="${ry}" fill="${c}" fill-opacity="${op}"/>`;
    svg.add(`<g filter="url(#${b})">${g}</g>`);
    const hot = svg.radial([[0, '#fff3c4', 0.9], [1, '#fff3c4', 0]], 0, 0.3, 0.35);
    svg.add(full(svg, `fill="url(#${hot})"`));
    return svg.toString();
  },

  'lens-flare'() {
    const svg = new Svg(S, S);
    const core = svg.radial([[0, '#ffffff', 1], [0.12, '#fff4d1', 0.85], [0.4, '#ffb85a', 0.28], [1, '#ff8a3a', 0]], 0.3, 0.26, 0.55);
    svg.add(full(svg, `fill="url(#${core})"`));
    const streak = svg.radial([[0, '#cfe3ff', 0.9], [1, '#7aa7ff', 0]]);
    svg.add(`<ellipse cx="384" cy="332" rx="900" ry="9" fill="url(#${streak})"/>`);
    const ghosts = [[0.42, 70, '#6ec3ff', 0.28], [0.55, 120, '#ffd27a', 0.22], [0.68, 46, '#ff7ab6', 0.3], [0.78, 160, '#7affd6', 0.16], [0.9, 84, '#ffe9a8', 0.26]];
    const b = svg.blur(2.4);
    for (const [t, rr, c, op] of ghosts) {
      const gx = 384 + (896 - 384) * (t * 1.2) - 220, gy = 332 + (948 - 332) * (t * 1.2) - 200;
      svg.add(`<g filter="url(#${b})"><circle cx="${f(gx)}" cy="${f(gy)}" r="${rr}" fill="${c}" fill-opacity="${op}"/>` +
        `<circle cx="${f(gx)}" cy="${f(gy)}" r="${rr}" fill="none" stroke="${c}" stroke-opacity="${f(op * 1.8)}" stroke-width="5"/></g>`);
    }
    const hexR = [[820, 700, 54], [930, 800, 36], [700, 600, 28]];
    for (const [x, y, rr] of hexR) {
      const pp = pts(Array.from({ length: 6 }, (_, i) => [x + rr * Math.cos(rad(60 * i)), y + rr * Math.sin(rad(60 * i))]));
      svg.add(`<polygon points="${pp}" fill="#ffd9a0" fill-opacity=".22" stroke="#ffe9c4" stroke-opacity=".4" stroke-width="2"/>`);
    }
    return svg.toString();
  },

  'haze'() {
    const svg = new Svg(S, S);
    const grad = svg.linear([[0, '#f4f1ec', 0.05], [0.45, '#f4f1ec', 0.22], [1, '#f1ede6', 0.7]]);
    svg.add(full(svg, `fill="url(#${grad})"`));
    const clouds = svg.noise([0.004, 0.009].join(' '), 4, 4, 'alpha');
    svg.add(full(svg, `filter="url(#${clouds})" opacity=".38"`));
    return svg.toString();
  },

  'glow'() {
    const svg = new Svg(S, S);
    const spots = [[0.28, 0.24, 0.62, 0.9], [0.78, 0.7, 0.5, 0.7], [0.55, 0.1, 0.4, 0.5]];
    for (const [cx, cy, r, op] of spots) {
      const id = svg.radial([[0, '#fffaf0', op], [0.35, '#ffe9c0', op * 0.4], [1, '#ffe9c0', 0]], cx, cy, r);
      svg.add(full(svg, `fill="url(#${id})"`));
    }
    const b = svg.blur(30);
    svg.add(`<g filter="url(#${b})"><rect x="-60" y="-60" width="1400" height="120" fill="#fff6e0" fill-opacity=".45"/></g>`);
    return svg.toString();
  },

  'vignette'() {
    const svg = new Svg(S, S);
    const id = svg.radial([[0, '#000', 0], [0.55, '#000', 0], [0.85, '#000', 0.55], [1, '#000', 0.9]], 0.5, 0.5, 0.72);
    svg.add(full(svg, `fill="url(#${id})"`));
    return svg.toString();
  },

  'dust'() {
    const svg = new Svg(S, S);
    const r = rng(17);
    let g = '';
    for (let i = 0; i < 520; i++) {
      const rr = Math.pow(r(), 3) * 3.4 + 0.5;
      g += `<circle cx="${f(r.range(0, S))}" cy="${f(r.range(0, S))}" r="${f(rr)}" fill="#fff" fill-opacity="${f(r.range(0.12, 0.8))}"/>`;
    }
    for (let i = 0; i < 46; i++) {
      const x = r.range(0, S), y = r.range(0, S), l = r.range(14, 60), a = r.range(0, 360);
      g += `<path d="M${f(x)},${f(y)} q${f(l * 0.5)},${f(r.range(-12, 12))} ${f(l)},${f(r.range(-6, 6))}" transform="rotate(${f(a)} ${f(x)} ${f(y)})" stroke="#fff" stroke-opacity="${f(r.range(0.25, 0.6))}" stroke-width="${f(r.range(0.6, 1.4))}" fill="none"/>`;
    }
    const b = svg.blur(0.5);
    svg.add(`<g filter="url(#${b})">${g}</g>`);
    return svg.toString();
  },

  'scratches'() {
    const svg = new Svg(S, S);
    const r = rng(29);
    let g = '';
    for (let i = 0; i < 38; i++) {
      const x = r.range(0, S), y = r.range(-100, S * 0.6), l = r.range(180, 1100);
      const bend = r.range(-24, 24);
      g += `<path d="M${f(x)},${f(y)} q${f(bend)},${f(l * 0.5)} ${f(bend * 0.4)},${f(l)}" stroke="#fff" stroke-opacity="${f(r.range(0.2, 0.7))}" stroke-width="${f(r.range(0.6, 1.7))}" fill="none"/>`;
    }
    for (let i = 0; i < 20; i++) {
      const x = r.range(0, S), y = r.range(0, S), l = r.range(30, 160), a = r.range(60, 120);
      g += `<line x1="${f(x)}" y1="${f(y)}" x2="${f(x + l * Math.cos(rad(a)))}" y2="${f(y + l * Math.sin(rad(a)))}" stroke="#fff" stroke-opacity="${f(r.range(0.3, 0.8))}" stroke-width="${f(r.range(0.6, 1.2))}"/>`;
    }
    const b = svg.blur(0.45);
    svg.add(`<g filter="url(#${b})">${g}</g>`);
    return svg.toString();
  },

  'bokeh'() {
    const svg = new Svg(S, S);
    const r = rng(37);
    const palette = ['#ffe3a3', '#ffd0a8', '#fff2cf', '#ffc4d6', '#d6ecff'];
    for (let i = 0; i < 44; i++) {
      const rr = r.range(28, 118);
      const id = svg.radial([[0, '#fff', 0.1], [0.72, r.pick(palette), 0.3], [0.94, r.pick(palette), 0.62], [1, '#fff', 0]]);
      const b = svg.blur(r.range(0.8, 5));
      svg.add(`<circle cx="${f(r.range(0, S))}" cy="${f(r.range(0, S))}" r="${f(rr)}" fill="url(#${id})" filter="url(#${b})" opacity="${f(r.range(0.35, 1))}"/>`);
    }
    return svg.toString();
  },

  'chromatic-aberration'() {
    const svg = new Svg(S, S);
    const edge = (id, c, x1, y1, x2, y2, op) => svg.linear([[0, c, op], [1, c, 0]], x1, y1, x2, y2);
    const left = edge('l', '#ff2a3c', 0, 0, 1, 0, 0.75);
    const right = edge('r', '#19e5ff', 1, 0, 0, 0, 0.75);
    const top = edge('t', '#3a5bff', 0, 0, 0, 1, 0.55);
    const bottom = edge('b', '#ffd83a', 0, 1, 0, 0, 0.5);
    const b = svg.blur(2.2);
    svg.add(`<g filter="url(#${b})">` +
      `<rect x="0" y="0" width="150" height="${S}" fill="url(#${left})"/>` +
      `<rect x="${S - 150}" y="0" width="150" height="${S}" fill="url(#${right})"/>` +
      `<rect x="0" y="0" width="${S}" height="120" fill="url(#${top})"/>` +
      `<rect x="0" y="${S - 120}" width="${S}" height="120" fill="url(#${bottom})"/></g>`);
    return svg.toString();
  },
};

export const glass = {
  'frosted-glass'() {
    const svg = new Svg(S, S);
    const base = svg.linear([[0, '#ffffff', 0.34], [1, '#f2f6fa', 0.46]]);
    svg.add(full(svg, `fill="url(#${base})"`));
    const grainy = svg.noise(0.55, 3, 12, 'alpha');
    svg.add(full(svg, `filter="url(#${grainy})" opacity=".32"`));
    const clear = svg.radial([[0, '#fff', 0], [1, '#fff', 0.18]], 0.5, 0.5, 0.75);
    svg.add(full(svg, `fill="url(#${clear})"`));
    return svg.toString();
  },

  'glass-reflection'() {
    const svg = new Svg(S, S);
    const band = svg.linear([[0, '#fff', 0], [0.5, '#fff', 0.55], [1, '#fff', 0]], 0, 0, 1, 0);
    const band2 = svg.linear([[0, '#fff', 0], [0.5, '#e6f2ff', 0.3], [1, '#fff', 0]], 0, 0, 1, 0);
    const b = svg.blur(3);
    svg.add(`<g filter="url(#${b})" transform="rotate(24 640 640)">` +
      `<rect x="120" y="-400" width="150" height="2100" fill="url(#${band})"/>` +
      `<rect x="330" y="-400" width="56" height="2100" fill="url(#${band})" opacity=".7"/>` +
      `<rect x="600" y="-400" width="320" height="2100" fill="url(#${band2})"/>` +
      `<rect x="1010" y="-400" width="80" height="2100" fill="url(#${band})" opacity=".5"/></g>`);
    const sheen = svg.linear([[0, '#fff', 0.35], [0.5, '#fff', 0]], 0, 0, 1, 1);
    svg.add(full(svg, `fill="url(#${sheen})"`));
    return svg.toString();
  },

  'glass-blur'() {
    const svg = new Svg(S, S);
    const b = svg.blur(70);
    const blobs = [[300, 320, 360, 280, 0.5], [900, 420, 320, 380, 0.42], [560, 900, 420, 260, 0.46], [1100, 1050, 260, 220, 0.38]];
    let g = '';
    for (const [x, y, rx, ry, op] of blobs) g += `<ellipse cx="${x}" cy="${y}" rx="${rx}" ry="${ry}" fill="#fff" fill-opacity="${op}"/>`;
    svg.add(`<g filter="url(#${b})">${g}</g>`);
    svg.add(full(svg, `fill="#f4f8fc" fill-opacity=".16"`));
    const fine = svg.noise(0.7, 2, 3, 'alpha');
    svg.add(full(svg, `filter="url(#${fine})" opacity=".1"`));
    return svg.toString();
  },

  'glass-distortion'() {
    const svg = new Svg(S, S);
    // Reeded / fluted glass: each flute acts like a tiny cylindrical lens.
    const flute = svg.linear([[0, '#0b0f16', 0.5], [0.35, '#0b0f16', 0.05], [0.55, '#ffffff', 0.22], [0.8, '#ffffff', 0.45], [1, '#0b0f16', 0.4]], 0, 0, 1, 0);
    let g = '';
    for (let x = 0; x < S; x += 28) g += `<rect x="${x}" y="0" width="28" height="${S}" fill="url(#${flute})"/>`;
    svg.add(g);
    const wobble = svg.noise([0.0016, 0.012].join(' '), 3, 8, 'alpha');
    svg.add(full(svg, `filter="url(#${wobble})" opacity=".12"`));
    return svg.toString();
  },

  'water-droplets'() {
    const svg = new Svg(S, S);
    const r = rng(43);
    const body = svg.radial([[0, '#cfe4f5', 0.04], [0.7, '#9fc3dd', 0.1], [0.92, '#0b1a28', 0.42], [1, '#0b1a28', 0.6]], 0.5, 0.52, 0.5);
    const spec = svg.radial([[0, '#fff', 0.95], [1, '#fff', 0]]);
    const drop = [];
    for (let i = 0; i < 170; i++) {
      const size = Math.pow(r(), 2.2) * 50 + 9;
      drop.push([r.range(0, S), r.range(0, S), size]);
    }
    const sh = svg.blur(2.4);
    let out = '';
    for (const [x, y, s] of drop) {
      const ry = s * r.range(1.0, 1.25);
      out += `<ellipse cx="${f(x + s * 0.12)}" cy="${f(y + s * 0.22)}" rx="${f(s)}" ry="${f(ry)}" fill="#000" fill-opacity=".2" filter="url(#${sh})"/>`;
      out += `<ellipse cx="${f(x)}" cy="${f(y)}" rx="${f(s)}" ry="${f(ry)}" fill="url(#${body})"/>`;
      out += `<ellipse cx="${f(x - s * 0.3)}" cy="${f(y - ry * 0.4)}" rx="${f(s * 0.26)}" ry="${f(s * 0.17)}" fill="url(#${spec})"/>`;
      out += `<path d="M${f(x - s * 0.55)},${f(y + ry * 0.6)} q${f(s * 0.5)},${f(s * 0.32)} ${f(s * 1.05)},${f(-s * 0.1)}" stroke="#fff" stroke-opacity=".5" stroke-width="${f(Math.max(1, s * 0.07))}" fill="none"/>`;
    }
    svg.add(out);
    return svg.toString();
  },
};
