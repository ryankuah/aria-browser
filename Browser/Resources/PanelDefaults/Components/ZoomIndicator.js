// @ts-check
/// <reference path="../aria.d.ts" />

// Shows the page's zoom for a moment after it changes.
export default defineComponent({
  name: "ZoomIndicator",
  title: "Zoom indicator",
  icon: "plus.magnifyingglass",
  summary: "Shows the zoom for a moment after it changes.",
  uses: ["page"],
  activate: [when((state) => state.page.zoomFlash != null)],
  clickThrough: true,
  width: 128,
  height: 48,
  transition: "slide",
  slideFrom: "top",
  background: "glass",
  cornerRadius: 16,
  border: "outline",
  render: (props, state) =>
    row([
      icon("magnifyingglass", { size: 14, color: "secondary" }),
      text(state.page.zoomFlash ?? state.page.zoomText, { size: 18, weight: "bold", monospaced: true }),
    ], { spacing: 8, padding: [16, 0], grow: true, align: "center" }),
});
