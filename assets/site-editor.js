(() => {
  const query = new URLSearchParams(location.search);
  if (query.get("edit") === "1") sessionStorage.setItem("nomad-site-editor-enabled", "1");
  if (query.get("edit") === "0") sessionStorage.removeItem("nomad-site-editor-enabled");
  const editorEnabled = ["localhost", "127.0.0.1"].includes(location.hostname) ||
    sessionStorage.getItem("nomad-site-editor-enabled") === "1";
  if (!editorEnabled) return;

  const STORAGE_KEY = `nomad-site-layout:${location.pathname}`;
  const host = document.createElement("div");
  host.id = "site-editor-host";
  document.documentElement.appendChild(host);
  const ui = host.attachShadow({ mode: "open" });

  ui.innerHTML = `
    <style>
      :host { font-family: Inter, system-ui, sans-serif; color: #111; }
      button { border: 0; font: inherit; cursor: pointer; }
      #toggle { position: fixed; right: 18px; bottom: 18px; pointer-events: auto; padding: 12px 16px;
        border-radius: 999px; color: #fff; background: #0b6cff; font-weight: 750;
        box-shadow: 0 8px 28px #001b4d4d; }
      #bar { position: fixed; left: 50%; top: 14px; transform: translateX(-50%); pointer-events: auto;
        display: none; align-items: center; gap: 8px; max-width: calc(100vw - 24px); padding: 9px;
        border: 1px solid #d7dce5; border-radius: 16px; background: #fffffff2;
        box-shadow: 0 10px 35px #001b4d33; backdrop-filter: blur(12px); }
      #bar.visible { display: flex; }
      #bar span { padding: 0 8px; white-space: nowrap; font-size: 13px; font-weight: 700; }
      #bar button, #remove { padding: 9px 12px; border-radius: 10px; background: #edf3ff; font-weight: 700; }
      #bar button:hover, #remove:hover { background: #dce8ff; }
      #remove { position: fixed; display: none; pointer-events: auto; color: #fff; background: #d92d20; }
      #remove:hover { background: #b42318; }
      @media (max-width: 720px) { #bar span { display: none; } #bar { top: 8px; } }
    </style>
    <button id="toggle" type="button">Modifica layout</button>
    <div id="bar">
      <span>Trascina qualsiasi elemento</span>
      <button id="undo" type="button">Annulla</button>
      <button id="reset" type="button">Ripristina</button>
      <button id="done" type="button">Fine</button>
    </div>
    <button id="remove" type="button">Elimina</button>`;

  const $ = (selector) => ui.querySelector(selector);
  const toggle = $("#toggle");
  const bar = $("#bar");
  const remove = $("#remove");
  let active = false;
  let selected = null;
  let hovered = null;
  let drag = null;
  let applying = false;
  const undoStack = [];

  const readState = () => {
    try { return JSON.parse(localStorage.getItem(STORAGE_KEY) || "{}"); }
    catch { return {}; }
  };
  const writeState = (state) => localStorage.setItem(STORAGE_KEY, JSON.stringify(state));

  function elementKey(element) {
    if (element.id && element.id !== "root") return `#${CSS.escape(element.id)}`;
    const parts = [];
    let node = element;
    while (node && node !== document.body) {
      const parent = node.parentElement;
      if (!parent) return null;
      const index = [...parent.children].indexOf(node) + 1;
      parts.unshift(`${node.tagName.toLowerCase()}:nth-child(${index})`);
      node = parent;
    }
    return `body>${parts.join(">")}`;
  }

  function editable(element) {
    return element instanceof HTMLElement &&
      !["HTML", "BODY", "SCRIPT", "STYLE", "LINK", "META"].includes(element.tagName) &&
      element !== host && !host.contains(element) && element.id !== "root" &&
      !element.closest(".bubble-lens-document");
  }

  function pickElement(x, y, fallback) {
    const semantic = "h1,h2,h3,h4,h5,h6,p,li,a,button";
    const candidates = [...document.querySelectorAll(
      `${semantic},span,small,strong,em,img,video,figure,div,section,article`
    )].filter((element) => {
      if (!editable(element) || element.classList.contains("site-editor-hidden")) return false;
      const box = element.getBoundingClientRect();
      if (!box.width || !box.height || x < box.left || x > box.right || y < box.top || y > box.bottom) return false;
      const style = getComputedStyle(element);
      return style.display !== "none" && style.visibility !== "hidden";
    });

    const normalized = [...new Set(candidates.map((element) => {
      const block = element.closest(semantic);
      return block && editable(block) ? block : element;
    }))];

    normalized.sort((a, b) => {
      const aSemantic = a.matches(semantic) ? 0 : a.children.length === 0 ? 1 : 2;
      const bSemantic = b.matches(semantic) ? 0 : b.children.length === 0 ? 1 : 2;
      if (aSemantic !== bSemantic) return aSemantic - bSemantic;
      const aBox = a.getBoundingClientRect();
      const bBox = b.getBoundingClientRect();
      return aBox.width * aBox.height - bBox.width * bBox.height;
    });

    return normalized[0] || (editable(fallback) ? fallback : null);
  }

  function findElement(key) {
    try { return document.querySelector(key); } catch { return null; }
  }

  function applyState() {
    if (applying) return;
    applying = true;
    const state = readState();
    for (const [key, value] of Object.entries(state)) {
      const element = findElement(key);
      if (!element) continue;
      element.style.translate = `${value.x || 0}px ${value.y || 0}px`;
      element.classList.toggle("site-editor-hidden", Boolean(value.hidden));
    }
    applying = false;
  }

  function remember(key, before) {
    undoStack.push({ key, before });
    if (undoStack.length > 100) undoStack.shift();
  }

  function saveElement(element, next, before) {
    const key = elementKey(element);
    if (!key) return;
    const state = readState();
    remember(key, before ?? state[key] ?? null);
    state[key] = { ...(state[key] || {}), ...next };
    writeState(state);
  }

  function positionRemove() {
    if (!selected || !active || selected.classList.contains("site-editor-hidden")) {
      remove.style.display = "none";
      return;
    }
    const box = selected.getBoundingClientRect();
    remove.style.display = "block";
    remove.style.left = `${Math.max(8, Math.min(innerWidth - 90, box.right - 76))}px`;
    remove.style.top = `${Math.max(64, Math.min(innerHeight - 48, box.top - 42))}px`;
  }

  function select(element) {
    selected?.classList.remove("site-editor-selected");
    selected = editable(element) ? element : null;
    selected?.classList.add("site-editor-selected");
    positionRemove();
  }

  function setActive(value) {
    active = value;
    document.body.classList.toggle("site-editor-active", value);
    bar.classList.toggle("visible", value);
    toggle.style.display = value ? "none" : "block";
    if (!value) {
      select(null);
      hovered?.classList.remove("site-editor-hovered");
      hovered = null;
    }
  }

  toggle.addEventListener("click", () => setActive(true));
  $("#done").addEventListener("click", () => setActive(false));
  $("#undo").addEventListener("click", () => {
    const change = undoStack.pop();
    if (!change) return;
    if (change.reset) {
      writeState(change.reset);
      applyState();
      return;
    }
    const state = readState();
    if (change.before) state[change.key] = change.before;
    else delete state[change.key];
    writeState(state);
    const element = findElement(change.key);
    if (element) {
      const value = change.before || {};
      element.style.translate = `${value.x || 0}px ${value.y || 0}px`;
      element.classList.toggle("site-editor-hidden", Boolean(value.hidden));
    }
    select(element);
  });
  $("#reset").addEventListener("click", () => {
    const state = readState();
    undoStack.push({ reset: state });
    localStorage.removeItem(STORAGE_KEY);
    for (const key of Object.keys(state)) {
      const element = findElement(key);
      if (!element) continue;
      element.style.translate = "";
      element.classList.remove("site-editor-hidden");
    }
    select(null);
  });
  remove.addEventListener("click", () => {
    if (!selected) return;
    const element = selected;
    const key = elementKey(element);
    const before = readState()[key] || null;
    saveElement(element, { hidden: true }, before);
    element.classList.add("site-editor-hidden");
    select(null);
  });

  document.addEventListener("pointermove", (event) => {
    if (!active) return;
    if (drag) {
      const x = drag.x + event.clientX - drag.startX;
      const y = drag.y + event.clientY - drag.startY;
      drag.element.style.translate = `${x}px ${y}px`;
      positionRemove();
      return;
    }
    const candidate = pickElement(event.clientX, event.clientY, event.target);
    if (candidate === hovered) return;
    hovered?.classList.remove("site-editor-hovered");
    hovered = candidate;
    if (hovered && hovered !== selected) hovered.classList.add("site-editor-hovered");
  }, true);

  document.addEventListener("pointerdown", (event) => {
    if (!active || event.button !== 0) return;
    const element = pickElement(event.clientX, event.clientY, event.target);
    if (!element) return;
    event.preventDefault();
    event.stopPropagation();
    select(element);
    const key = elementKey(element);
    const state = readState();
    const before = state[key] || null;
    drag = {
      element, key, before,
      startX: event.clientX, startY: event.clientY,
      x: before?.x || 0, y: before?.y || 0,
    };
  }, true);

  document.addEventListener("pointerup", (event) => {
    if (!drag) return;
    const x = drag.x + event.clientX - drag.startX;
    const y = drag.y + event.clientY - drag.startY;
    saveElement(drag.element, { x, y }, drag.before);
    drag = null;
  }, true);

  document.addEventListener("click", (event) => {
    if (active && editable(event.target)) {
      event.preventDefault();
      event.stopPropagation();
    }
  }, true);

  document.addEventListener("keydown", (event) => {
    if (!active) return;
    if ((event.key === "Delete" || event.key === "Backspace") && selected) remove.click();
    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "z") $("#undo").click();
    if (event.key === "Escape") setActive(false);
  });

  new MutationObserver(() => queueMicrotask(applyState))
    .observe(document.body, { childList: true, subtree: true });
  addEventListener("resize", positionRemove);
  applyState();
})();
