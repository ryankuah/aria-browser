// @ts-check
/// <reference path="../aria.d.ts" />

// Find in page. It takes over the find commands, so ⌘F, ⌘G and ⇧⌘G open it.
// Return finds the next match and ⇧Return the one before.
export default defineComponent({
  name: "FindBar",
  title: "Find bar",
  icon: "text.magnifyingglass",
  summary: "Finds text in the page.",
  uses: ["page"],
  alwaysOpen: false,
  width: 360,
  height: 44,
  transition: "slide",
  background: "glass",
  cornerRadius: 12,
  border: "outline",
  local: { query: "" },
  handles: {
    find: open(),
    findNext: (aria) => { aria.open(); aria.run("findNext"); },
    findPrevious: (aria) => { aria.open(); aria.run("findPrevious"); },
  },
  onClose: run("clearFind"),
  render: (props, state, local) =>
    row([
      icon("magnifyingglass", { size: 12, color: "secondary" }),
      textField({
        bind: "query",
        placeholder: "Find",
        autofocus: true,
        selectAll: true,
        grow: true,
        // Its own find commands go to Aria, since this component is the one asking.
        onChange: run("find"),
        onSubmit: "findNext",
        onKey: { "shift+enter": "findPrevious", escape: close() },
      }),
      local.query && state.page.find.matched === false ? text("No match", { size: 11, color: "secondary" }) : null,
      button({ icon: "chevron.up", size: 11, help: "Previous", action: "findPrevious", enabled: Boolean(local.query) }),
      button({ icon: "chevron.down", size: 11, help: "Next", action: "findNext", enabled: Boolean(local.query) }),
      button({ icon: "xmark", size: 11, help: "Close", action: close() }),
    ], { spacing: 6, padding: [10, 0], grow: true }),
});
