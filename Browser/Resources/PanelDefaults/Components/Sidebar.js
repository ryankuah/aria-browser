// @ts-check
/// <reference path="../aria.d.ts" />

// Tabs, the address bar and bookmarks. It opens while the pointer is over its
// hover area, or with ⇧⌘S, and stays open while the pointer is over it.
//
// Each part below draws one thing. The layout arranges them, and Customize
// Layout can rearrange them: double-click the Sidebar there to edit its parts.
// Components placed in the "buttons" slot line up along the bottom; those in
// "panels", like Downloads and quick settings, appear above them when opened.

/** @param {Tab} tab */
const tabRow = (tab) =>
  row([
    favicon(tab.favicon, { size: 16 }),
    text(tab.title, { size: 13, lineLimit: 1, grow: true }),
    tab.isAudible || tab.isMuted
      ? button({
          icon: tab.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
          size: 11,
          help: tab.isMuted ? "Unmute Tab" : "Mute Tab",
          action: run("muteTab", tab.id),
        })
      : null,
    button({ icon: "xmark", size: 10, help: "Close Tab", action: run("closeTab", tab.id), showOnHover: !tab.isActive }),
  ], {
    spacing: 8,
    padding: [8, 0],
    height: 34,
    cornerRadius: 8,
    background: tab.isActive ? "primary/0.12" : undefined,
    hoverBackground: tab.isActive ? undefined : "primary/0.06",
    hoverGroup: true,
    action: run("selectTab", tab.id),
    drag: "tab:" + tab.id,
    // Dropping a tab on another moves it there.
    onDrop: (aria, state, local, dropped) => {
      if (typeof dropped === "string" && dropped.startsWith("tab:")) {
        aria.run("moveTab", { id: dropped.slice(4), before: tab.id });
      }
    },
    menu: [
      tab.isBookmarked ? { label: "Unpin", icon: "pin.slash", action: run("unpinTab", tab.id) }
        : { label: "Bookmark", icon: "bookmark", action: run("bookmarkTab", tab.id) },
      tab.isAudible || tab.isMuted
        ? { label: tab.isMuted ? "Unmute Tab" : "Mute Tab", action: run("muteTab", tab.id) } : null,
      "divider",
      { label: "Copy Link", icon: "link", action: run("copy", tab.url) },
      { label: "Close Tab", icon: "xmark", action: run("closeTab", tab.id) },
    ],
  });

/** @param {Bookmark} bookmark */
const bookmarkTile = (bookmark) =>
  layers([favicon(bookmark.favicon, { size: 20 })], {
    align: "center",
    grow: true,
    height: 48,
    cornerRadius: 8,
    background: bookmark.isActive ? "primary/0.14" : "primary/0.06",
    hoverBackground: bookmark.isActive ? "primary/0.18" : "primary/0.1",
    border: bookmark.isActive ? "accent/0.6" : undefined,
    opacity: bookmark.isOpen ? 1 : 0.78,
    help: bookmark.title,
    action: run("openBookmark", bookmark.id),
    menu: [
      { label: "Open Bookmark", action: run("openBookmark", bookmark.id) },
      "divider",
      { label: "Edit URL…", icon: "pencil", action: run("editBookmark", bookmark.id) },
      { label: "Copy URL", icon: "link", action: run("copyBookmark", bookmark.id) },
      "divider",
      { label: "Remove Bookmark", icon: "trash", destructive: true, action: run("removeBookmark", bookmark.id) },
      bookmark.tabId ? { label: "Close Tab", icon: "xmark", action: run("closeTab", bookmark.tabId) } : null,
    ],
  });

/** Splits a list into rows of `size`. @template T @param {readonly T[]} list @param {number} size */
const rowsOf = (list, size) =>
  Array.from({ length: Math.ceil(list.length / size) }, (_, index) => list.slice(index * size, index * size + size));

/** @type {ActionFunction} */
const bookmarkDropped = (aria, state, local, dropped) => {
  if (typeof dropped === "string" && dropped.startsWith("tab:")) aria.run("bookmarkTab", dropped.slice(4));
};

const securityColor = { secure: "green", local: "blue", insecure: "orange", certificateError: "orange", none: "secondary" };

export default defineComponent({
  name: "Sidebar",
  icon: "sidebar.left",
  summary: "Tabs, the address bar and bookmarks, with a row of buttons at the bottom.",
  uses: ["tabs", "bookmarks", "page", "scripts"],
  activate: [hover({ edge: "left", closeDelay: 0.1 }), shortcut("cmd+shift+s")],
  width: 236,
  transition: "slide",
  background: "glass",
  corners: "left",
  border: "right",
  paddingY: 12,
  parts: {
    trafficLights: { title: "Traffic lights", icon: "ellipsis", render: () => windowControls() },
    back: {
      title: "Back",
      icon: "chevron.left",
      render: (props, state) => button({ icon: "chevron.left", help: "Back", action: "back", enabled: state.canGoBack }),
    },
    forward: {
      title: "Forward",
      icon: "chevron.right",
      render: (props, state) =>
        button({ icon: "chevron.right", help: "Forward", action: "forward", enabled: state.canGoForward }),
    },
    reload: {
      title: "Reload",
      icon: "arrow.clockwise",
      render: (props, state) =>
        button({
          icon: state.isLoading ? "xmark" : "arrow.clockwise",
          help: state.isLoading ? "Stop" : "Reload",
          action: "reload",
          enabled: state.hasPage,
        }),
    },
    address: {
      title: "Address bar",
      icon: "magnifyingglass",
      render: (props, state) => {
        const address = state.url.replace(/^https?:\/\//, "").replace(/\/$/, "");
        const warn = state.page.security === "insecure" || state.page.security === "certificateError";
        return row([
          warn ? icon(state.page.securityIcon, { size: 12, color: securityColor[state.page.security], help: state.page.securityLabel }) : null,
          text(address || "Search or enter website", {
            size: 13, lineLimit: 1, truncate: "middle", grow: true, color: address ? "primary" : "secondary",
          }),
        ], {
          spacing: 8, padding: [12, 0], height: 34, cornerRadius: 8,
          background: "primary/0.06", border: "secondary/0.22", help: state.url || undefined,
          action: run("editAddress"),
        });
      },
    },
    tabs: {
      title: "Tabs",
      icon: "square.stack",
      render: (props, state) => scroll([
        ...state.tabs.map(tabRow),
        row([spacer()], { height: 12, onDrop: (aria, state, local, dropped) => {
          if (typeof dropped === "string" && dropped.startsWith("tab:")) aria.run("moveTab", { id: dropped.slice(4) });
        } }),
      ], { spacing: 5 }),
    },
    bookmarks: {
      title: "Bookmarks",
      icon: "bookmark",
      render: (props, state) =>
        state.bookmarks.length === 0
          ? text("Drag a tab here to bookmark it", { style: "caption", opacity: 0.6, padding: [4, 6], onDrop: bookmarkDropped })
          : column(rowsOf(state.bookmarks, 3).map((items) =>
              row([...items.map(bookmarkTile), ...Array.from({ length: 3 - items.length }, () => row([], { grow: true, height: 48 }))],
                { spacing: 10 })), { spacing: 10, onDrop: bookmarkDropped, cornerRadius: 8 }),
    },
    scriptButtons: {
      title: "Script buttons",
      icon: "curlybraces",
      render: (props, state) =>
        row(state.scripts.filter((script) => script.button).map((script) =>
          button({ icon: script.button?.icon, help: script.button?.label, action: run("runScript", script.id) })), { spacing: 4 }),
    },
  },
  // <aria:layout> Customize Layout rewrites the lines up to the closing marker.
  layout: column([
    row([part("trafficLights"), part("back"), part("forward"), part("reload")], { padding: [16, 0] }),
    part("address", { padding: [10, 0] }),
    part("bookmarks", { padding: [10, 0] }),
    part("tabs", { grow: true, padding: [10, 0] }),
    slot("panels", { direction: "column", padding: [10, 0] }),
    row([spacer(), part("scriptButtons"), slot("buttons", { spacing: 4 })], { padding: [10, 0] }),
  ], { spacing: 12 }),
  // </aria:layout>
});
