import { Svg, f, rad, rng, leafPath, pts } from '../lib.mjs';

const S = 1280;
const INK = '#07090d';

/** Quadratic bezier point + tangent angle (degrees). */
function quad(p0, p1, p2, t) {
  const x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0];
  const y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1];
  const dx = 2 * (1 - t) * (p1[0] - p0[0]) + 2 * t * (p2[0] - p1[0]);
  const dy = 2 * (1 - t) * (p1[1] - p0[1]) + 2 * t * (p2[1] - p1[1]);
  return { x, y, angle: (Math.atan2(dy, dx) * 180) / Math.PI };
}

function shadowGroup(svg, inner, std, opacity = 0.74) {
  const b = svg.blur(std);
  svg.add(`<g filter="url(#${b})" fill="${INK}" fill-opacity="${opacity}" stroke="none">${inner}</g>`);
}

function frond(p0, p1, p2, leaflets, length, width, tilt) {
  let out = `<path d="M${p0.join(',')} Q${p1.join(',')} ${p2.join(',')}" fill="none" stroke="${INK}" stroke-width="7" stroke-linecap="round"/>`;
  for (let i = 1; i <= leaflets; i++) {
    const t = i / (leaflets + 1);
    const { x, y, angle } = quad(p0, p1, p2, t);
    const size = length * Math.sin(Math.PI * Math.min(1, t * 0.92 + 0.08)) + 14;
    for (const side of [-1, 1]) {
      const rot = angle + 90 + side * tilt;
      out += `<path d="${leafPath(size, width)}" transform="translate(${f(x)} ${f(y)}) rotate(${f(rot - 180 + (side > 0 ? 180 : 0))})"/>`;
    }
  }
  return out;
}

export const nature = {
  'palm-leaf-shadow'() {
    const svg = new Svg(S, S);
    let g = '';
    const fronds = [
      [[-60, 1100], [380, 700], [880, 640], 26, 190, 36, 62],
      [[-40, 1260], [280, 880], [640, 980], 22, 170, 32, 66],
      [[-80, 640], [360, 330], [820, 220], 24, 180, 34, 60],
      [[300, 1380], [520, 1000], [1000, 900], 20, 150, 30, 68],
    ];
    for (const [a, b, c, n, len, wid, tilt] of fronds) g += frond(a, b, c, n, len, wid, tilt);
    shadowGroup(svg, g, 2.6);
    return svg.toString();
  },

  'plant-shadow'() {
    const svg = new Svg(S, S);
    const r = rng(23);
    let g = '';
    for (let stem = 0; stem < 5; stem++) {
      const baseX = 700 + r.range(-90, 360), baseY = 1320;
      const ang = r.range(-38, 18);
      const len = r.range(520, 900);
      g += `<path d="M${f(baseX)},${baseY} q${f(r.range(-90, 90))},${f(-len * 0.5)} ${f(Math.sin(rad(ang)) * len)},${f(-len * 0.95)}" stroke="${INK}" stroke-width="6" fill="none"/>`;
      const leaves = r.int(6, 9);
      for (let i = 0; i < leaves; i++) {
        const t = (i + 1) / (leaves + 1);
        const x = baseX + Math.sin(rad(ang)) * len * t * 0.95 + r.range(-20, 20);
        const y = baseY - len * 0.95 * t;
        const a = ang + r.range(-70, 70) + (i % 2 ? 40 : -40);
        g += `<path d="${leafPath(r.range(110, 210), r.range(46, 84))}" transform="translate(${f(x)} ${f(y)}) rotate(${f(a)})"/>`;
      }
    }
    shadowGroup(svg, g, 3.4);
    return svg.toString();
  },

  'tree-branch-shadow'() {
    const svg = new Svg(S, S);
    const r = rng(31);
    let g = '';
    const branches = [
      { p: [[1320, 120], [980, 300], [620, 380], [260, 640]], w: 20 },
      { p: [[900, 280], [800, 520], [700, 760], [660, 1100]], w: 12 },
      { p: [[640, 380], [520, 330], [380, 360], [220, 300]], w: 9 },
      { p: [[1100, 200], [1160, 420], [1120, 620], [1240, 860]], w: 10 },
    ];
    for (const { p, w } of branches) {
      g += `<path d="M${p[0]} C${p[1]} ${p[2]} ${p[3]}" stroke="${INK}" stroke-width="${w}" fill="none" stroke-linecap="round"/>`;
      for (let i = 0; i < 14; i++) {
        const t = (i + 1) / 15;
        const x = (1 - t) ** 3 * p[0][0] + 3 * (1 - t) ** 2 * t * p[1][0] + 3 * (1 - t) * t * t * p[2][0] + t ** 3 * p[3][0];
        const y = (1 - t) ** 3 * p[0][1] + 3 * (1 - t) ** 2 * t * p[1][1] + 3 * (1 - t) * t * t * p[2][1] + t ** 3 * p[3][1];
        for (let k = 0; k < 2; k++) {
          const a = r.range(0, 360);
          g += `<path d="${leafPath(r.range(60, 120), r.range(26, 46))}" transform="translate(${f(x)} ${f(y)}) rotate(${f(a)})"/>`;
        }
      }
    }
    shadowGroup(svg, g, 3.8);
    return svg.toString();
  },

  'flower-shadow'() {
    const svg = new Svg(S, S);
    const r = rng(41);
    let g = '';
    const stems = [[300, 1320, 360, 520], [560, 1340, 640, 360], [820, 1330, 980, 560], [1040, 1320, 1130, 700], [150, 1300, 190, 760]];
    for (const [x0, y0, x1, y1] of stems) {
      const cx = (x0 + x1) / 2 + r.range(-60, 60);
      g += `<path d="M${x0},${y0} Q${f(cx)},${f((y0 + y1) / 2)} ${x1},${y1}" stroke="${INK}" stroke-width="9" fill="none"/>`;
      for (let i = 1; i <= 3; i++) {
        const t = i / 4;
        const x = (1 - t) * (1 - t) * x0 + 2 * (1 - t) * t * cx + t * t * x1;
        const y = (1 - t) * (1 - t) * y0 + 2 * (1 - t) * t * ((y0 + y1) / 2) + t * t * y1;
        g += `<path d="${leafPath(150, 52)}" transform="translate(${f(x)} ${f(y)}) rotate(${i % 2 ? 62 : -62})"/>`;
      }
      const petals = r.int(6, 8);
      const size = r.range(70, 110);
      for (let p = 0; p < petals; p++) {
        g += `<ellipse cx="0" cy="${f(-size * 0.8)}" rx="${f(size * 0.34)}" ry="${f(size * 0.8)}" transform="translate(${x1} ${y1}) rotate(${f((360 / petals) * p)})"/>`;
      }
    }
    shadowGroup(svg, g, 3, 0.7);
    // Let light through each flower's centre.
    return svg.toString();
  },

  'tropical-leaf-shadow'() {
    const svg = new Svg(S, S);
    const r = rng(53);
    const m = svg.id('m');
    // Monstera style leaf with slits + holes.
    let slits = '';
    for (const side of [-1, 1]) {
      for (let i = 0; i < 7; i++) {
        const y = -250 + i * 78;
        const lenSlit = 300 - Math.abs(y + 100) * 0.35;
        slits += `<polygon points="0,${y} ${side * lenSlit},${y - 38} ${side * (lenSlit + 6)},${y - 12}" fill="#000"/>`;
      }
    }
    svg.def(`<mask id="${m}" maskUnits="userSpaceOnUse" x="-500" y="-500" width="1000" height="1000">` +
      `<path d="M0,-340 C260,-330 420,-110 380,90 C340,270 150,360 0,390 C-150,360 -340,270 -380,90 C-420,-110 -260,-330 0,-340 Z" fill="#fff"/>` +
      `<g>${slits}</g><circle cx="-90" cy="-60" r="26" fill="#000"/><circle cx="110" cy="20" r="30" fill="#000"/><circle cx="-60" cy="140" r="22" fill="#000"/></mask>`);
    let g = '';
    g += `<g transform="translate(330 470) rotate(-24) scale(1.05)"><rect x="-500" y="-500" width="1000" height="1000" mask="url(#${m})"/>` +
      `<path d="M0,380 L0,640" stroke="${INK}" stroke-width="14"/></g>`;
    g += `<g transform="translate(1010 330) rotate(32) scale(.82)"><rect x="-500" y="-500" width="1000" height="1000" mask="url(#${m})"/>` +
      `<path d="M0,380 L0,640" stroke="${INK}" stroke-width="14"/></g>`;
    // Banana style leaf with regular tears.
    const bm = svg.id('m');
    let cuts = '';
    for (let i = 0; i < 16; i++) {
      const y = -440 + i * 56;
      for (const side of [-1, 1]) cuts += `<polygon points="${side * 14},${y} ${side * 280},${y + 22} ${side * 280},${y + 34}" fill="#000"/>`;
    }
    svg.def(`<mask id="${bm}" maskUnits="userSpaceOnUse" x="-400" y="-600" width="800" height="1200"><path d="M0,-520 C170,-380 190,-60 150,200 C120,420 40,520 0,540 C-40,520 -120,420 -150,200 C-190,-60 -170,-380 0,-520 Z" fill="#fff"/>${cuts}</mask>`);
    g += `<g transform="translate(760 1010) rotate(14) scale(.95)"><rect x="-400" y="-600" width="800" height="1200" mask="url(#${bm})"/></g>`;
    shadowGroup(svg, g, 3.2, 0.72);
    return svg.toString();
  },
};
