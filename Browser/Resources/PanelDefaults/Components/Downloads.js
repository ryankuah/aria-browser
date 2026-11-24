// @ts-check
/// <reference path="../aria.d.ts" />

// A button that opens the downloads panel. Place it in a slot, like the
// Sidebar's buttons, or anywhere in the window.
export default defineComponent({
  name: "Downloads",
  icon: "arrow.down.circle",
  summary: "A button that shows the files you’ve downloaded.",
  width: 28,
  height: 28,
  render: (props, state) =>
    button({
      icon: state.activeDownloadCount > 0 ? "arrow.down.circle.fill" : "arrow.down.circle",
      help: "Downloads",
      badge: state.activeDownloadCount,
      action: toggle("DownloadsPanel"),
    }),
});
