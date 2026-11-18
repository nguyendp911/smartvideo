import { Svg, f, rad, rng, pts } from '../lib.mjs';

// Scene mockups: the artwork covers the whole canvas and leaves a transparent
// WINDOW (the slot) where the user's photo is placed. Builders return
// { svg, slot: {x,y,w,h} } with the slot in pixels.

const rr = (x, y, w, h, r, fill, extra = '') => `<rect x="${f(x)}" y="${f(y)}" width="${f(w)}" height="${f(h)}" rx="${r}" fill="${fill}" ${extra}/>`;

/** Draw `markup` and mark `slot` as a transparent window through the whole scene. */
function withHole(svg, markup, slot, radius = 0) {
  svg.add(markup);
  svg.cutWindow(slot, radius);
}

function dropShadow(svg, x, y, w, h, r, std, opacity, dx = 0, dy = 18) {
  const b = svg.blur(std);
  svg.add(`<rect x="${x + dx}" y="${y + dy}" width="${w}" height="${h}" rx="${r}" fill="#0a0a0c" fill-opacity="${opacity}" filter="url(#${b})"/>`);
}

function backdrop(svg, top, bottom, noiseOpacity = 0.05, seed = 4) {
  const g = svg.linear([[0, top], [1, bottom]]);
  svg.add(`<rect width="${svg.w}" height="${svg.h}" fill="url(#${g})"/>`);
  const n = svg.noise(0.85, 2, seed, 'gray');
  svg.add(`<rect width="${svg.w}" height="${svg.h}" filter="url(#${n})" opacity="${noiseOpacity}"/>`);
}

function vignette(svg, strength = 0.28) {
  const v = svg.radial([[0.55, '#000', 0], [1, '#000', strength]], 0.5, 0.5, 0.78);
  svg.add(`<rect width="${svg.w}" height="${svg.h}" fill="url(#${v})"/>`);
}

export const frames = {
  'polaroid-frame'() {
    const svg = new Svg(1200, 1500);
    backdrop(svg, '#e9e2d6', '#cfc4b4');
    const cx = 160, cy = 190, cw = 880, ch = 1066;
    const slot = { x: cx + 45, y: cy + 45, w: 790, h: 790 };
    dropShadow(svg, cx, cy, cw, ch, 6, 26, 0.45, 8, 28);
    const paper = svg.linear([[0, '#fdfcf8'], [1, '#efece3']]);
    withHole(svg, rr(cx, cy, cw, ch, 6, `url(#${paper})`), slot);
    // Inner bevel of the window + a hand-written line area.
    svg.add(`<rect x="${slot.x - 2}" y="${slot.y - 2}" width="${slot.w + 4}" height="${slot.h + 4}" fill="none" stroke="#000" stroke-opacity=".18" stroke-width="4"/>`);
    svg.add(`<path d="M${cx + 130},${cy + 960} q90,-26 190,2 t210,-4" stroke="#6c6a63" stroke-opacity=".5" stroke-width="5" fill="none" stroke-linecap="round"/>`);
    for (const [x, rot] of [[cx + 60, -32], [cx + cw - 60, 28]]) {
      svg.add(`<rect x="-80" y="-24" width="160" height="48" fill="#ecdfae" fill-opacity=".72" transform="translate(${x} ${cy + 6}) rotate(${rot})"/>`);
    }
    return { svg: svg.toString(), slot };
  },

  'film-frame'() {
    const svg = new Svg(1500, 1200);
    backdrop(svg, '#f6f6f3', '#e4e4df', 0.04);
    const stripY = 170, stripH = 860;
    const slot = { x: 250, y: 266, w: 1000, h: 667 };
    const strip = svg.linear([[0, '#1d1511'], [1, '#120d0a']]);
    dropShadow(svg, 0, stripY, 1500, stripH, 0, 24, 0.35, 0, 14);
    let art = `<rect x="0" y="${stripY}" width="1500" height="${stripH}" fill="url(#${strip})"/>`;
    // Neighbouring frames (partially visible), sprocket holes and edge marks.
    art += `<rect x="-300" y="266" width="520" height="667" fill="#3b2a1d"/><rect x="1280" y="266" width="520" height="667" fill="#3b2a1d"/>`;
    for (let x = 18; x < 1500; x += 62) {
      art += rr(x, stripY + 24, 34, 48, 8, '#f2f1ec') + rr(x, stripY + stripH - 72, 34, 48, 8, '#f2f1ec');
    }
    for (let x = 40; x < 1500; x += 250) art += `<rect x="${x}" y="${stripY + 90}" width="60" height="9" fill="#e9a23b" fill-opacity=".7"/><rect x="${x + 80}" y="${stripY + 90}" width="22" height="9" fill="#e9a23b" fill-opacity=".7"/>`;
    withHole(svg, art, slot);
    svg.add(`<rect x="${slot.x - 3}" y="${slot.y - 3}" width="${slot.w + 6}" height="${slot.h + 6}" fill="none" stroke="#000" stroke-width="6"/>`);
    return { svg: svg.toString(), slot };
  },

  'vintage-frame'() {
    const svg = new Svg(1200, 1500);
    backdrop(svg, '#4b3b34', '#2f2420', 0.07);
    let stripes = '';
    for (let x = 0; x < 1200; x += 60) stripes += `<rect x="${x}" y="0" width="28" height="1500" fill="#fff" fill-opacity=".035"/>`;
    svg.add(stripes);
    const outer = { x: 120, y: 170, w: 960, h: 1160 };
    const slot = { x: 280, y: 330, w: 640, h: 840 };
    dropShadow(svg, outer.x, outer.y, outer.w, outer.h, 10, 30, 0.6, 14, 30);
    const gold = svg.linear([[0, '#f1d58a'], [0.3, '#b98a36'], [0.55, '#f4e0a4'], [1, '#8f6422']], 0, 0, 1, 1);
    const inset = (n) => ({ x: outer.x + n, y: outer.y + n, w: outer.w - 2 * n, h: outer.h - 2 * n });
    let art = rr(outer.x, outer.y, outer.w, outer.h, 10, `url(#${gold})`);
    const dark = svg.linear([[0, '#6a4a1c'], [1, '#c79a47']], 0, 0, 1, 1);
    for (const [n, fill] of [[36, `url(#${dark})`], [62, `url(#${gold})`], [96, '#2a1d12'], [112, `url(#${gold})`], [138, '#efe4cb']]) {
      const b = inset(n);
      art += rr(b.x, b.y, b.w, b.h, 6, fill);
    }
    for (const [x, y] of [[outer.x + 54, outer.y + 54], [outer.x + outer.w - 54, outer.y + 54], [outer.x + 54, outer.y + outer.h - 54], [outer.x + outer.w - 54, outer.y + outer.h - 54]]) {
      art += `<circle cx="${x}" cy="${y}" r="34" fill="url(#${gold})" stroke="#6a4a1c" stroke-width="4"/><circle cx="${x}" cy="${y}" r="14" fill="#6a4a1c"/>`;
    }
    withHole(svg, art, slot);
    svg.add(`<rect x="${slot.x - 2}" y="${slot.y - 2}" width="${slot.w + 4}" height="${slot.h + 4}" fill="none" stroke="#000" stroke-opacity=".35" stroke-width="5"/>`);
    vignette(svg, 0.34);
    return { svg: svg.toString(), slot };
  },

  'photo-frame'() {
    const svg = new Svg(1200, 1500);
    backdrop(svg, '#efede8', '#dcd8d0', 0.05, 8);
    const light = svg.radial([[0, '#fff', 0.7], [1, '#fff', 0]], 0.3, 0.2, 0.9);
    svg.add(`<rect width="1200" height="1500" fill="url(#${light})"/>`);
    const outer = { x: 170, y: 220, w: 860, h: 1060 };
    const slot = { x: 300, y: 350, w: 600, h: 800 };
    dropShadow(svg, outer.x, outer.y, outer.w, outer.h, 4, 22, 0.4, 10, 26);
    const wood = svg.linear([[0, '#2a2522'], [1, '#12100f']], 0, 0, 1, 1);
    let art = rr(outer.x, outer.y, outer.w, outer.h, 4, `url(#${wood})`);
    art += rr(outer.x + 26, outer.y + 26, outer.w - 52, outer.h - 52, 2, '#f8f7f3');
    withHole(svg, art, slot);
    svg.add(`<rect x="${slot.x - 3}" y="${slot.y - 3}" width="${slot.w + 6}" height="${slot.h + 6}" fill="none" stroke="#000" stroke-opacity=".28" stroke-width="6"/>`);
    svg.add(`<path d="M600,130 L${outer.x + 160},${outer.y + 6} M600,130 L${outer.x + outer.w - 160},${outer.y + 6}" stroke="#6b6258" stroke-width="3" fill="none"/><circle cx="600" cy="128" r="9" fill="#9b9187"/>`);
    return { svg: svg.toString(), slot };
  },

  'magazine-frame'() {
    const svg = new Svg(1200, 1500);
    backdrop(svg, '#d9d3c8', '#c5bdaf', 0.05, 12);
    const page = { x: 90, y: 90, w: 1020, h: 1320 };
    const slot = { x: 150, y: 330, w: 900, h: 640 };
    dropShadow(svg, page.x, page.y, page.w, page.h, 4, 26, 0.4, 10, 22);
    let art = rr(page.x, page.y, page.w, page.h, 4, '#fbf9f4');
    art += rr(150, 140, 420, 44, 4, '#1c1a19') + rr(150, 196, 180, 14, 3, '#c24a3a');
    art += rr(150, 250, 900, 6, 2, '#1c1a19', 'fill-opacity=".85"');
    // Caption + three text columns made of bars.
    art += rr(150, 990, 600, 14, 3, '#6a665f') + rr(150, 1014, 420, 10, 3, '#9d988f');
    for (let col = 0; col < 3; col++) {
      for (let line = 0; line < 8; line++) {
        art += rr(150 + col * 310, 1070 + line * 38, 280 - (line === 7 ? 120 : 0), 11, 3, '#8a857c', 'fill-opacity=".8"');
      }
    }
    art += rr(960, 1360, 90, 12, 3, '#8a857c');
    withHole(svg, art, slot);
    const gutter = svg.linear([[0, '#000', 0.22], [1, '#000', 0]], 0, 0, 1, 0);
    svg.add(`<rect x="${page.x}" y="${page.y}" width="120" height="${page.h}" fill="url(#${gutter})"/>`);
    return { svg: svg.toString(), slot };
  },
};

export const products = {
  'cosmetic-packaging'() {
    const svg = new Svg(1200, 1500);
    backdrop(svg, '#efe6da', '#d8c9b6');
    const floor = svg.linear([[0, '#c9b79f'], [1, '#b8a389']]);
    svg.add(`<rect y="1130" width="1200" height="370" fill="url(#${floor})"/>`);
    const box = { x: 290, y: 330, w: 500, h: 800 };
    const slot = { x: 350, y: 520, w: 380, h: 420 };
    const bSh = svg.blur(22);
    svg.add(`<ellipse cx="560" cy="1140" rx="360" ry="34" fill="#000" fill-opacity=".34" filter="url(#${bSh})"/>`);
    const body = svg.linear([[0, '#fbf6ec'], [0.7, '#efe7d8'], [1, '#e1d6c2']], 0, 0, 1, 0);
    let art = rr(box.x, box.y, box.w, box.h, 14, `url(#${body})`);
    art += rr(box.x + 40, box.y + 40, 120, 8, 3, '#b08a4f') + rr(box.x + 40, box.y + box.h - 70, 220, 10, 3, '#b08a4f');
    withHole(svg, art, slot, 6);
    svg.add(`<rect x="${slot.x - 2}" y="${slot.y - 2}" width="${slot.w + 4}" height="${slot.h + 4}" rx="6" fill="none" stroke="#b08a4f" stroke-width="4"/>`);
    // Jar with gold lid beside the box.
    const jar = svg.linear([[0, '#e8dfd0'], [0.4, '#fffaf0'], [1, '#cdbfa8']], 0, 0, 1, 0);
    const lid = svg.linear([[0, '#a97d3a'], [0.45, '#f0d089'], [1, '#8d6528']], 0, 0, 1, 0);
    svg.add(`<ellipse cx="930" cy="1128" rx="170" ry="26" fill="#000" fill-opacity=".3" filter="url(#${bSh})"/>`);
    svg.add(`<path d="M780,980 L780,1100 Q780,1140 930,1140 Q1080,1140 1080,1100 L1080,980 Z" fill="url(#${jar})"/>`);
    svg.add(`<ellipse cx="930" cy="980" rx="150" ry="26" fill="#efe7d8"/><path d="M780,930 L780,985 Q780,1012 930,1012 Q1080,1012 1080,985 L1080,930 Z" fill="url(#${lid})"/><ellipse cx="930" cy="930" rx="150" ry="26" fill="#f6dfa0"/>`);
    vignette(svg, 0.2);
    return { svg: svg.toString(), slot };
  },

  'perfume-bottle'() {
    const svg = new Svg(1200, 1500);
    backdrop(svg, '#f2dcd8', '#d9b8b4');
    const floor = svg.linear([[0, '#c9a5a2'], [1, '#b58f8c']]);
    svg.add(`<rect y="1200" width="1200" height="300" fill="url(#${floor})"/>`);
    const bSh = svg.blur(24);
    svg.add(`<ellipse cx="600" cy="1210" rx="330" ry="34" fill="#000" fill-opacity=".34" filter="url(#${bSh})"/>`);
    const glass = svg.linear([[0, '#f8e9e6', 0.9], [0.18, '#ffffff', 0.5], [0.55, '#e6c7c4', 0.55], [1, '#c99f9b', 0.8]], 0, 0, 1, 0);
    const liquid = svg.linear([[0, '#f0b9a8'], [1, '#d98a7c']], 0, 0, 0, 1);
    const gold = svg.linear([[0, '#a67b36'], [0.5, '#f3d894'], [1, '#8a6125']], 0, 0, 1, 0);
    const slot = { x: 460, y: 760, w: 280, h: 250 };
    // Bottle: body, liquid, neck, collar, cap.
    let art = '';
    art += rr(360, 640, 480, 570, 34, `url(#${glass})`);
    art += rr(384, 800, 432, 384, 22, `url(#${liquid})`, 'fill-opacity=".85"');
    art += rr(540, 560, 120, 90, 10, `url(#${glass})`) + rr(520, 528, 160, 40, 8, `url(#${gold})`);
    art += rr(500, 330, 200, 200, 16, `url(#${gold})`);
    art += `<rect x="372" y="652" width="30" height="520" rx="15" fill="#fff" fill-opacity=".5"/>`;
    withHole(svg, art, slot, 8);
    svg.add(`<rect x="${slot.x - 3}" y="${slot.y - 3}" width="${slot.w + 6}" height="${slot.h + 6}" rx="8" fill="none" stroke="#a67b36" stroke-width="5"/>`);
    vignette(svg, 0.22);
    return { svg: svg.toString(), slot };
  },

  'skincare-bottle'() {
    const svg = new Svg(1200, 1500);
    backdrop(svg, '#dfe8de', '#bccdba');
    const bSh = svg.blur(20);
    const podium = svg.linear([[0, '#f3f5f1'], [1, '#d3dbd0']], 0, 0, 1, 0);
    svg.add(`<ellipse cx="600" cy="1230" rx="420" ry="64" fill="#000" fill-opacity=".25" filter="url(#${bSh})"/>`);
    svg.add(`<path d="M180,1170 L180,1250 Q180,1316 600,1316 Q1020,1316 1020,1250 L1020,1170 Z" fill="url(#${podium})"/><ellipse cx="600" cy="1170" rx="420" ry="64" fill="#fbfcfa"/>`);
    const body = svg.linear([[0, '#e6ebe4'], [0.35, '#ffffff'], [1, '#c9d2c6']], 0, 0, 1, 0);
    const pump = svg.linear([[0, '#b4a07a'], [0.5, '#efe0b6'], [1, '#8d7a55']], 0, 0, 1, 0);
    const slot = { x: 450, y: 560, w: 300, h: 420 };
    let art = rr(410, 400, 380, 780, 70, `url(#${body})`);
    art += rr(550, 320, 100, 90, 12, `url(#${pump})`) + rr(530, 250, 140, 80, 18, `url(#${pump})`) + `<path d="M660,270 h110 q20,0 20,20 v18 h-60" fill="url(#${pump})"/>`;
    art += `<rect x="424" y="420" width="26" height="740" rx="13" fill="#fff" fill-opacity=".6"/>`;
    withHole(svg, art, slot, 10);
    svg.add(`<rect x="${slot.x - 2}" y="${slot.y - 2}" width="${slot.w + 4}" height="${slot.h + 4}" rx="10" fill="none" stroke="#8d7a55" stroke-opacity=".6" stroke-width="3"/>`);
    vignette(svg, 0.2);
    return { svg: svg.toString(), slot };
  },

  'product-box'() {
    const svg = new Svg(1200, 1500);
    backdrop(svg, '#e8e6e1', '#cfcbc2');
    const bSh = svg.blur(26);
    svg.add(`<polygon points="${pts([[210, 1250], [880, 1250], [1130, 1190], [470, 1190]])}" fill="#000" fill-opacity=".3" filter="url(#${bSh})"/>`);
    const front = svg.linear([[0, '#fbfaf7'], [1, '#ebe8e1']], 0, 0, 1, 1);
    const side = svg.linear([[0, '#cfcac0'], [1, '#aea99e']], 0, 0, 1, 0);
    const top = svg.linear([[0, '#ffffff'], [1, '#e4e0d7']], 0, 0, 1, 1);
    const slot = { x: 280, y: 480, w: 420, h: 560 };
    let art = `<rect x="210" y="360" width="590" height="860" fill="url(#${front})"/>`;
    art += `<polygon points="${pts([[800, 360], [1000, 300], [1000, 1160], [800, 1220]])}" fill="url(#${side})"/>`;
    art += `<polygon points="${pts([[210, 360], [410, 300], [1000, 300], [800, 360]])}" fill="url(#${top})"/>`;
    art += `<rect x="210" y="1160" width="590" height="60" fill="#000" fill-opacity=".05"/>`;
    withHole(svg, art, slot);
    svg.add(`<rect x="${slot.x - 2}" y="${slot.y - 2}" width="${slot.w + 4}" height="${slot.h + 4}" fill="none" stroke="#000" stroke-opacity=".22" stroke-width="4"/>`);
    vignette(svg, 0.2);
    return { svg: svg.toString(), slot };
  },

  'shopping-bag'() {
    const svg = new Svg(1200, 1500);
    backdrop(svg, '#efe9df', '#d6ccbc');
    const bSh = svg.blur(26);
    svg.add(`<ellipse cx="600" cy="1290" rx="420" ry="40" fill="#000" fill-opacity=".32" filter="url(#${bSh})"/>`);
    const kraft = svg.linear([[0, '#d6b185'], [0.5, '#caa274'], [1, '#b58a5a']], 0, 0, 1, 0);
    const handle = svg.linear([[0, '#8a6a46'], [1, '#6d5233']], 0, 0, 1, 0);
    const slot = { x: 430, y: 640, w: 340, h: 400 };
    // Rope handles behind the bag.
    svg.add(`<path d="M470,430 C470,200 600,200 600,360" stroke="url(#${handle})" stroke-width="16" fill="none" stroke-linecap="round"/>` +
      `<path d="M730,430 C730,200 600,200 600,360" stroke="url(#${handle})" stroke-width="16" fill="none" stroke-linecap="round" opacity=".0"/>` +
      `<path d="M730,430 C730,210 860,210 860,360" stroke="url(#${handle})" stroke-width="16" fill="none" stroke-linecap="round" opacity=".0"/>`);
    svg.add(`<path d="M450,440 C430,180 770,180 750,440" stroke="url(#${handle})" stroke-width="18" fill="none" stroke-linecap="round"/>`);
    let art = `<rect x="260" y="420" width="680" height="860" rx="8" fill="url(#${kraft})"/>`;
    art += `<rect x="260" y="420" width="680" height="70" fill="#000" fill-opacity=".1"/>`;
    art += `<rect x="260" y="420" width="46" height="860" fill="#000" fill-opacity=".1"/><rect x="894" y="420" width="46" height="860" fill="#000" fill-opacity=".14"/>`;
    art += `<circle cx="450" cy="455" r="12" fill="#5d4426"/><circle cx="750" cy="455" r="12" fill="#5d4426"/>`;
    withHole(svg, art, slot, 4);
    svg.add(`<rect x="${slot.x - 10}" y="${slot.y - 10}" width="${slot.w + 20}" height="${slot.h + 20}" fill="none" stroke="#fbf7ee" stroke-width="20"/>`);
    vignette(svg, 0.2);
    return { svg: svg.toString(), slot };
  },

  'poster'() {
    const svg = new Svg(1200, 1500);
    const wall = svg.linear([[0, '#e7e3dc'], [1, '#d5d0c6']]);
    svg.add(`<rect width="1200" height="1500" fill="url(#${wall})"/>`);
    const n = svg.noise(0.7, 3, 21, 'gray');
    svg.add(`<rect width="1200" height="1500" filter="url(#${n})" opacity=".05"/>`);
    const floor = svg.linear([[0, '#9b7a58'], [1, '#6f5339']]);
    svg.add(`<rect y="1290" width="1200" height="210" fill="url(#${floor})"/><rect y="1280" width="1200" height="14" fill="#f4f1ea"/>`);
    const light = svg.radial([[0, '#fff', 0.6], [1, '#fff', 0]], 0.5, 0.3, 0.8);
    svg.add(`<rect width="1200" height="1500" fill="url(#${light})"/>`);
    const frame = { x: 210, y: 150, w: 780, h: 1060 };
    const slot = { x: 262, y: 202, w: 676, h: 956 };
    dropShadow(svg, frame.x, frame.y, frame.w, frame.h, 3, 24, 0.4, 12, 22);
    let art = rr(frame.x, frame.y, frame.w, frame.h, 3, '#1b1b1d') + rr(frame.x + 28, frame.y + 28, frame.w - 56, frame.h - 56, 1, '#fbfaf7');
    withHole(svg, art, slot);
    svg.add(`<rect x="${slot.x - 2}" y="${slot.y - 2}" width="${slot.w + 4}" height="${slot.h + 4}" fill="none" stroke="#000" stroke-opacity=".25" stroke-width="4"/>`);
    // Console + plant.
    svg.add(rr(120, 1240, 960, 40, 4, '#7a5a3d') + rr(170, 1280, 18, 160, 3, '#5c4229') + rr(1012, 1280, 18, 160, 3, '#5c4229'));
    svg.add(rr(900, 1130, 120, 110, 18, '#e8dccb'));
    const r = rng(5);
    for (let i = 0; i < 8; i++) svg.add(`<path d="M960,1130 q${r.range(-120, 120)},-140 ${r.range(-150, 150)},-${r.range(180, 300)}" stroke="#5a7a4a" stroke-width="7" fill="none"/>`);
    vignette(svg, 0.22);
    return { svg: svg.toString(), slot };
  },

  'business-card'() {
    const svg = new Svg(1500, 1100);
    const wood = svg.linear([[0, '#a47a52'], [1, '#6f4e31']]);
    svg.add(`<rect width="1500" height="1100" fill="url(#${wood})"/>`);
    const grain = svg.surface([0.003, 0.09], 4, 7, 2, 70, '#d9b48a', 1.0, 0.0);
    svg.add(`<rect width="1500" height="1100" filter="url(#${grain})" opacity=".35"/>`);
    const card = { x: 240, y: 250, w: 1020, h: 583 };
    const slot = { x: 250, y: 260, w: 1000, h: 563 };
    // Stack of cards below + shadow.
    for (const [dx, dy, c] of [[34, 40, '#e9e6df'], [18, 22, '#f1eee8']]) {
      dropShadow(svg, card.x + dx, card.y + dy, card.w, card.h, 5, 10, 0.25, 0, 6);
      svg.add(rr(card.x + dx, card.y + dy, card.w, card.h, 5, c));
    }
    dropShadow(svg, card.x, card.y, card.w, card.h, 5, 18, 0.45, 8, 22);
    const paper = svg.linear([[0, '#ffffff'], [1, '#f1eee8']], 0, 0, 1, 1);
    withHole(svg, rr(card.x, card.y, card.w, card.h, 5, `url(#${paper})`), slot);
    svg.add(`<rect x="${slot.x - 1}" y="${slot.y - 1}" width="${slot.w + 2}" height="${slot.h + 2}" fill="none" stroke="#000" stroke-opacity=".14" stroke-width="2"/>`);
    vignette(svg, 0.3);
    return { svg: svg.toString(), slot };
  },

  'magazine-cover'() {
    const svg = new Svg(1200, 1500);
    backdrop(svg, '#cfd2d4', '#aeb3b6', 0.05, 15);
    const cover = { x: 190, y: 140, w: 820, h: 1200 };
    const slot = { x: 190, y: 400, w: 820, h: 740 };
    dropShadow(svg, cover.x, cover.y, cover.w, cover.h, 4, 28, 0.45, 12, 26);
    let art = rr(cover.x, cover.y, cover.w, cover.h, 4, '#f7f5f0');
    art += rr(cover.x + 40, cover.y + 36, 620, 120, 6, '#1f1f22') + rr(cover.x + 40, cover.y + 176, 360, 16, 4, '#c44a3a') + rr(cover.x + 40, cover.y + 204, 220, 12, 3, '#8d8a84');
    art += rr(cover.x + 700, cover.y + 40, 80, 80, 40, '#c44a3a');
    // Cover lines + barcode.
    for (let i = 0; i < 4; i++) art += rr(cover.x + 40, cover.y + 980 + i * 38, 520 - i * 70, 16, 4, i === 0 ? '#1f1f22' : '#6a665f');
    art += rr(cover.x + 600, cover.y + 960, 180, 170, 4, '#fff');
    for (let i = 0; i < 28; i++) art += `<rect x="${cover.x + 614 + i * 6}" y="${cover.y + 976}" width="${i % 3 === 0 ? 4 : 2}" height="110" fill="#111"/>`;
    withHole(svg, art, slot);
    const spine = svg.linear([[0, '#000', 0.25], [1, '#000', 0]], 0, 0, 1, 0);
    svg.add(`<rect x="${cover.x}" y="${cover.y}" width="46" height="${cover.h}" fill="url(#${spine})"/>`);
    return { svg: svg.toString(), slot };
  },

  'book-cover'() {
    const svg = new Svg(1200, 1500);
    backdrop(svg, '#e6dfd3', '#c9bdaa');
    const bSh = svg.blur(26);
    svg.add(`<ellipse cx="640" cy="1290" rx="470" ry="44" fill="#000" fill-opacity=".34" filter="url(#${bSh})"/>`);
    const front = svg.linear([[0, '#243a4f'], [1, '#162636']], 0, 0, 1, 1);
    const spine = svg.linear([[0, '#0f1c29'], [1, '#243a4f']], 0, 0, 1, 0);
    const slot = { x: 380, y: 360, w: 540, h: 720 };
    let art = `<rect x="300" y="300" width="680" height="960" rx="6" fill="url(#${front})"/>`;
    art += `<rect x="300" y="300" width="60" height="960" fill="url(#${spine})"/>`;
    art += rr(380, 1120, 360, 22, 4, '#d9b865') + rr(380, 1160, 220, 14, 3, '#9fb2c4');
    withHole(svg, art, slot, 2);
    // Page block on the right edge.
    svg.add(`<polygon points="${pts([[980, 306], [1040, 330], [1040, 1230], [980, 1254]])}" fill="#f0e9d8"/>`);
    for (let i = 0; i < 40; i++) svg.add(`<line x1="980" y1="${310 + i * 23.5}" x2="1040" y2="${334 + i * 23.5}" stroke="#bcae8c" stroke-opacity=".5" stroke-width="1"/>`);
    svg.add(`<polygon points="${pts([[300, 300], [360, 276], [1040, 330], [980, 306]])}" fill="#fff" fill-opacity=".14"/>`);
    svg.add(`<rect x="${slot.x - 2}" y="${slot.y - 2}" width="${slot.w + 4}" height="${slot.h + 4}" fill="none" stroke="#d9b865" stroke-width="4"/>`);
    vignette(svg, 0.2);
    return { svg: svg.toString(), slot };
  },
};
