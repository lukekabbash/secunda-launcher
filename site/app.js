// Page behaviour: the game catalog and its filters, the how-it-works
// stepper, copy buttons, the sticky nav, and download links that follow
// release.json (written by scripts/release-local.sh).

// The catalog mirrors app/Model/GameDescriptor.swift and ClassicGameCatalog.swift.
const GAMES = [
  { title: "Skyrim Special Edition", status: "played", api: "DirectX 11",
    note: "Played through menus, dialogue, saving and loading. Spoken dialogue is set up for you, and included DLC is detected." },
  { title: "Fallout 4", status: "played", api: "DirectX 11",
    note: "Starts from the game's own Medium preset, sized to your screen. The add-ons you own are detected automatically." },
  { title: "Supreme Commander 2", status: "played", api: "DirectX 9",
    note: "Opens borderless at your screen's full size, using the windowed setup this engine needs to start reliably." },
  { title: "Insurgency", status: "played", api: "DirectX 9",
    note: "Starts through Steam and is playable, though it runs a bit laggy. Performance tuning for it is still to come." },
  { title: "Enderal: Forgotten Stories", status: "experimental", api: "DirectX 11",
    note: "Uses Skyrim's engine and the same display fixes. Needs Skyrim Special Edition on the same Steam account." },
  { title: "Fallout: New Vegas", status: "experimental", api: "DirectX 9",
    note: "Has its own launch profile and is ready to try. A report on GitHub helps it move up to Played." },
  { title: "Portal 2", status: "experimental", api: "DirectX 9",
    note: "Writes the game's video settings for your screen before launch, so it opens at the right size." },
  { title: "Half-Life 2", status: "experimental", api: "DirectX 9",
    note: "Gets the same Source engine setup as Portal 2: video settings written for your screen before launch." },
  { title: "Supreme Commander", status: "experimental", api: "DirectX 9",
    note: "Opens borderless at your screen's exact size for a sharp picture, with an audio buffer option for crackle." },
  { title: "Supreme Commander: Forged Alliance", status: "experimental", api: "DirectX 9",
    note: "Same setup as Supreme Commander: an exact-size borderless window and an optional audio buffer for crackle." },
  { title: "STAR WARS Battlefront II (2005)", status: "experimental", api: "DirectX 9",
    note: "The 2005 classic with its own display profile. Ready to try; reports on GitHub help it move up." },
  { title: "Angels Fall First", status: "experimental", api: "DirectX 9",
    note: "Runs through DXVK and Vulkan instead of the default DirectX 9 path, set per game by its profile." },
  { title: "Call of Duty: Black Ops II", status: "partial", api: "DirectX 11",
    note: "The campaign closes early on this setup. Multiplayer and Zombies haven't been tested end to end yet." },
];

const STATUS_LABEL = { played: "Played", experimental: "Experimental", partial: "Partial" };

const STEPS = [
  {
    title: "Secunda",
    body: "The app you open. It's a native Apple-silicon app that keeps your Windows space, Steam and each game's settings in one place, and watches each launch until the game is running.",
    detail: "Written in Swift. Before Play, it writes display and quality settings for that game, then hands the launch to Steam.",
  },
  {
    title: "Wine 11",
    body: "Wine lets Windows programs run on macOS by answering their Windows system calls with Mac ones. It isn't an emulator and there's no copy of Windows involved.",
    detail: "Secunda builds Wine 11.0 itself from CodeWeavers' published source, with its own patches. The Windows side runs through Apple's Rosetta 2 and handles both 32-bit and 64-bit games.",
  },
  {
    title: "Graphics",
    body: "Games speak DirectX. Macs speak Metal. A translation layer turns one into the other as the game draws each frame.",
    detail: "DirectX 10 and 11 games use DXMT, which goes straight to Metal. DirectX 9 games use Wine's built-in path, or DXVK plus MoltenVK when a game runs better that way.",
  },
  {
    title: "Steam",
    body: "The real Windows Steam client, downloaded from Valve, runs inside your private Windows space. It handles sign-in, ownership, downloads and game updates as usual.",
    detail: "Secunda never sees your password and never ships Steam or game files. Everything lives in one folder in your Library.",
  },
  {
    title: "Your game",
    body: "Steam starts the game, and Secunda watches it start, so a game that fails shows an error instead of quietly vanishing. Sound comes out of your Mac's speakers or headphones, and your keyboard and mouse work as usual.",
    detail: "When you're done, Stop closes the game and Steam cleanly. Your saves stay where the game put them, and Secunda can back them up.",
  },
];

const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];

function gameCard(game, index) {
  const item = document.createElement("li");
  item.className = `game ${game.status}`;
  item.style.animationDelay = `${Math.min(index, 8) * 40}ms`;

  // Designed cover in the icon's style; publisher artwork is not used.
  const art = document.createElement("div");
  art.className = "game-art";
  art.setAttribute("aria-hidden", "true");
  const moon = document.createElement("span");
  moon.className = "game-moon";
  const glint = document.createElement("span");
  glint.className = "game-glint";
  art.append(moon, glint);

  const body = document.createElement("div");
  body.className = "game-body";
  const title = document.createElement("h3");
  title.textContent = game.title;
  const note = document.createElement("p");
  note.textContent = game.note;

  const foot = document.createElement("div");
  foot.className = "game-foot";
  const status = document.createElement("span");
  status.className = `status ${game.status}`;
  status.textContent = STATUS_LABEL[game.status];
  const api = document.createElement("span");
  api.className = "game-api";
  api.textContent = game.api;
  foot.append(status, api);

  body.append(title, note, foot);
  item.append(art, body);
  return item;
}

function initGames() {
  const grid = $("#game-grid");
  if (!grid) return;
  // The "won't run yet" note moves into the grid as its last tile.
  const callout = $(".callout");
  // When the cards fill their last row exactly, it shows below the grid as
  // a compact strip instead, so it never becomes a tall empty row.
  let more = null;
  let strip = null;
  if (callout) {
    more = document.createElement("li");
    more.className = "game-more";
    const [text, link] = callout.children;
    more.append(...text.children, link);
    strip = document.createElement("div");
    strip.className = "game-more is-strip";
    strip.innerHTML = more.innerHTML;
    strip.hidden = true;
    callout.replaceWith(strip);
    grid.after(strip);
  }
  let cards = [];
  const fitMore = () => {
    if (!more) return;
    const columns = getComputedStyle(grid).gridTemplateColumns.split(" ").length;
    const left = columns - (cards.length % columns);
    const full = left === columns;
    more.style.setProperty("--span", String(left));
    if (full === more.isConnected) grid.replaceChildren(...cards, ...(full ? [] : [more]));
    strip.hidden = !full;
  };
  const render = (filter) => {
    cards = GAMES.filter((game) => filter === "all" || game.status === filter).map(gameCard);
    grid.replaceChildren(...cards, more);
    fitMore();
  };
  new ResizeObserver(fitMore).observe(grid);
  for (const counter of $$("[data-count]")) {
    const kind = counter.dataset.count;
    counter.textContent = kind === "all" ? GAMES.length : GAMES.filter((g) => g.status === kind).length;
  }
  for (const chip of $$(".chip")) {
    chip.addEventListener("click", () => {
      for (const other of $$(".chip")) other.setAttribute("aria-pressed", String(other === chip));
      render(chip.dataset.filter);
    });
  }
  render("all");
}

function initPipeline() {
  const tabs = $$(".pipeline-steps [role=tab]");
  const panel = $("#step-panel");
  if (!tabs.length || !panel) return;
  const show = (index, focus = false) => {
    const step = STEPS[index];
    tabs.forEach((tab, i) => {
      tab.setAttribute("aria-selected", String(i === index));
      tab.tabIndex = i === index ? 0 : -1;
    });
    panel.setAttribute("aria-labelledby", tabs[index].id);
    $("[data-step-title]", panel).textContent = step.title;
    $("[data-step-body]", panel).textContent = step.body;
    $("[data-step-detail]", panel).textContent = step.detail;
    panel.classList.remove("is-changing");
    void panel.offsetWidth;
    panel.classList.add("is-changing");
    if (focus) tabs[index].focus();
  };
  tabs.forEach((tab, index) => {
    tab.addEventListener("click", () => show(index));
    tab.addEventListener("keydown", (event) => {
      const moves = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 };
      if (event.key in moves) {
        event.preventDefault();
        show((index + moves[event.key] + tabs.length) % tabs.length, true);
      } else if (event.key === "Home") {
        event.preventDefault();
        show(0, true);
      } else if (event.key === "End") {
        event.preventDefault();
        show(tabs.length - 1, true);
      }
    });
  });
  show(0);
}

function initCopy() {
  for (const button of $$("[data-copy]")) {
    button.addEventListener("click", async () => {
      const source = document.getElementById(button.dataset.copy);
      try {
        await navigator.clipboard.writeText(source.textContent);
        button.textContent = "Copied";
      } catch {
        const range = document.createRange();
        range.selectNodeContents(source);
        const selection = window.getSelection();
        selection.removeAllRanges();
        selection.addRange(range);
        button.textContent = "Press ⌘C";
      }
      clearTimeout(button.resetTimer);
      button.resetTimer = setTimeout(() => (button.textContent = "Copy"), 2400);
    });
  }
}

function initNav() {
  const nav = $("#nav");
  if (!nav) return;
  const update = () => nav.classList.toggle("is-scrolled", window.scrollY > 24);
  update();
  window.addEventListener("scroll", update, { passive: true });
}

function initReveal() {
  const targets = $$(".section-head, .pipeline, .first-run, .features, .oss-grid, .promises, .faq, .final-cta");
  if (!("IntersectionObserver" in window)) return;
  const observer = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      entry.target.classList.add("is-in");
      observer.unobserve(entry.target);
    }
  }, { rootMargin: "0px 0px -8% 0px" });
  for (const target of targets) {
    target.classList.add("reveal");
    observer.observe(target);
  }
}

async function initRelease() {
  try {
    const response = await fetch("release.json", { cache: "no-store" });
    if (!response.ok) return;
    const release = await response.json();
    if (release.testOnly || typeof release.downloadURL !== "string") return;
    const url = new URL(release.downloadURL);
    if (url.protocol !== "https:") return;

    for (const link of $$("[data-download]")) {
      link.href = url.href;
      const label = $("[data-download-label]", link);
      if (label) label.textContent = `Download Secunda ${release.version}`;
      else if (link.classList.contains("button")) link.textContent = `Download Secunda ${release.version}`;
    }
    const megabytes = Math.round(release.sizeBytes / 1_000_000);
    const date = new Date(release.published).toLocaleDateString(undefined, {
      year: "numeric", month: "long", day: "numeric",
    });
    for (const meta of $$("[data-download-meta]")) {
      meta.textContent = `Version ${release.version} · ${megabytes} MB · ${date} · Apple silicon · macOS ${release.minimumSystemVersion} or newer · Free`;
    }
    const points = $("[data-download-points]");
    if (points) {
      const item = document.createElement("li");
      item.textContent = `Version ${release.version}, ${megabytes} MB`;
      points.prepend(item);
    }
    for (const promise of $$("[data-signed-release]")) promise.hidden = false;
    const checksum = $("[data-checksum]");
    if (checksum && /^[0-9a-f]{64}$/.test(release.sha256)) {
      checksum.textContent = `SHA-256 of the download: ${release.sha256}`;
      checksum.hidden = false;
    }
  } catch {
    // Keep the GitHub Releases fallback links.
  }
}

function initFaq() {
  const reduce = matchMedia("(prefers-reduced-motion: reduce)");
  const easing = "cubic-bezier(0.2, 0.7, 0.2, 1)";
  for (const details of $$(".faq details")) {
    const summary = $("summary", details);
    const body = $(".faq-body", details);
    if (!summary || !body) continue;
    let running = null;

    const finish = () => {
      running = null;
      details.style.height = "";
      details.style.overflow = "";
      details.classList.remove("is-closing");
    };

    summary.addEventListener("click", (event) => {
      if (reduce.matches || !details.animate) return;
      event.preventDefault();
      const from = details.offsetHeight;
      // Stop whatever is running first. Cancel events arrive later, so each
      // handler checks it still owns `running` before touching it.
      if (running) running.cancel();
      for (const fade of body.getAnimations()) fade.cancel();
      details.style.overflow = "hidden";
      const border = details.offsetHeight - details.clientHeight;
      const opening = !details.open || details.classList.contains("is-closing");

      let animation;
      if (opening) {
        details.classList.remove("is-closing");
        details.open = true;
        const to = details.scrollHeight + border;
        animation = details.animate({ height: [`${from}px`, `${to}px`] }, { duration: 340, easing });
        body.animate(
          { opacity: [0, 1], transform: ["translateY(-6px)", "none"] },
          { duration: 340, easing }
        );
        animation.onfinish = () => { if (running === animation) finish(); };
      } else {
        details.classList.add("is-closing");
        const to = summary.offsetHeight + border;
        animation = details.animate({ height: [`${from}px`, `${to}px`] }, { duration: 280, easing });
        body.animate({ opacity: [1, 0] }, { duration: 200, easing, fill: "forwards" });
        animation.onfinish = () => {
          if (running !== animation) return;
          details.open = false;
          for (const fade of body.getAnimations()) fade.cancel();
          finish();
        };
      }
      animation.oncancel = () => { if (running === animation) running = null; };
      running = animation;
    });
  }
}

initGames();
initFaq();
initPipeline();
initCopy();
initNav();
initReveal();
initRelease();
initScrollRail();
initHint();
initStepFade();

// A floating page scrollbar for mouse and trackpad users. The native one
// reserves a gutter the hero sky can't draw into; this rail takes no space,
// shows while scrolling or hovering, and can be dragged or clicked.
function initScrollRail() {
  if (!window.matchMedia("(pointer: fine)").matches) return;
  const root = document.documentElement;
  const rail = document.createElement("div");
  rail.className = "scroll-rail";
  rail.setAttribute("aria-hidden", "true");
  const thumb = document.createElement("div");
  thumb.className = "scroll-thumb";
  rail.append(thumb);
  document.body.append(rail);
  root.classList.add("has-rail");
  // Safari keeps the old scrollbar gutter until the root lays out again.
  root.style.overflow = "hidden";
  void root.offsetWidth;
  root.style.overflow = "";

  let thumbHeight = 0;
  let travel = 0;
  let hideTimer = 0;

  const layout = () => {
    const view = window.innerHeight;
    const total = root.scrollHeight;
    const scrollable = total - view;
    rail.hidden = scrollable <= 1;
    if (rail.hidden) return;
    thumbHeight = Math.max(36, Math.round((view / total) * view));
    travel = view - thumbHeight - 8;
    thumb.style.height = `${thumbHeight}px`;
    const y = 4 + (window.scrollY / scrollable) * travel;
    thumb.style.transform = `translateY(${y}px)`;
  };
  const reveal = () => {
    rail.classList.add("is-visible");
    clearTimeout(hideTimer);
    hideTimer = setTimeout(() => rail.classList.remove("is-visible"), 900);
  };

  window.addEventListener("scroll", () => { layout(); reveal(); }, { passive: true });
  window.addEventListener("resize", layout);
  new ResizeObserver(layout).observe(document.body);

  const scrollToPointer = (clientY, offset) => {
    const scrollable = root.scrollHeight - window.innerHeight;
    const ratio = Math.min(1, Math.max(0, (clientY - 4 - offset) / travel));
    window.scrollTo({ top: ratio * scrollable, behavior: "instant" });
  };
  rail.addEventListener("pointerdown", (event) => {
    event.preventDefault();
    const box = thumb.getBoundingClientRect();
    const onThumb = event.clientY >= box.top && event.clientY <= box.bottom;
    const offset = onThumb ? event.clientY - box.top : thumbHeight / 2;
    if (!onThumb) scrollToPointer(event.clientY, offset);
    try { rail.setPointerCapture(event.pointerId); } catch { /* synthetic or already-released pointer */ }
    rail.classList.add("is-dragging");
    const move = (e) => scrollToPointer(e.clientY, offset);
    const end = () => {
      rail.classList.remove("is-dragging");
      rail.removeEventListener("pointermove", move);
      rail.removeEventListener("pointerup", end);
      rail.removeEventListener("pointercancel", end);
      reveal();
    };
    rail.addEventListener("pointermove", move);
    rail.addEventListener("pointerup", end);
    rail.addEventListener("pointercancel", end);
  });

  layout();
}

// The "move across the sky" hint belongs to the hero; hide it once the page
// scrolls so it never sits under the nav.
function initHint() {
  const hint = $(".sky-hint");
  if (!hint) return;
  const update = () => hint.classList.toggle("is-scrolled", window.scrollY > 24);
  window.addEventListener("scroll", update, { passive: true });
  update();
}

// On narrow screens the how-it-works steps scroll sideways; drop the edge
// fade once the last step is in view, and keep the chosen step visible.
function initStepFade() {
  const list = $(".pipeline-steps");
  if (!list) return;
  const update = () => list.classList.toggle(
    "is-end", list.scrollLeft + list.clientWidth >= list.scrollWidth - 2
  );
  list.addEventListener("scroll", update, { passive: true });
  window.addEventListener("resize", update);
  for (const tab of $$("[role=tab]", list)) {
    tab.addEventListener("click", () => tab.scrollIntoView({ block: "nearest", inline: "nearest", behavior: "smooth" }));
  }
  update();
}
