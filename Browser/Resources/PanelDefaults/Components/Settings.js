// @ts-check
/// <reference path="../aria.d.ts" />

// A button that opens quick settings.
export default defineComponent({
  name: "Settings",
  icon: "gearshape",
  summary: "A button that shows appearance and quick settings.",
  width: 28,
  height: 28,
  render: () => button({ icon: "gearshape", help: "Settings", action: toggle("QuickSettings") }),
});
