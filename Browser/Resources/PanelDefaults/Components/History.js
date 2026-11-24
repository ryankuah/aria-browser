// @ts-check
/// <reference path="../aria.d.ts" />

// A button that opens your browsing history.
export default defineComponent({
  name: "History",
  icon: "clock.arrow.circlepath",
  summary: "A button that opens your browsing history.",
  width: 28,
  height: 28,
  render: () => button({ icon: "clock.arrow.circlepath", help: "History", action: "history" }),
});
