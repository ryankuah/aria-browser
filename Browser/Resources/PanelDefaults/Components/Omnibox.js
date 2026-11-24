// @ts-check
/// <reference path="../aria.d.ts" />

// The floating field for a new tab (⌘T) and for changing the current page's
// address (⌘L, or clicking the address bar). It takes over the newTab and
// editAddress commands, so menus, keys and other components open it.
//
// Type an address or a search. ↑ and ↓ pick a suggestion, Tab completes the
// address shown, Return opens it and Esc closes the field.

/** @param {Local} local @returns {readonly Suggestion[]} */
const suggestions = (local) => /** @type {any} */ (local.results)?.items ?? [];

/** Opens a suggestion, or what's typed. @param {Aria} aria @param {Local} local @param {Suggestion | undefined} pick */
const go = (aria, local, pick) => {
  const navigating = local.mode === "navigate";
  if (pick && pick.kind === "tab" && !navigating && pick.tabId) {
    aria.run("selectTab", pick.tabId);
  } else {
    const address = pick ? pick.address : String(local.query ?? "").trim();
    if (!address) return;
    if (navigating) aria.navigate(address);
    else aria.openTab(address);
  }
  aria.close();
};

/** @param {number} step @returns {ActionFunction} */
const move = (step) => (aria, state, local) => {
  const count = suggestions(local).length;
  if (count === 0) return;
  const current = Number(local.selected ?? -1);
  let next = current + step;
  if (current === -1 && step < 0) next = count - 1;
  if (next >= count) next = 0;
  aria.set("selected", next < -1 ? -1 : next);
};

/** @param {Suggestion} item @param {boolean} selected @param {boolean} navigating */
const suggestionRow = (item, selected, navigating) => {
  const actionTitle = navigating ? "Navigate" : item.kind === "tab" ? "Switch to Tab" : null;
  const actionIcon = navigating ? "arrow.forward" : item.kind === "tab" ? "arrow.right" : item.kind === "site" ? "globe" : "clock.arrow.circlepath";
  return row([
    layers([favicon(item.favicon, { size: 18 })], {
      align: "center", width: 32, height: 32, cornerRadius: 5, background: selected ? "white/0.9" : "primary/0.08",
    }),
    column([
      text(item.title, { size: 14, weight: "semibold", lineLimit: 1 }),
      item.subtitle ? text(item.subtitle, { size: 11, weight: "medium", color: "secondary", lineLimit: 1, truncate: "middle" }) : null,
    ], { spacing: 2, grow: true }),
    actionTitle ? text(actionTitle, { size: 12, weight: "semibold", color: selected ? "primary" : "secondary" }) : null,
    layers([icon(actionIcon, { size: 15, color: selected ? "black/0.72" : "secondary" })], {
      align: "center", width: 32, height: 32, cornerRadius: 7, background: selected ? "white/0.92" : "primary/0.08",
    }),
  ], {
    spacing: 9,
    padding: [8, 0],
    height: 50,
    cornerRadius: 8,
    background: selected ? "accent/0.24" : undefined,
    hoverBackground: selected ? undefined : "primary/0.06",
    action: (aria, state, local) => go(aria, local, item),
  });
};

export default defineComponent({
  name: "Omnibox",
  title: "Address prompt",
  icon: "magnifyingglass",
  summary: "The floating field for new tabs and for changing the page’s address.",
  opensAs: "overlay",
  alwaysOpen: false,
  width: 620,
  scrim: "accent",
  align: "top",
  transition: "scale",
  background: "glass",
  cornerRadius: 10,
  border: "outline",
  local: { query: "", mode: "new", selected: -1 },
  handles: {
    newTab: (aria, state, local, address) => {
      if (typeof address === "string" && address.trim()) {
        aria.openTab(address);
        return;
      }
      aria.set({ mode: "new", query: "", selected: -1 });
      aria.open();
    },
    editAddress: (aria, state) => {
      aria.set({ mode: "navigate", query: state.url, selected: -1 });
      aria.open();
    },
  },
  render: (props, state, local) => {
    const items = suggestions(local);
    const selected = Number(local.selected ?? -1);
    const completion = /** @type {any} */ (local.results)?.completion;
    return column([
      row([
        icon("magnifyingglass", { size: 13 }),
        textField({
          bind: "query",
          suggest: "results",
          placeholder: "Search or Enter URL…",
          size: 18,
          autofocus: true,
          selectAll: true,
          grow: true,
          onChange: set("selected", -1),
          onSubmit: (aria, state, local) => go(aria, local, suggestions(local)[Number(local.selected ?? -1)]),
          onKey: {
            up: move(-1),
            down: move(1),
            escape: close(),
            tab: (aria, state, local) => {
              const next = /** @type {any} */ (local.results)?.completion;
              if (next) aria.set({ query: next, selected: -1 });
            },
          },
        }),
        completion && selected === -1 ? text("⇥ " + completion, { size: 12, color: "secondary", lineLimit: 1, truncate: "middle", maxWidth: 220 }) : null,
      ], { spacing: 9, padding: [16, 0], height: 54 }),
      items.length ? divider({ padding: [12, 0] }) : null,
      items.length
        ? column(items.map((item, index) => suggestionRow(item, index === selected, local.mode === "navigate")), { spacing: 3, padding: [12, 8] })
        : null,
    ], { spacing: 0 });
  },
});
