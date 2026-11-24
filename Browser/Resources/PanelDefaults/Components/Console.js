// @ts-check
/// <reference path="../aria.d.ts" />

// Messages pages log, with errors in red. ⌥⌘J or Show Console opens it.

const levelColor = { error: "red", warn: "orange", warning: "orange", info: "blue", debug: "secondary" };

/** @param {ConsoleMessage} message */
const messageRow = (message) =>
  row([
    text(message.time, { size: 10, monospaced: true, color: "secondary" }),
    text(message.level.toUpperCase(), { size: 10, weight: "semibold", color: levelColor[message.level] ?? "secondary", width: 44 }),
    text(message.source, { size: 10, color: "secondary", width: 64, lineLimit: 1 }),
    column([
      text(message.message, { size: 11, monospaced: true }),
      message.url ? text(message.url, { size: 10, color: "secondary", truncate: "middle", lineLimit: 1 }) : null,
    ], { spacing: 3, grow: true }),
  ], {
    spacing: 8,
    align: "top",
    padding: [10, 3],
    help: message.url ?? undefined,
    menu: [{ label: "Copy Message", action: run("copy", message.message) }],
  });

export default defineComponent({
  name: "Console",
  icon: "terminal",
  summary: "Messages the page logs.",
  uses: ["console"],
  alwaysOpen: false,
  width: 640,
  height: 260,
  transition: "slide",
  slideFrom: "bottom",
  background: "glass",
  cornerRadius: 12,
  border: "outline",
  handles: { console: toggle() },
  render: (props, state) =>
    column([
      row([
        text("Console", { size: 12, weight: "semibold", grow: true }),
        button({ icon: "doc.on.doc", size: 11, help: "Copy Console", action: "copyConsole" }),
        button({ label: "Clear", action: "clearConsole" }),
        button({ icon: "xmark", size: 11, help: "Close Console", action: close() }),
      ], { spacing: 4, padding: [10, 4] }),
      divider(),
      state.console.length === 0
        ? text("No console messages", { size: 12, color: "secondary", padding: [12, 12] })
        : scroll(state.console.map(messageRow), { spacing: 0, grow: true, indicators: true, followEnd: state.console.at(-1)?.id }),
    ], { spacing: 0 }),
});
