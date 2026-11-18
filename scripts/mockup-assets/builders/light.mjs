import { Svg, f, rad, pts, rng } from '../lib.mjs';

const S = 1280;

/** Dark shadow field with light panes cut out through a mask. */
function windowPanes(svg, { cols, rows, skew, rotate, shadow, paneW, paneH, gap, ox, oy, blurStd }) {
  const m = svg.id('m');
  let panes = '';
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      panes += `<rect x="${f(ox + c * (paneW + gap))}" y="${f(oy + r * (paneH + gap))}" width="${paneW}" height="${paneH}" rx="2"/>`;
    }
  }
  svg.def(`<mask id="${m}" maskUnits="userSpaceOnUse" x="-400" y="-400" width="2100" height="2100">` +
    `<rect x="-400" y="-400" width="2100" height="2100" fill="#fff"/>` +
    `<g fill="#000" transform="rotate(${rotate} 640 640) skewX(${skew})">${panes}</g></mask>`);
  const b = svg.blur(blurStd);
  svg.add(`<g filter="url(#${b})"><rect x="-400" y="-400" width="2100" height="2100" fill="${shadow}" fill-opacity=".66" mask="url(#${m})"/></g>`);
}

export const light = {
  'window-shadow'() {
    const svg = new Svg(S, S);
    windowPanes(svg, { cols: 2, rows: 3, skew: -16, rotate: -6, shadow: '#0b0e14', paneW: 300, paneH: 300, gap: 34, ox: 200, oy: 70, blurStd: 9 });
    return svg.toString();
  },

  'window-frame-shadow'() {
    const svg = new Svg(S, S);
    const b = svg.blur(7);
    // Outer frame + mullions cast as thick bars.
    const bars = [];
    const x0 = 170, y0 = 60, w = 760, h = 1010, t = 46;
    bars.push(`<rect x="${x0}" y="${y0}" width="${w}" height="${t}"/>`);
    bars.push(`<rect x="${x0}" y="${y0 + h - t}" width="${w}" height="${t + 14}"/>`);
    bars.push(`<rect x="${x0}" y="${y0}" width="${t}" height="${h}"/>`);
    bars.push(`<rect x="${x0 + w - t}" y="${y0}" width="${t}" height="${h}"/>`);
    bars.push(`<rect x="${x0 + w / 2 - 15}" y="${y0}" width="30" height="${h}"/>`);
    bars.push(`<rect x="${x0}" y="${y0 + h * 0.36}" width="${w}" height="26"/>`);
    bars.push(`<rect x="${x0}" y="${y0 + h * 0.68}" width="${w}" height="26"/>`);
    svg.add(`<g filter="url(#${b})"><g fill="#0b0e14" fill-opacity=".62" transform="rotate(-5 640 640) skewX(-14) translate(120 -10)">${bars.join('')}</g></g>`);
    return svg.toString();
  },

  'sunlight-rays'() {
    const svg = new Svg(S, S);
    const r = rng(11);
    const grad = svg.linear([[0, '#fff6d6', 0.7], [0.55, '#ffe9ad', 0.3], [1, '#ffe9ad', 0]], 0, 0, 1, 0);
    const b = svg.blur(6);
    let rays = '';
    for (let i = 0; i < 30; i++) {
      const angle = r.range(4, 86);
      const width = r.range(8, 58);
      const op = r.range(0.35, 1);
      rays += `<g transform="rotate(${f(angle)} -80 -80)" opacity="${f(op)}"><rect x="-80" y="${f(-80 - width / 2)}" width="2300" height="${f(width)}" fill="url(#${grad})"/></g>`;
    }
    svg.add(`<g filter="url(#${b})">${rays}</g>`);
    const glow = svg.radial([[0, '#fff3cf', 0.85], [0.4, '#ffe3a0', 0.25], [1, '#ffe3a0', 0]], 0, 0, 0.95);
    svg.add(`<rect width="${S}" height="${S}" fill="url(#${glow})"/>`);
    return svg.toString();
  },

  'natural-light'() {
    const svg = new Svg(S, S);
    const warm = svg.radial([[0, '#fff0cc', 0.9], [0.35, '#ffe2a8', 0.42], [1, '#ffd9a0', 0]], 0.08, 0.04, 1.05);
    const cool = svg.radial([[0, '#cfe4ff', 0.32], [1, '#cfe4ff', 0]], 0.95, 1, 0.8);
    svg.add(`<rect width="${S}" height="${S}" fill="url(#${warm})"/><rect width="${S}" height="${S}" fill="url(#${cool})"/>`);
    return svg.toString();
  },

  'blind-shadows'() {
    const svg = new Svg(S, S);
    const b = svg.blur(3.2);
    let slats = '';
    for (let y = -300; y < 1700; y += 62) {
      slats += `<rect x="-600" y="${y}" width="2600" height="${32 + ((y / 62) % 3 === 0 ? 6 : 0)}"/>`;
    }
    svg.add(`<g filter="url(#${b})"><g fill="#0b0e14" fill-opacity=".62" transform="rotate(-9 640 640) skewX(-22)">${slats}</g></g>`);
    return svg.toString();
  },

  'hard-light'() {
    const svg = new Svg(S, S);
    const g = svg.linear([[0, '#fffaf0', 0.95], [1, '#ffe7b5', 0.55]], 0, 0, 1, 1);
    const b = svg.blur(1.4);
    const shapes = [
      pts([[-80, 120], [520, -40], [820, 340], [150, 640]]),
      pts([[600, 560], [1360, 330], [1360, 700], [740, 980]]),
      pts([[120, 760], [520, 700], [610, 1000], [210, 1120]]),
    ];
    svg.add(`<g filter="url(#${b})" fill="url(#${g})">${shapes.map((p) => `<polygon points="${p}"/>`).join('')}</g>`);
    return svg.toString();
  },

  'soft-light'() {
    const svg = new Svg(S, S);
    const a = svg.radial([[0, '#ffffff', 0.95], [1, '#ffffff', 0]], 0.28, 0.22, 0.7);
    const c = svg.radial([[0, '#ffe1b5', 0.7], [1, '#ffe1b5', 0]], 0.82, 0.78, 0.6);
    const d = svg.linear([[0, '#10141c', 0], [1, '#10141c', 0.35]], 0, 0.4, 0, 1);
    svg.add(`<rect width="${S}" height="${S}" fill="url(#${d})"/><rect width="${S}" height="${S}" fill="url(#${a})"/><rect width="${S}" height="${S}" fill="url(#${c})"/>`);
    return svg.toString();
  },

  'long-shadow'() {
    const svg = new Svg(S, S);
    const g = svg.linear([[0, '#080b11', 0.78], [0.7, '#080b11', 0.35], [1, '#080b11', 0]], 0, 0, 1, 0);
    const b = svg.blur(5);
    let out = '';
    const stripes = [[-40, 90], [250, 54], [470, 150], [820, 70]];
    for (const [off, wid] of stripes) {
      out += `<polygon points="${pts([[-100, 1100 + off * 0.1], [1500, 380 + off * 0.1], [1500, 380 + wid + off * 0.1], [-100, 1100 + wid * 1.4 + off * 0.1]])}" fill="url(#${g})" transform="translate(0 ${off - 180})"/>`;
    }
    svg.add(`<g filter="url(#${b})">${out}</g>`);
    return svg.toString();
  },

  'floating-shadow'() {
    const svg = new Svg(S, S);
    const b1 = svg.blur(34), b2 = svg.blur(62);
    svg.add(`<ellipse cx="640" cy="1000" rx="430" ry="82" fill="#05070b" fill-opacity=".26" filter="url(#${b2})"/>`);
    svg.add(`<ellipse cx="640" cy="988" rx="300" ry="42" fill="#05070b" fill-opacity=".6" filter="url(#${b1})"/>`);
    return svg.toString();
  },

  'product-shadow'() {
    const svg = new Svg(S, S);
    const b1 = svg.blur(12), b2 = svg.blur(46), b3 = svg.blur(26);
    svg.add(`<ellipse cx="700" cy="930" rx="420" ry="70" fill="#05070b" fill-opacity=".22" filter="url(#${b2})"/>`);
    svg.add(`<polygon points="${pts([[560, 900], [1020, 1000], [900, 1040], [470, 940]])}" fill="#05070b" fill-opacity=".2" filter="url(#${b3})"/>`);
    svg.add(`<ellipse cx="640" cy="918" rx="290" ry="20" fill="#05070b" fill-opacity=".72" filter="url(#${b1})"/>`);
    return svg.toString();
  },
};
