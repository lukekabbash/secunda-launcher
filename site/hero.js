// The hero sky: the app icon's crescent moon over a teal horizon, drawn live.
//
// Performance: the static sky and sea live on their own canvas, painted once
// per resize and slid for parallax with a GPU transform. The vignette and
// film grain are a static CSS layer. Glows are pre-rendered sprites, the
// aurora renders at quarter resolution, and the moon's phase is only
// re-rendered when it changes. Each frame only draws what moves: stars,
// aurora, moon, reflection, horizon swell and shooting stars.
//
// Pointer position turns the moon's phase and tilts the sky; a click sends a
// shooting star. With reduced motion on, it draws one still frame and only
// redraws when the pointer moves.
(() => {
  const canvas = document.getElementById("sky");
  if (!canvas || !canvas.getContext) return;
  const ctx = canvas.getContext("2d");
  const hero = canvas.closest(".hero");
  const base = document.createElement("canvas");
  base.className = "sky-base";
  base.setAttribute("aria-hidden", "true");
  canvas.before(base);
  const baseCtx = base.getContext("2d");
  const hint = document.querySelector(".sky-hint");
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");

  const MOON = [214, 225, 234];
  const FROST = [115, 163, 153];
  const AURORA = [110, 196, 172];
  const IDLE_PHASE = 0.14;
  const PARALLAX = 28;

  let width = 0;
  let height = 0;
  let scale = 1;
  let geometry = null;
  let textBottom = 0;
  let textBox = null;

  let skyLayer = null;
  let moonTexture = null;
  let moonWork = null;
  let auroraStrip = null;
  let auroraLayer = null;
  let haloSprite = null;
  let poolSprite = null;
  let crescentKey = "";
  let baseShift = NaN;
  let stars = [];
  let meteors = [];

  let running = false;
  let visible = true;
  let lastTime = 0;
  let clock = 0;
  const INTRO_SECONDS = 1.8;
  const introStart = performance.now();
  let intro = reducedMotion.matches ? 1 : 0;
  let nextMeteor = 5;
  let interacted = false;

  const target = { x: 0, y: 0, phase: IDLE_PHASE };
  const now = { x: 0, y: 0, phase: IDLE_PHASE };

  const rgba = (c, a) => `rgba(${c[0]},${c[1]},${c[2]},${a})`;
  const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
  const easeOut = (t) => 1 - Math.pow(1 - t, 3);
  const lit = () => 0.5 + now.phase * 0.5;

  // Deterministic randomness so the sky and the moon look the same each visit.
  function seeded(seed) {
    return () => {
      seed |= 0;
      seed = (seed + 0x6d2b79f5) | 0;
      let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }
  function gaussian(random) {
    let u = 0;
    let v = 0;
    while (u === 0) u = random();
    while (v === 0) v = random();
    return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
  }
  function offscreen(w, h, resolution = scale) {
    const c = document.createElement("canvas");
    c.width = Math.max(1, Math.round(w * resolution));
    c.height = Math.max(1, Math.round(h * resolution));
    const g = c.getContext("2d");
    g.setTransform(resolution, 0, 0, resolution, 0, 0);
    return { canvas: c, ctx: g, w, h };
  }

  // Soft glows never change shape, only brightness, so they are drawn once
  // at half resolution and stamped each frame with globalAlpha.
  function paintGlows() {
    const { radius: r } = geometry;
    const s = r * 8.4;
    const c = s / 2;
    const halo = offscreen(s, s, 0.5);
    const g = halo.ctx;
    const wide = g.createRadialGradient(c, c, r * 0.8, c, c, r * 4.2);
    wide.addColorStop(0, rgba([160, 200, 205], 0.075));
    wide.addColorStop(1, rgba([160, 200, 205], 0));
    g.fillStyle = wide;
    g.fillRect(0, 0, s, s);
    const corona = g.createRadialGradient(c, c, r * 0.95, c, c, r * 1.55);
    corona.addColorStop(0, rgba([225, 235, 242], 0.14));
    corona.addColorStop(1, rgba([225, 235, 242], 0));
    g.fillStyle = corona;
    g.beginPath();
    g.arc(c, c, r * 1.55, 0, Math.PI * 2);
    g.fill();
    haloSprite = halo;

    const pw = r * 4.4;
    const ph = pw * 0.32;
    const pool = offscreen(pw, ph, 0.5);
    const p = pool.ctx;
    p.translate(pw / 2, ph / 2);
    p.scale(1, 0.32);
    const light = p.createRadialGradient(0, 0, 0, 0, 0, r * 2.2);
    light.addColorStop(0, rgba(MOON, 1));
    light.addColorStop(1, rgba(MOON, 0));
    p.fillStyle = light;
    p.fillRect(-r * 2.2, -r * 2.2, r * 4.4, r * 4.4);
    poolSprite = pool;
  }

  // The static sky and sea, on their own canvas. Parallax slides it with a
  // transform, which the GPU composites without repainting anything.
  function paintBase() {
    const { horizon } = geometry;
    const w = width + PARALLAX * 2;
    base.width = Math.round(w * scale);
    base.height = Math.round(height * scale);
    base.style.width = `${w}px`;
    base.style.height = `${height}px`;
    baseCtx.setTransform(scale, 0, 0, scale, 0, 0);
    baseCtx.drawImage(skyLayer.canvas, 0, 0, skyLayer.w, skyLayer.h);
    const sea = baseCtx.createLinearGradient(0, horizon, 0, height);
    sea.addColorStop(0, "#0b161b");
    sea.addColorStop(0.4, "#060b11");
    sea.addColorStop(1, "#03050a");
    baseCtx.fillStyle = sea;
    baseCtx.fillRect(0, horizon, w, height - horizon);
    baseShift = NaN;
  }

  function computeGeometry() {
    const narrow = width < 820;
    const radius = narrow
      ? clamp(width * 0.15, 44, 80)
      : clamp(Math.min(width, height) * 0.15, 60, 150);
    return {
      narrow,
      radius,
      // On phones the moon gets its own band of sky above the text.
      moonX: narrow ? width * 0.68 : width * 0.72,
      moonY: narrow ? 76 + radius : height * 0.36,
      // The water always sits below the hero text, never through it.
      horizon: Math.min(height - 40, Math.max(height * (narrow ? 0.6 : 0.76), textBottom + 36)),
    };
  }

  // --- Static layers ------------------------------------------------------

  function paintSky() {
    const { horizon } = geometry;
    const pad = PARALLAX;
    const layer = offscreen(width + pad * 2, horizon + pad);
    const g = layer.ctx;
    const random = seeded(7);

    const sky = g.createLinearGradient(0, 0, 0, horizon + pad);
    sky.addColorStop(0, "#020309");
    sky.addColorStop(0.5, "#060a14");
    sky.addColorStop(0.85, "#0a141c");
    sky.addColorStop(1, "#102027");
    g.fillStyle = sky;
    g.fillRect(0, 0, layer.w, layer.h);

    // Milky Way: a soft diagonal band of glow and dense faint stars.
    const from = { x: layer.w * 0.02, y: horizon * 0.02 };
    const to = { x: layer.w * 0.98, y: horizon * 0.95 };
    const dx = to.x - from.x;
    const dy = to.y - from.y;
    const length = Math.hypot(dx, dy);
    const nx = -dy / length;
    const ny = dx / length;
    const spread = Math.min(width, height) * 0.11;

    g.globalCompositeOperation = "lighter";
    for (let i = 0; i < 46; i++) {
      const along = random();
      const off = gaussian(random) * spread * 0.6;
      const x = from.x + dx * along + nx * off;
      const y = from.y + dy * along + ny * off;
      const r = spread * (0.8 + random() * 1.4);
      const glow = g.createRadialGradient(x, y, 0, x, y, r);
      const tint = random() < 0.35 ? [120, 170, 165] : [170, 185, 205];
      glow.addColorStop(0, rgba(tint, 0.022));
      glow.addColorStop(1, rgba(tint, 0));
      g.fillStyle = glow;
      g.fillRect(x - r, y - r, r * 2, r * 2);
    }
    const bandStars = Math.round((width * horizon) / 900);
    for (let i = 0; i < bandStars; i++) {
      const along = random();
      const off = gaussian(random) * spread * 0.55;
      const x = from.x + dx * along + nx * off;
      const y = from.y + dy * along + ny * off;
      if (y > horizon - 6) continue;
      g.fillStyle = `rgba(225,232,240,${0.08 + random() * 0.3})`;
      g.fillRect(x, y, random() < 0.9 ? 0.6 : 1, random() < 0.9 ? 0.6 : 1);
    }
    // Dark dust lane through the band.
    g.globalCompositeOperation = "source-over";
    for (let i = 0; i < 22; i++) {
      const along = 0.15 + random() * 0.7;
      const off = gaussian(random) * spread * 0.18;
      const x = from.x + dx * along + nx * off;
      const y = from.y + dy * along + ny * off;
      const r = spread * (0.5 + random() * 0.6);
      const dust = g.createRadialGradient(x, y, 0, x, y, r);
      dust.addColorStop(0, "rgba(2,3,9,0.12)");
      dust.addColorStop(1, "rgba(2,3,9,0)");
      g.fillStyle = dust;
      g.fillRect(x - r, y - r, r * 2, r * 2);
    }
    // Sparse faint stars across the whole sky.
    const dustCount = Math.round((width * horizon) / 2600);
    for (let i = 0; i < dustCount; i++) {
      const x = random() * layer.w;
      const y = random() * (horizon - 6);
      g.fillStyle = `rgba(225,232,240,${0.06 + random() * 0.22})`;
      g.fillRect(x, y, 0.7, 0.7);
    }
    // Low mist on the horizon.
    const mist = g.createLinearGradient(0, horizon - 140, 0, horizon + pad);
    mist.addColorStop(0, rgba(FROST, 0));
    mist.addColorStop(1, rgba(FROST, 0.09));
    g.fillStyle = mist;
    g.fillRect(0, horizon - 140, layer.w, 140 + pad);

    skyLayer = layer;
  }

  function paintMoonTexture() {
    const { radius: r } = geometry;
    const size = r * 2 + 4;
    const layer = offscreen(size, size);
    const g = layer.ctx;
    const c = size / 2;
    const random = seeded(11);

    g.save();
    g.beginPath();
    g.arc(c, c, r, 0, Math.PI * 2);
    g.clip();

    const body = g.createRadialGradient(c + r * 0.3, c + r * 0.28, r * 0.05, c, c, r);
    body.addColorStop(0, "#f6f8fb");
    body.addColorStop(0.55, rgba(MOON, 1));
    body.addColorStop(1, "#a7b6c3");
    g.fillStyle = body;
    g.fillRect(0, 0, size, size);

    // Maria: the soft dark "seas".
    const maria = [
      [-0.28, -0.22, 0.34], [0.12, -0.38, 0.24], [0.32, 0.02, 0.2],
      [-0.02, 0.22, 0.22], [0.36, 0.42, 0.13], [-0.45, 0.2, 0.16],
    ];
    for (const [mx, my, mr] of maria) {
      const x = c + mx * r;
      const y = c + my * r;
      const rr = mr * r;
      const sea = g.createRadialGradient(x, y, 0, x, y, rr);
      sea.addColorStop(0, "rgba(98,114,132,0.30)");
      sea.addColorStop(0.7, "rgba(98,114,132,0.14)");
      sea.addColorStop(1, "rgba(98,114,132,0)");
      g.fillStyle = sea;
      g.fillRect(x - rr, y - rr, rr * 2, rr * 2);
    }
    // Craters: a dark bowl with a lit rim on the sun side.
    for (let i = 0; i < 16; i++) {
      const angle = random() * Math.PI * 2;
      const dist = Math.sqrt(random()) * 0.82 * r;
      const x = c + Math.cos(angle) * dist;
      const y = c + Math.sin(angle) * dist;
      const cr = (0.018 + random() * 0.034) * r;
      g.fillStyle = "rgba(92,108,124,0.07)";
      g.beginPath();
      g.arc(x, y, cr, 0, Math.PI * 2);
      g.fill();
      g.strokeStyle = "rgba(255,255,255,0.08)";
      g.lineWidth = Math.max(0.6, cr * 0.18);
      g.beginPath();
      g.arc(x, y, cr, Math.PI * 0.1, Math.PI * 0.9);
      g.stroke();
    }
    // Fine surface speckle.
    for (let i = 0; i < r * 9; i++) {
      const angle = random() * Math.PI * 2;
      const dist = Math.sqrt(random()) * r;
      g.fillStyle = random() < 0.5 ? "rgba(80,96,112,0.07)" : "rgba(255,255,255,0.06)";
      g.fillRect(c + Math.cos(angle) * dist, c + Math.sin(angle) * dist, 1, 1);
    }
    // Limb darkening.
    const limb = g.createRadialGradient(c, c, r * 0.72, c, c, r);
    limb.addColorStop(0, "rgba(30,44,58,0)");
    limb.addColorStop(1, "rgba(30,44,58,0.38)");
    g.fillStyle = limb;
    g.fillRect(0, 0, size, size);
    g.restore();

    moonTexture = layer;
    moonWork = offscreen(size, size);
  }

  function paintAuroraStrip() {
    const layer = offscreen(1, 256);
    const g = layer.ctx;
    const curtain = g.createLinearGradient(0, 0, 0, 256);
    curtain.addColorStop(0, rgba(AURORA, 0));
    curtain.addColorStop(0.45, rgba(AURORA, 0.35));
    curtain.addColorStop(0.78, rgba(AURORA, 1));
    curtain.addColorStop(1, rgba(AURORA, 0));
    g.fillStyle = curtain;
    g.fillRect(0, 0, 1, 256);
    auroraStrip = layer;
  }

  function resize() {
    const rect = hero.getBoundingClientRect();
    scale = Math.min(window.devicePixelRatio || 1, 2);
    width = Math.max(1, Math.round(rect.width));
    height = Math.max(1, Math.round(rect.height));
    canvas.width = Math.round(width * scale);
    canvas.height = Math.round(height * scale);
    canvas.style.width = `${width}px`;
    canvas.style.height = `${height}px`;
    ctx.setTransform(scale, 0, 0, scale, 0, 0);

    const lastText = hero.querySelector(".hero-meta");
    textBottom = lastText ? lastText.getBoundingClientRect().bottom - rect.top : 0;
    const inner = hero.querySelector(".hero-inner");
    const parts = inner ? [...inner.children].map((child) => child.getBoundingClientRect()) : [];
    textBox = parts.length ? {
      left: Math.min(...parts.map((p) => p.left)) - rect.left - 24,
      right: Math.max(...parts.map((p) => p.right)) - rect.left + 24,
      top: Math.min(...parts.map((p) => p.top)) - rect.top - 24,
      bottom: textBottom + 24,
    } : null;

    geometry = computeGeometry();
    paintSky();
    paintBase();
    paintMoonTexture();
    paintGlows();
    crescentKey = "";
    if (!auroraStrip) paintAuroraStrip();
    auroraLayer = offscreen(width + 40, height * 0.5 + 140, 0.25);

    const random = seeded(23);
    const count = Math.min(170, Math.round((width * geometry.horizon) / 7000));
    stars = Array.from({ length: count }, () => {
      const depth = random() ** 1.6;
      return {
        x: random() * width,
        y: random() * (geometry.horizon - 10),
        r: 0.45 + depth * 1.15,
        depth,
        alpha: 0.35 + depth * 0.6,
        speed: 0.5 + random() * 1.8,
        offset: random() * Math.PI * 2,
        tint: random() < 0.1 ? [170, 220, 210] : random() < 0.08 ? [240, 222, 190] : [238, 242, 247],
        spike: depth > 0.82,
      };
    });

    draw();
  }

  // --- Per-frame drawing --------------------------------------------------

  function drawStars(horizon) {
    const fadeIn = clamp(intro * 1.6, 0, 1);
    for (const star of stars) {
      const twinkle = reducedMotion.matches ? 1 : 0.62 + 0.38 * Math.sin(clock * star.speed + star.offset);
      const x = star.x - now.x * PARALLAX * star.depth;
      const y = star.y - now.y * 12 * star.depth;
      if (y > horizon - 6) continue;
      const behindText = textBox && x > textBox.left && x < textBox.right && y > textBox.top && y < textBox.bottom;
      const alpha = star.alpha * twinkle * fadeIn * (behindText ? 0.16 : 1);
      ctx.fillStyle = rgba(star.tint, alpha);
      ctx.beginPath();
      ctx.arc(x, y, star.r, 0, Math.PI * 2);
      ctx.fill();
      if (star.spike && !behindText) {
        // A faint four-point glint on the brightest stars.
        const len = star.r * 5 * twinkle;
        ctx.strokeStyle = rgba(star.tint, alpha * 0.35);
        ctx.lineWidth = 0.6;
        ctx.beginPath();
        ctx.moveTo(x - len, y); ctx.lineTo(x + len, y);
        ctx.moveTo(x, y - len); ctx.lineTo(x, y + len);
        ctx.stroke();
      }
    }
  }

  function drawAurora(horizon) {
    const t = reducedMotion.matches ? 0 : clock;
    const step = 8;
    const top = horizon - height * 0.5;
    // Rendered small, then stretched once: it is soft light, so the lower
    // resolution is invisible and the column loop touches 1/16 the pixels.
    const layer = auroraLayer;
    const layerTop = top - 70;
    const g = layer.ctx;
    g.clearRect(0, 0, layer.w, layer.h);
    for (let x = -step; x < width + step; x += step) {
      const wave =
        Math.sin(x * 0.0042 + t * 0.12) * 0.55 +
        Math.sin(x * 0.0113 - t * 0.21 + 1.3) * 0.3 +
        Math.sin(x * 0.027 + t * 0.4) * 0.15;
      const strength = clamp(wave * 0.9 + 0.15, 0, 1);
      if (strength <= 0.01) continue;
      const lift = Math.sin(x * 0.006 + t * 0.18) * 46 + Math.sin(x * 0.015 - t * 0.27) * 18;
      const y = top + lift;
      const h = (horizon - y) * 0.92;
      g.globalAlpha = strength * 0.075 * intro;
      g.drawImage(auroraStrip.canvas, x + 20, y - layerTop, step, h);
    }
    g.globalAlpha = 1;
    ctx.save();
    ctx.globalCompositeOperation = "lighter";
    ctx.drawImage(layer.canvas, -20 - now.x * 10, layerTop, layer.w, layer.h);
    ctx.restore();
  }

  function renderCrescent() {
    const { radius: r } = geometry;
    const size = moonWork.w;
    const c = size / 2;
    const g = moonWork.ctx;
    // Shadow disc with a feathered edge for a soft terminator.
    const angle = -2.25 + now.x * 0.35;
    const shift = r * (0.32 + now.phase * 1.55);
    const key = `${angle.toFixed(3)}|${shift.toFixed(2)}`;
    if (key === crescentKey) return;
    crescentKey = key;
    g.save();
    g.setTransform(scale, 0, 0, scale, 0, 0);
    g.clearRect(0, 0, size, size);
    g.globalCompositeOperation = "source-over";
    g.drawImage(moonTexture.canvas, 0, 0, size, size);

    const sx = c + Math.cos(angle) * shift;
    const sy = c + Math.sin(angle) * shift;
    const sr = r * 1.03;
    const feather = r * 0.07;
    const shadow = g.createRadialGradient(sx, sy, 0, sx, sy, sr);
    shadow.addColorStop(0, "rgba(0,0,0,1)");
    shadow.addColorStop(clamp(1 - feather / sr, 0, 1), "rgba(0,0,0,1)");
    shadow.addColorStop(1, "rgba(0,0,0,0)");
    g.globalCompositeOperation = "destination-out";
    g.fillStyle = shadow;
    g.beginPath();
    g.arc(sx, sy, sr, 0, Math.PI * 2);
    g.fill();
    g.restore();
  }

  function drawMoon(moonX, moonY, fade) {
    const { radius: r } = geometry;
    if (fade <= 0) return;
    const size = moonWork.w;
    const glow = 0.35 + now.phase * 0.65;
    ctx.save();
    ctx.globalAlpha = fade;

    // Two-layer halo (wide glow and tight corona), pre-rendered.
    const halo = haloSprite.w;
    ctx.globalAlpha = fade * glow;
    ctx.drawImage(haloSprite.canvas, moonX - halo / 2, moonY - halo / 2, halo, halo);
    ctx.globalAlpha = fade;

    // Earthshine: the dark side stays faintly visible, surface and all.
    ctx.fillStyle = "rgba(20,28,40,0.94)";
    ctx.beginPath();
    ctx.arc(moonX, moonY, r, 0, Math.PI * 2);
    ctx.fill();
    ctx.globalAlpha = fade * 0.09;
    ctx.drawImage(moonTexture.canvas, moonX - size / 2, moonY - size / 2, size, size);
    ctx.globalAlpha = fade;

    ctx.drawImage(moonWork.canvas, moonX - size / 2, moonY - size / 2, size, size);
    ctx.restore();
  }

  function drawWater(horizon, moonX, moonY, fade) {
    const t = reducedMotion.matches ? 0 : clock;
    const { radius: r } = geometry;

    if (fade > 0) {
      // Mirrored moon, squashed and broken into rippling slices.
      const size = moonWork.w;
      const squash = 0.55;
      const mirrorY = horizon + (horizon - moonY) * 0.28;
      const top = Math.max(horizon + 2, mirrorY - r * squash);
      const bottom = Math.min(height, mirrorY + r * squash);
      ctx.save();
      for (let y = top; y < bottom; y += 2) {
        const sourceY = (mirrorY - y) / squash + r + 2;
        if (sourceY < 0 || sourceY > size - 2) continue;
        const depth = (y - horizon) / (height - horizon);
        const wobble = Math.sin(y * 0.19 + t * 2.4) * r * 0.07 + Math.sin(y * 0.07 - t * 1.4) * r * 0.05;
        ctx.globalAlpha = fade * 0.62 * (1 - depth * 0.8) * (0.72 + 0.28 * Math.sin(y * 0.5 + t * 3));
        ctx.drawImage(
          moonWork.canvas,
          0, sourceY * scale, moonWork.canvas.width, 2 * scale,
          moonX - size / 2 + wobble, y, size, 2
        );
      }
      ctx.restore();

      // A soft pool of moonlight on the water under the moon.
      const poolY = horizon + (height - horizon) * 0.32;
      ctx.save();
      ctx.globalAlpha = 0.07 * fade * lit();
      ctx.drawImage(poolSprite.canvas, moonX - poolSprite.w / 2, poolY - poolSprite.h / 2, poolSprite.w, poolSprite.h);
      ctx.restore();

      // Glitter path down to the shore.
      ctx.save();
      ctx.globalCompositeOperation = "lighter";
      const rows = Math.floor((height - horizon) / 4);
      for (let i = 1; i < rows; i++) {
        const y = horizon + i * 4;
        const progress = i / rows;
        const shimmer = Math.sin(t * 1.7 + i * 1.3) * 0.5 + 0.5;
        const span = r * (0.35 + progress * 0.9) * (0.3 + shimmer * 0.7);
        const drift = Math.sin(t * 0.9 + i * 0.41) * r * 0.18;
        ctx.strokeStyle = rgba(MOON, (0.26 - progress * 0.2) * fade * lit());
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.moveTo(moonX - span / 2 + drift, y);
        ctx.lineTo(moonX + span / 2 + drift, y);
        ctx.stroke();
      }
      ctx.restore();
    }

    // The icon's teal horizon band, then fainter swells beneath it.
    const bands = [
      { offset: 0, amplitude: 2.6, alpha: 0.8, line: 1.6 },
      { offset: 12, amplitude: 2.2, alpha: 0.2, line: 1 },
      { offset: 30, amplitude: 1.8, alpha: 0.11, line: 1 },
      { offset: 56, amplitude: 1.5, alpha: 0.06, line: 1 },
      { offset: 92, amplitude: 1.2, alpha: 0.035, line: 1 },
    ];
    bands.forEach((band, index) => {
      const base = horizon + band.offset;
      if (base > height) return;
      const step = 6;
      ctx.beginPath();
      for (let x = -step; x <= width + step; x += step) {
        const f = 0.006 + index * 0.0016;
        const y = base
          + Math.sin(x * f + t * (0.5 + index * 0.1) + index * 1.7) * band.amplitude
          + Math.sin(x * f * 2.3 - t * 0.38) * band.amplitude * 0.4;
        if (x === -step) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
      }
      if (index === 0) {
        ctx.strokeStyle = rgba(FROST, 0.1 * intro);
        ctx.lineWidth = 12;
        ctx.stroke();
        ctx.strokeStyle = rgba(FROST, 0.18 * intro);
        ctx.lineWidth = 4;
        ctx.stroke();
      }
      ctx.strokeStyle = rgba(FROST, band.alpha * intro);
      ctx.lineWidth = band.line;
      ctx.stroke();
    });
  }

  function drawMeteors(delta, horizon) {
    meteors = meteors.filter((m) => m.life < m.maxLife && m.y < horizon);
    for (const m of meteors) {
      m.life += delta;
      m.x += m.vx * delta;
      m.y += m.vy * delta;
      const fade = Math.sin(Math.PI * Math.min(1, m.life / m.maxLife));
      const tailX = m.x - m.vx * 0.14;
      const tailY = m.y - m.vy * 0.14;
      const trail = ctx.createLinearGradient(m.x, m.y, tailX, tailY);
      trail.addColorStop(0, `rgba(244,248,252,${0.95 * fade})`);
      trail.addColorStop(0.3, `rgba(190,225,218,${0.35 * fade})`);
      trail.addColorStop(1, "rgba(190,225,218,0)");
      ctx.strokeStyle = trail;
      ctx.lineWidth = 1.4;
      ctx.lineCap = "round";
      ctx.beginPath();
      ctx.moveTo(m.x, m.y);
      ctx.lineTo(tailX, tailY);
      ctx.stroke();
      ctx.fillStyle = `rgba(255,255,255,${0.9 * fade})`;
      ctx.beginPath();
      ctx.arc(m.x, m.y, 1.3, 0, Math.PI * 2);
      ctx.fill();
    }
  }

  function draw(delta = 0) {
    if (!geometry) return;
    if (!reducedMotion.matches) {
      intro = Math.min(1, (performance.now() - introStart) / 1000 / INTRO_SECONDS);
    }
    const { radius: r, moonX: baseX, moonY: baseY, horizon } = geometry;
    const scrolled = Math.max(0, window.scrollY);
    const rise = (1 - easeOut(clamp(intro, 0, 1))) * r * 0.5;
    const moonX = baseX + now.x * 16;
    const moonY = baseY + now.y * 10 + scrolled * 0.35 + rise;
    const fade = clamp((horizon - (moonY + r * 0.4)) / (r * 1.2), 0, 1) * clamp(intro * 1.3, 0, 1);

    const shift = Math.round((-PARALLAX - now.x * PARALLAX * 0.35) * 4) / 4;
    if (shift !== baseShift) {
      baseShift = shift;
      base.style.transform = `translate3d(${shift}px, 0, 0)`;
    }
    ctx.clearRect(0, 0, width, height);
    drawAurora(horizon);
    drawStars(horizon);
    drawMeteors(delta, horizon);
    renderCrescent();
    drawMoon(moonX, moonY, fade);
    drawWater(horizon, moonX, moonY, fade);
  }

  function launchMeteor(x, y) {
    const direction = x > width / 2 ? -1 : 1;
    const speed = 560 + Math.random() * 260;
    const angle = 0.36 + Math.random() * 0.26;
    meteors.push({
      x, y,
      vx: Math.cos(angle) * speed * direction,
      vy: Math.sin(angle) * speed,
      life: 0,
      maxLife: 0.7 + Math.random() * 0.45,
    });
  }

  function frame(ms) {
    if (!running) return;
    const time = ms / 1000;
    const delta = lastTime ? Math.min(0.05, time - lastTime) : 0;
    lastTime = time;
    clock += delta;

    const ease = 1 - Math.pow(0.002, delta);
    now.x += (target.x - now.x) * ease;
    now.y += (target.y - now.y) * ease;
    now.phase += (target.phase - now.phase) * ease;

    nextMeteor -= delta;
    if (nextMeteor <= 0 && geometry) {
      launchMeteor((0.1 + Math.random() * 0.8) * width, (0.05 + Math.random() * 0.3) * geometry.horizon);
      nextMeteor = 7 + Math.random() * 7;
    }

    draw(delta);
    requestAnimationFrame(frame);
  }

  function start() {
    if (running || reducedMotion.matches || !visible || document.hidden) return;
    running = true;
    lastTime = 0;
    requestAnimationFrame(frame);
  }

  function stop() {
    running = false;
  }

  function stillFrame() {
    intro = 1;
    now.x = target.x;
    now.y = target.y;
    now.phase = target.phase;
    draw();
  }

  function pointAt(clientX, clientY) {
    const rect = hero.getBoundingClientRect();
    const x = (clientX - rect.left) / rect.width;
    const y = (clientY - rect.top) / rect.height;
    if (y < 0 || y > 1) return;
    target.x = (x - 0.5) * 2;
    target.y = (y - 0.5) * 2;
    target.phase = clamp(x * 1.15 - 0.1, 0, 1);
    if (!interacted && hint) {
      interacted = true;
      hint.classList.add("is-done");
    }
    if (reducedMotion.matches) stillFrame();
  }

  window.addEventListener("pointermove", (event) => pointAt(event.clientX, event.clientY), { passive: true });
  hero.addEventListener("click", (event) => {
    if (event.target.closest("a, button") || reducedMotion.matches || !geometry) return;
    const rect = hero.getBoundingClientRect();
    const x = event.clientX - rect.left;
    const y = event.clientY - rect.top;
    if (y < geometry.horizon) launchMeteor(x, y);
  });
  hero.addEventListener("pointerleave", () => {
    target.x = 0;
    target.y = 0;
    target.phase = IDLE_PHASE;
    if (reducedMotion.matches) stillFrame();
  });

  window.addEventListener("scroll", () => {
    if (!running) draw();
  }, { passive: true });
  new ResizeObserver(() => resize()).observe(hero);
  if (document.fonts) document.fonts.ready.then(resize);
  document.addEventListener("visibilitychange", () => (document.hidden ? stop() : start()));
  reducedMotion.addEventListener("change", () => {
    if (reducedMotion.matches) {
      stop();
      stillFrame();
    } else {
      start();
    }
  });

  new IntersectionObserver(([entry]) => {
    visible = entry.isIntersecting;
    if (visible) start();
    else stop();
  }).observe(hero);

  // Film grain: a small noise tile, generated once and laid over the sky.
  const grain = hero.querySelector(".grain");
  if (grain) {
    const tile = document.createElement("canvas");
    tile.width = tile.height = 160;
    const g = tile.getContext("2d");
    const image = g.createImageData(160, 160);
    const random = seeded(31);
    // Light and dark specks with their own alpha, so the layer blends
    // normally; a blend mode here would force a full re-blend every frame.
    for (let i = 0; i < image.data.length; i += 4) {
      const v = random() * 2 - 1;
      const c = v > 0 ? 255 : 0;
      image.data[i] = image.data[i + 1] = image.data[i + 2] = c;
      image.data[i + 3] = Math.round(Math.abs(v) * 9);
    }
    g.putImageData(image, 0, 0);
    grain.style.setProperty("--noise", `url(${tile.toDataURL()})`);
  }

  resize();
  if (reducedMotion.matches) stillFrame();
  start();
  // If frames are throttled, still paint the settled sky once the entrance ends.
  setTimeout(() => { if (!running) draw(); }, INTRO_SECONDS * 1000 + 50);
})();
