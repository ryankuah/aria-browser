// @ts-check
/// <reference path="../aria.d.ts" />

// Bezel style, page zoom, camera and microphone for this site, and a way to
// the full settings. The Settings button opens it.

/** @param {string} title @param {Child[]} children */
const section = (title, children) =>
  column([text(title, { size: 11, weight: "medium", color: "secondary" }), ...children], { spacing: 7 });

/** @param {string} label @param {boolean} selected @param {Action} action */
const segment = (label, selected, action) =>
  button({ label, active: selected, action, grow: true, background: selected ? "accent/0.28" : "primary/0.06", cornerRadius: 6 });

export default defineComponent({
  name: "QuickSettings",
  title: "Quick settings",
  icon: "slider.horizontal.3",
  summary: "Appearance, zoom and site permissions, opened by the Settings button.",
  uses: ["settings", "page"],
  alwaysOpen: false,
  width: 216,
  transition: "slide",
  slideFrom: "bottom",
  background: "glass",
  cornerRadius: 8,
  border: "outline",
  onOpen: close("DownloadsPanel"),
  render: (props, state) =>
    column([
      row([
        text("Settings", { size: 12, weight: "semibold", grow: true }),
        button({ icon: "arrow.up.forward.app", size: 11, help: "Full Settings", action: "settings" }),
      ], { padding: [10, 2] }),
      divider(),
      column([
        section("Bezel Style", [
          row(state.settings.bezelStyles.map((style) =>
            segment(style.label, style.id === state.settings.bezelStyle, run("setBezelStyle", style.id))), { spacing: 6 }),
        ]),
        state.settings.isDefaultBrowser ? null : section("Default Browser", [
          button({ label: "Make Aria Your Default Browser", icon: "star", action: "makeDefaultBrowser", background: "primary/0.06", cornerRadius: 6 }),
        ]),
        section("Page Zoom", [
          row([
            button({ icon: "minus", help: "Zoom Out", action: "zoomOut", enabled: state.hasPage }),
            text(state.page.zoomText, { size: 12, weight: "semibold", monospaced: true, grow: true }),
            button({ icon: "plus", help: "Zoom In", action: "zoomIn", enabled: state.hasPage }),
            button({ icon: "arrow.counterclockwise", help: "Actual Size", action: "resetZoom", enabled: state.hasPage }),
          ], { spacing: 4 }),
        ]),
        state.page.canSetPermissions ? section("This Site", [
          row([
            segment(state.page.camera ? "Camera On" : "Camera Off", state.page.camera, run("togglePermission", "camera")),
            segment(state.page.microphone ? "Mic On" : "Mic Off", state.page.microphone, run("togglePermission", "microphone")),
          ], { spacing: 6 }),
        ]) : null,
      ], { spacing: 12, padding: [10, 10] }),
    ], { spacing: 0 }),
});
