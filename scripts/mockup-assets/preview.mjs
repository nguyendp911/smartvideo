// Dev helper: render builders over a sample photo into out/sheet-*.jpg to inspect them.
import sharp from 'sharp';
import fs from 'node:fs';
import { Svg, rng } from './lib.mjs';

export function samplePhoto(size = 1280) {
  const svg = new Svg(1280, 1280);
  const wall = svg.linear([[0, '#e9dccb'], [1, '#cdb79b']]);
  const table = svg.linear([[0, '#a47b52'], [1, '#6f4d30']]);
  const sun = svg.radial([[0, '#fff6d8', 0.9], [1, '#fff6d8', 0]], 0.7, 0.3, 0.6);
  const vase = svg.linear([[0, '#d9d3c7'], [0.5, '#f2eee6'], [1, '#bdb5a6']], 0, 0, 1, 0);
  svg.add(`<rect width="1280" height="1280" fill="url(#${wall})"/>`);
  svg.add(`<rect width="1280" height="1280" fill="url(#${sun})"/>`);
  svg.add(`<rect y="860" width="1280" height="420" fill="url(#${table})"/>`);
  svg.add(`<ellipse cx="640" cy="872" rx="360" ry="22" fill="#000" fill-opacity=".25"/>`);
  svg.add(`<path d="M560,860 C520,700 540,560 590,500 L690,500 C740,560 760,700 720,860 Z" fill="url(#${vase})"/>`);
  svg.add(`<rect x="598" y="468" width="84" height="40" rx="8" fill="#e6e0d3"/>`);
  const r = rng(5);
  for (let i = 0; i < 9; i++) {
    const a = r.range(-70, 70);
    svg.add(`<path d="M640,470 q${a * 2},-160 ${a * 3.2},-300" stroke="#55703f" stroke-width="7" fill="none"/>` +
      `<ellipse cx="${640 + a * 3.2}" cy="${170 + r.range(0, 40)}" rx="30" ry="58" fill="#6c8a4b" transform="rotate(${a} ${640 + a * 3.2} 190)"/>`);
  }
  svg.add(`<rect x="860" y="740" width="150" height="120" rx="10" fill="#f6f1e8"/><rect x="880" y="700" width="110" height="40" rx="8" fill="#c8553d"/>`);
  svg.add(`<circle cx="320" cy="800" r="70" fill="#e0b25a"/><circle cx="305" cy="785" r="20" fill="#f7dc9a" fill-opacity=".7"/>`);
  return svg.toString();
}

export async function sheet(name, items, builders, cols = 4, cell = 320) {
  const base = await sharp(Buffer.from(samplePhoto())).resize(cell, cell).jpeg().toBuffer();
  const rows = Math.ceil(items.length / cols);
  const comps = [];
  const bg = { create: { width: cols * cell, height: rows * cell, channels: 3, background: '#222' } };
  let i = 0;
  for (const [id, blend] of items) {
    const svg = builders[id]();
    const overlay = await sharp(Buffer.from(svg)).resize(cell, cell).png().toBuffer();
    const tile = await sharp(base).composite([{ input: overlay, blend }]).jpeg().toBuffer();
    const x = (i % cols) * cell, y = Math.floor(i / cols) * cell;
    comps.push({ input: tile, left: x, top: y });
    i++;
  }
  fs.mkdirSync('out', { recursive: true });
  await sharp(bg).composite(comps).jpeg({ quality: 88 }).toFile(`out/sheet-${name}.jpg`);
}

if (process.argv[1].endsWith('preview.mjs')) {
  const group = process.argv[2];
  const mods = await Promise.all(['light', 'nature', 'effects', 'weather'].map((n) => import(`./builders/${n}.mjs`)));
  const builders = Object.assign({}, ...mods.map((m) => Object.assign({}, ...Object.values(m))));
  const defs = {
    light: [['window-shadow', 'multiply'], ['window-frame-shadow', 'multiply'], ['sunlight-rays', 'screen'], ['natural-light', 'soft-light'],
      ['blind-shadows', 'multiply'], ['hard-light', 'screen'], ['soft-light', 'soft-light'], ['long-shadow', 'multiply'],
      ['floating-shadow', 'multiply'], ['product-shadow', 'multiply']],
    nature: [['palm-leaf-shadow', 'multiply'], ['plant-shadow', 'multiply'], ['tree-branch-shadow', 'multiply'],
      ['flower-shadow', 'multiply'], ['tropical-leaf-shadow', 'multiply']],
    photo: [['film-grain', 'overlay'], ['light-leak', 'screen'], ['lens-flare', 'screen'], ['haze', 'screen'], ['glow', 'screen'],
      ['vignette', 'multiply'], ['dust', 'screen'], ['scratches', 'screen'], ['bokeh', 'screen'], ['chromatic-aberration', 'screen']],
    glass: [['frosted-glass', 'over'], ['glass-reflection', 'screen'], ['glass-blur', 'over'], ['glass-distortion', 'overlay'], ['water-droplets', 'over']],
    weather: [['rain', 'screen'], ['snow', 'screen'], ['fog', 'screen'], ['mist', 'screen'], ['sun-flare', 'screen'], ['water-reflection', 'overlay']],
    retro: [['vhs', 'overlay'], ['halftone', 'multiply'], ['duotone', 'overlay'], ['film-burn', 'screen'], ['vintage-film', 'multiply'], ['analog-noise', 'overlay']],
  };
  await sheet(group, defs[group], builders);
  console.log('wrote out/sheet-' + group + '.jpg');
}
