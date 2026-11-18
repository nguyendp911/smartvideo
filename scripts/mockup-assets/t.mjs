import sharp from 'sharp';
const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="400" height="300">
<defs><filter id="n" x="0" y="0" width="100%" height="100%"><feTurbulence type="fractalNoise" baseFrequency="0.02" numOctaves="4" seed="3" result="t"/><feDiffuseLighting in="t" lighting-color="#fff" surfaceScale="5"><feDistantLight azimuth="45" elevation="60"/></feDiffuseLighting></filter>
<filter id="b"><feGaussianBlur stdDeviation="8"/></filter></defs>
<rect width="400" height="300" filter="url(#n)"/><polygon points="50,50 200,80 150,200" fill="#000" fill-opacity=".6" filter="url(#b)"/></svg>`;
const t=Date.now();
await sharp(Buffer.from(svg)).webp({quality:80}).toFile('out/t.webp');
const m = await sharp('out/t.webp').metadata();
console.log(m.format, m.width, m.height, m.hasAlpha, Date.now()-t,'ms');
