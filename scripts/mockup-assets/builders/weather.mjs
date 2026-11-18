import { Svg, f, rad, rng, pts } from '../lib.mjs';

const S = 1280;
const full = (extra = '') => `<rect width="${S}" height="${S}" ${extra}/>`;

export const weather = {
  'rain'() {
    const svg = new Svg(S, S);
    const r = rng(61);
    const b = svg.blur(0.7);
    let g = '';
    for (let i = 0; i < 760; i++) {
      const x = r.range(-100, S + 100), y = r.range(-150, S), len = r.range(40, 170);
      const w = r.range(0.8, 2.4), op = r.range(0.12, 0.58);
      g += `<line x1="${f(x)}" y1="${f(y)}" x2="${f(x - len * 0.21)}" y2="${f(y + len)}" stroke="#eaf3ff" stroke-opacity="${f(op)}" stroke-width="${f(w)}" stroke-linecap="round"/>`;
    }
    svg.add(`<g filter="url(#${b})">${g}</g>`);
    const mist = svg.linear([[0, '#cfdcea', 0.05], [1, '#cfdcea', 0.3]]);
    svg.add(full(`fill="url(#${mist})"`));
    return svg.toString();
  },

  'snow'() {
    const svg = new Svg(S, S);
    const r = rng(67);
    for (const [count, rMin, rMax, blurStd, op] of [[260, 1.2, 3.2, 0.3, 0.85], [90, 3, 7, 1.4, 0.7], [26, 8, 15, 4.5, 0.55]]) {
      const b = svg.blur(blurStd);
      let g = '';
      for (let i = 0; i < count; i++) {
        g += `<circle cx="${f(r.range(0, S))}" cy="${f(r.range(0, S))}" r="${f(r.range(rMin, rMax))}" fill="#fff" fill-opacity="${f(r.range(op * 0.5, op))}"/>`;
      }
      svg.add(`<g filter="url(#${b})">${g}</g>`);
    }
    return svg.toString();
  },

  'fog'() {
    const svg = new Svg(S, S);
    const clouds = svg.noise([0.0035, 0.007].join(' '), 5, 14, 'alpha');
    const mask = svg.linear([[0, '#fff', 0.25], [0.6, '#fff', 0.7], [1, '#fff', 1]]);
    const m = svg.id('m');
    svg.def(`<mask id="${m}"><rect width="${S}" height="${S}" fill="url(#${mask})"/></mask>`);
    svg.add(`<g mask="url(#${m})">${full(`filter="url(#${clouds})" opacity=".92"`)}</g>`);
    svg.add(full(`fill="#e9eef3" fill-opacity=".14"`));
    return svg.toString();
  },

  'mist'() {
    const svg = new Svg(S, S);
    const r = rng(71);
    const b = svg.blur(34);
    let g = '';
    for (let i = 0; i < 9; i++) {
      const y = 520 + i * 70 + r.range(-20, 20);
      g += `<ellipse cx="${f(r.range(300, 980))}" cy="${f(y)}" rx="${f(r.range(420, 760))}" ry="${f(r.range(26, 58))}" fill="#f2f6fa" fill-opacity="${f(r.range(0.18, 0.4))}"/>`;
    }
    svg.add(`<g filter="url(#${b})">${g}</g>`);
    const base = svg.linear([[0, '#f2f6fa', 0], [1, '#f2f6fa', 0.45]], 0, 0.4, 0, 1);
    svg.add(full(`fill="url(#${base})"`));
    return svg.toString();
  },

  'sun-flare'() {
    const svg = new Svg(S, S);
    const core = svg.radial([[0, '#ffffff', 1], [0.1, '#fff6d6', 0.9], [0.35, '#ffd27a', 0.34], [1, '#ff9f3d', 0]], 0.88, 0.1, 0.62);
    svg.add(full(`fill="url(#${core})"`));
    const b = svg.blur(4);
    let rays = '';
    for (let i = 0; i < 14; i++) {
      const a = 112 + i * 4.6;
      rays += `<polygon points="0,-3 1500,-${6 + i} 1500,${6 + i} 0,3" transform="translate(1126 128) rotate(${f(a)})" fill="#fff1c9" fill-opacity="${f(0.16 + (i % 3) * 0.08)}"/>`;
    }
    svg.add(`<g filter="url(#${b})">${rays}</g>`);
    const gh = [[840, 380, 60, '#ffd27a'], [650, 560, 100, '#ffb067'], [470, 760, 44, '#9ad0ff'], [300, 900, 78, '#ffe3a0']];
    const bb = svg.blur(3);
    for (const [x, y, rr, c] of gh) svg.add(`<circle cx="${x}" cy="${y}" r="${rr}" fill="${c}" fill-opacity=".22" filter="url(#${bb})"/>`);
    return svg.toString();
  },

  'water-reflection'() {
    const svg = new Svg(S, S);
    const ripples = svg.noise([0.0016, 0.09].join(' '), 3, 21, 'alpha');
    const tone = svg.linear([[0, '#2c6c8f', 0], [0.5, '#2c6c8f', 0.35], [1, '#0e3550', 0.7]]);
    const fade = svg.linear([[0, '#fff', 0], [0.45, '#fff', 0.55], [1, '#fff', 1]]);
    const m = svg.id('m');
    svg.def(`<mask id="${m}"><rect width="${S}" height="${S}" fill="url(#${fade})"/></mask>`);
    svg.add(`<g mask="url(#${m})">${full(`fill="url(#${tone})"`)}${full(`filter="url(#${ripples})" opacity=".55"`)}</g>`);
    let streaks = '';
    const r = rng(81);
    for (let i = 0; i < 90; i++) {
      const y = r.range(640, S), x = r.range(0, S), w = r.range(40, 260);
      streaks += `<rect x="${f(x)}" y="${f(y)}" width="${f(w)}" height="${f(r.range(1.5, 4))}" rx="2" fill="#fff" fill-opacity="${f(r.range(0.12, 0.45))}"/>`;
    }
    const b = svg.blur(1.1);
    svg.add(`<g filter="url(#${b})">${streaks}</g>`);
    return svg.toString();
  },
};

export const retro = {
  'vhs'() {
    const svg = new Svg(S, S);
    // Mid-grey base keeps it neutral under Overlay; lines/bands add the tape look.
    svg.add(full(`fill="#808080"`));
    let lines = '';
    for (let y = 0; y < S; y += 4) lines += `<rect x="0" y="${y}" width="${S}" height="2" fill="#000" fill-opacity=".34"/>`;
    svg.add(lines);
    const r = rng(91);
    const b = svg.blur(1.6);
    let bands = '';
    for (const [y, h, c, op] of [[220, 18, '#ffffff', 0.5], [236, 8, '#ff2d6f', 0.55], [248, 10, '#22e0ff', 0.45], [640, 30, '#ffffff', 0.35], [900, 14, '#ff2d6f', 0.4], [1090, 40, '#ffffff', 0.45]]) {
      bands += `<rect x="${f(r.range(-40, 40))}" y="${y}" width="${S}" height="${h}" fill="${c}" fill-opacity="${op}"/>`;
    }
    svg.add(`<g filter="url(#${b})">${bands}</g>`);
    const grain = svg.noise(0.5, 2, 3, 'gray');
    svg.add(full(`filter="url(#${grain})" opacity=".4"`));
    const edges = svg.linear([[0, '#ff1f5a', 0.35], [0.06, '#ff1f5a', 0], [0.94, '#19e0ff', 0], [1, '#19e0ff', 0.35]], 0, 0, 1, 0);
    svg.add(full(`fill="url(#${edges})"`));
    const noiseBand = svg.noise([0.02, 0.9].join(' '), 2, 4, 'gray');
    svg.add(`<rect y="1150" width="${S}" height="46" filter="url(#${noiseBand})" opacity=".55" transform="translate(0 0)"/>`);
    return svg.toString();
  },

  'halftone'() {
    const svg = new Svg(S, S);
    let dots = '';
    const pitch = 24;
    for (let row = -24; row < S / (pitch * 0.866) + 24; row++) {
      for (let col = -24; col < S / pitch + 24; col++) {
        const x = col * pitch + (row % 2 ? pitch / 2 : 0);
        const y = row * pitch * 0.866;
        const t = Math.min(1, Math.max(0, (x + y + 400) / (S * 1.9)));
        const rr = 1.4 + t * 9.6;
        dots += `<circle cx="${f(x)}" cy="${f(y)}" r="${f(rr)}"/>`;
      }
    }
    svg.add(`<g fill="#0c0c10" fill-opacity=".82" transform="rotate(20 640 640)">${dots}</g>`);
    return svg.toString();
  },

  'duotone'() {
    const svg = new Svg(S, S);
    const grad = svg.linear([[0, '#2a0f6b'], [0.5, '#a1306f'], [1, '#ff9a3d']], 0, 1, 1, 0);
    svg.add(full(`fill="url(#${grad})"`));
    return svg.toString();
  },

  'film-burn'() {
    const svg = new Svg(S, S);
    const warp = svg.id('w');
    svg.def(`<filter id="${warp}" x="-20%" y="-20%" width="140%" height="140%"><feTurbulence type="fractalNoise" baseFrequency="0.011" numOctaves="3" seed="6" result="n"/>` +
      `<feDisplacementMap in="SourceGraphic" in2="n" scale="150" xChannelSelector="R" yChannelSelector="G"/><feGaussianBlur stdDeviation="16"/></filter>`);
    const layers = [
      ['#2b0600', 0.92, [[-120, -120], [520, -60], [380, 330], [220, 660], [-120, 760]]],
      ['#c22a00', 0.95, [[-120, -120], [430, -80], [300, 250], [150, 560], [-120, 640]]],
      ['#ff7a00', 0.95, [[-120, -120], [330, -90], [210, 190], [90, 440], [-120, 520]]],
      ['#ffd34d', 0.98, [[-120, -120], [230, -90], [130, 120], [40, 320], [-120, 400]]],
      ['#fff7d2', 1, [[-120, -120], [130, -90], [60, 70], [-20, 210], [-120, 260]]],
    ];
    let g = '';
    for (const [c, op, poly] of layers) g += `<polygon points="${pts(poly)}" fill="${c}" fill-opacity="${op}"/>`;
    svg.add(`<g filter="url(#${warp})">${g}</g>`);
    svg.add(`<g filter="url(#${warp})" transform="translate(1280 1280) rotate(180) scale(1)">${g}</g>`);
    return svg.toString();
  },

  'vintage-film'() {
    const svg = new Svg(S, S);
    const warp = svg.id('w');
    svg.def(`<filter id="${warp}" x="-10%" y="-10%" width="120%" height="120%"><feTurbulence type="fractalNoise" baseFrequency="0.02 0.03" numOctaves="3" seed="2" result="n"/>` +
      `<feDisplacementMap in="SourceGraphic" in2="n" scale="46" xChannelSelector="R" yChannelSelector="G"/><feGaussianBlur stdDeviation="4"/></filter>`);
    const m = svg.id('m');
    svg.def(`<mask id="${m}"><rect width="${S}" height="${S}" fill="#fff"/><rect x="60" y="64" width="${S - 120}" height="${S - 128}" rx="26" fill="#000" filter="url(#${warp})"/></mask>`);
    svg.add(`<rect width="${S}" height="${S}" fill="#0d0907" fill-opacity=".96" mask="url(#${m})"/>`);
    const tint = svg.radial([[0.5, '#c98a3c', 0], [1, '#c98a3c', 0.42]], 0.5, 0.5, 0.72);
    svg.add(full(`fill="url(#${tint})"`));
    const r = rng(97);
    let dust = '';
    for (let i = 0; i < 140; i++) dust += `<circle cx="${f(r.range(80, 1200))}" cy="${f(r.range(80, 1200))}" r="${f(r.range(0.6, 2.4))}" fill="#fff" fill-opacity="${f(r.range(0.1, 0.5))}"/>`;
    svg.add(dust);
    return svg.toString();
  },

  'analog-noise'() {
    const svg = new Svg(S, S);
    const colour = svg.noise(0.7, 2, 5, 'color');
    svg.add(full(`filter="url(#${colour})"`));
    const mono = svg.noise(0.25, 1, 8, 'gray');
    svg.add(full(`filter="url(#${mono})" opacity=".45"`));
    const r = rng(101);
    let jitter = '';
    for (let i = 0; i < 50; i++) {
      jitter += `<rect x="${f(r.range(-20, 400))}" y="${f(r.range(0, S))}" width="${f(r.range(200, 1100))}" height="${f(r.range(1, 4))}" fill="${r() > 0.5 ? '#fff' : '#000'}" fill-opacity="${f(r.range(0.18, 0.5))}"/>`;
    }
    svg.add(jitter);
    return svg.toString();
  },
};
