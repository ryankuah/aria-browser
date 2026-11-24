// @ts-check
/// <reference path="../aria.d.ts" />

// Download notices: progress while a file downloads, then a way to open it.
// Camera, microphone and password prompts aren't components: Aria shows those.

const statusColor = { pending: "accent", success: "green", failure: "red" };

/** @param {Notice} notice */
const noticeCard = (notice) =>
  column([
    row([
      icon(notice.icon, { size: 14, color: statusColor[notice.status], width: 22, height: 22 }),
      column([
        text(notice.title, { size: 12, weight: "semibold", lineLimit: 2 }),
        notice.message ? text(notice.message, { size: 11, color: "secondary", lineLimit: 2, truncate: "middle" }) : null,
      ], { spacing: 2, grow: true }),
      button({ icon: "xmark", size: 10, help: "Dismiss", action: run("dismissNotice", notice.id) }),
    ], { spacing: 8, align: "top" }),
    notice.status === "pending" ? progress(notice.progress) : null,
    notice.status === "success" && notice.downloadId
      ? row([spacer(), button({ label: "Open", weight: "semibold", action: run("openDownload", notice.downloadId), background: "primary/0.1" })])
      : null,
  ], { spacing: 7, padding: [14, 12], background: "glass", cornerRadius: 20, border: "white/0.18" });

export default defineComponent({
  name: "Notices",
  icon: "bell",
  summary: "Download progress, and a way to open what finished.",
  uses: ["notices"],
  activate: [when((state) => state.notices.length > 0)],
  width: 320,
  height: 360,
  transition: "slide",
  slideFrom: "right",
  render: (props, state) => column(state.notices.slice(0, 4).map(noticeCard), { spacing: 8 }),
});
