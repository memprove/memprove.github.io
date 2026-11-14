// Homepage behaviour. Everything works without it: the HTML shows each figure's
// still frame. With prefers-reduced-motion nothing moves either.
type Frame = {
  head: string;
  stale: boolean;
  count: string;
  on: number;
  facts: { sym: string; cls: string; word: string; meta: string }[];
};

const reduce = () => window.matchMedia('(prefers-reduced-motion: reduce)').matches;
const $ = <T extends Element = HTMLElement>(sel: string, root: ParentNode = document) => root.querySelector<T>(sel);
const $$ = <T extends Element = HTMLElement>(sel: string, root: ParentNode = document) => Array.from(root.querySelectorAll<T>(sel));

/** Calls `start` while the element is on screen and `stop` when it leaves. */
function whileVisible(el: Element, start: () => void, stop: () => void) {
  new IntersectionObserver(
    (entries) => {
      for (const e of entries) (e.isIntersecting ? start : stop)();
    },
    { threshold: 0.25 },
  ).observe(el);
}

function tabs() {
  const list = $('[role="tablist"]');
  if (!list) return;
  const all = $$<HTMLButtonElement>('[role="tab"]', list);
  const select = (tab: HTMLButtonElement, focus = false) => {
    for (const t of all) {
      const on = t === tab;
      t.setAttribute('aria-selected', String(on));
      t.tabIndex = on ? 0 : -1;
      const pane = document.getElementById(t.getAttribute('aria-controls') ?? '');
      if (pane) pane.hidden = !on;
    }
    if (focus) tab.focus();
  };
  for (const t of all) {
    t.addEventListener('click', () => select(t));
    t.addEventListener('keydown', (e) => {
      const i = all.indexOf(t);
      if (e.key === 'ArrowRight') select(all[(i + 1) % all.length], true);
      else if (e.key === 'ArrowLeft') select(all[(i - 1 + all.length) % all.length], true);
      else return;
      e.preventDefault();
    });
  }
  // Linux visitors see the Linux archive first.
  if (/Linux/.test(navigator.platform) && !/Android/.test(navigator.userAgent)) select(all[1]);
}

/** Types el's data-text, then calls done. Returns a function that stops it. */
function type(el: HTMLElement, speed: number, done: () => void): () => void {
  const text = el.dataset.text ?? '';
  let i = 0;
  el.textContent = '';
  const timer = window.setInterval(() => {
    i += 1;
    el.textContent = text.slice(0, i);
    if (i >= text.length) {
      window.clearInterval(timer);
      done();
    }
  }, speed);
  return () => window.clearInterval(timer);
}

function heroInit() {
  const typed = $('#typed-init');
  const out = $$('.init-out');
  if (!typed) return;
  if (reduce()) {
    out.forEach((l) => l.classList.add('on'));
    return;
  }
  let started = false;
  whileVisible(
    typed,
    () => {
      if (started) return;
      started = true;
      window.setTimeout(() => {
        type(typed, 70, () => out.forEach((l, i) => window.setTimeout(() => l.classList.add('on'), 350 + i * 300)));
      }, 600);
    },
    () => {},
  );
}

function fig1() {
  const fig = $('#fig1');
  const data = $('#fig1-data');
  if (!fig || !data) return;
  const { frames } = JSON.parse(data.textContent ?? '{}') as { frames: Frame[] };
  const rows = $$('[data-fact]', fig);
  const head = $('[data-head]', fig)!;
  const count = $('[data-count]', fig)!;
  const evs = $$('[data-ev]', fig);
  const show = (f: Frame) => {
    head.textContent = f.head;
    head.classList.toggle('k-st', f.stale);
    count.textContent = f.count;
    rows.forEach((row, j) => {
      const sq = $('[data-sym]', row)!;
      sq.textContent = f.facts[j].sym;
      sq.className = `sq ${f.facts[j].cls}`;
      $('[data-meta]', row)!.textContent = f.facts[j].meta;
    });
    evs.forEach((e, i) => e.classList.toggle('on', i < f.on));
  };
  if (reduce()) return; // the still frame in the HTML is the stale one
  let k = 0;
  let timer = 0;
  const tick = () => {
    show(frames[k]);
    k = (k + 1) % frames.length;
  };
  whileVisible(
    fig,
    () => {
      if (timer) return;
      k = 0;
      tick();
      timer = window.setInterval(tick, 4000);
    },
    () => {
      window.clearInterval(timer);
      timer = 0;
    },
  );
}

function fig4() {
  const typed = $('#typed-ask');
  const cur = $('#ask-cur');
  const out = $$('.agent-out');
  if (!typed) return;
  if (reduce()) {
    out.forEach((l) => l.classList.add('on'));
    cur?.remove();
    return;
  }
  let timers: number[] = [];
  let stopTyping = () => {};
  const clear = () => {
    stopTyping();
    timers.forEach((t) => window.clearTimeout(t));
    timers = [];
  };
  const play = () => {
    clear();
    out.forEach((l) => l.classList.remove('on'));
    if (cur) cur.style.display = '';
    stopTyping = type(typed, 38, () => {
      if (cur) cur.style.display = 'none';
      out.forEach((l, i) => timers.push(window.setTimeout(() => l.classList.add('on'), 600 + i * 1100)));
      timers.push(window.setTimeout(play, 600 + out.length * 1100 + 5000));
    });
  };
  whileVisible(typed, play, clear);
}

function logo() {
  const pre = $('#logo');
  const button = $<HTMLButtonElement>('#replay');
  if (!pre) return;
  const rows = $$('[data-row]', pre);
  if (reduce()) {
    button?.remove();
    return;
  }
  const noise = '░▒▓·:+*#';
  let raf = 0;
  const decode = () => {
    cancelAnimationFrame(raf);
    const t0 = performance.now();
    const frame = (now: number) => {
      const t = (now - t0) / 1000;
      let k = 0;
      let busy = false;
      for (const row of rows) {
        const src = row.dataset.row ?? '';
        let s = '';
        for (const ch of src) {
          k += 1;
          if (ch === ' ') {
            s += ' ';
            continue;
          }
          const h = (k * 2654435761) >>> 0;
          const at = 0.3 + (h % 260) / 100; // each character settles between 0.3 s and 2.9 s
          if (t < at) {
            busy = true;
            s += noise.charAt((h + Math.floor(t * 14)) % noise.length);
          } else s += ch;
        }
        row.textContent = s;
      }
      if (busy) raf = requestAnimationFrame(frame);
    };
    raf = requestAnimationFrame(frame);
  };
  let seen = false;
  whileVisible(
    pre,
    () => {
      if (!seen) decode();
      seen = true;
    },
    () => {},
  );
  button?.addEventListener('click', decode);
}

export function initHome() {
  tabs();
  heroInit();
  fig1();
  fig4();
  logo();
}
