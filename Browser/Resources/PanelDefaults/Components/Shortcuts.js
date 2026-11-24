// @ts-check
/// <reference path="../aria.d.ts" />

// Aria's keyboard shortcuts. Change a key, add your own, or delete this file to
// use the menu commands without these bindings. Commands that another component takes over, like newTab
// and find, go to it. Write "+" as "plus".
export default defineComponent({
  name: "Shortcuts",
  title: "Keyboard shortcuts",
  icon: "command",
  summary: "Aria’s keyboard shortcuts. It draws nothing.",
  opensAs: "none",
  keys: {
    "cmd+t": "newTab",
    "cmd+shift+t": "reopenTab",
    "cmd+w": "closeTab",
    "cmd+,": "settings",
    "cmd+l": "editAddress",
    "cmd+r": "reload",
    "cmd+[": "back",
    "cmd+]": "forward",
    "cmd+f": "find",
    "cmd+g": "findNext",
    "cmd+shift+g": "findPrevious",
    "cmd+y": "history",
    "cmd+shift+c": "copyLink",
    "cmd+opt+j": "console",
    "cmd+=": "zoomIn",
    "cmd+shift+plus": "zoomIn",
    "cmd+-": "zoomOut",
    "cmd+0": "resetZoom",
    // ⌘1 to ⌘9: bookmarks first, then tabs.
    ...Object.fromEntries([1, 2, 3, 4, 5, 6, 7, 8, 9].map((n) => ["cmd+" + n, run("selectItem", n)])),
  },
  render: () => null,
});
