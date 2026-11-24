// @ts-check
/// <reference path="../aria.d.ts" />

// Your downloads: progress while they run, then open, reveal, retry or remove.
// The Downloads button opens it. Place it in the Sidebar's "panels" slot, or
// anywhere in the window.

/** @param {Download} download */
const statusIcon = (download) =>
  download.status === "failed" ? icon("exclamationmark.circle.fill", { color: "red" })
    : download.status === "finished" ? icon("doc.fill", { color: "secondary" })
    : icon("arrow.down.circle", { color: "accent" });

/** @param {Download} download */
const downloadRow = (download) =>
  row([
    statusIcon(download),
    column([
      text(download.name, { size: 12, weight: "medium", lineLimit: 1, truncate: "middle" }),
      download.status === "downloading" ? progress(download.progress) : null,
      text(download.detail, { size: 10, color: "secondary", lineLimit: 1, truncate: "middle" }),
    ], { spacing: 3, grow: true }),
    download.canCancel ? button({ icon: "xmark.circle.fill", size: 12, help: "Cancel", action: run("cancelDownload", download.id) })
      : download.canRetry ? button({ icon: "arrow.clockwise", size: 12, help: "Retry", action: run("retryDownload", download.id) })
      : null,
  ], {
    spacing: 8,
    padding: [8, 6],
    cornerRadius: 6,
    hoverBackground: "primary/0.06",
    action: download.status === "finished" ? run("openDownload", download.id) : undefined,
    help: download.status === "finished" ? "Open" : undefined,
    menu: [
      download.canCancel ? { label: "Cancel", action: run("cancelDownload", download.id) } : null,
      download.canRetry ? { label: "Retry", action: run("retryDownload", download.id) } : null,
      { label: "Open", enabled: download.status === "finished", action: run("openDownload", download.id) },
      { label: "Show in Finder", icon: "folder", action: run("revealDownload", download.id) },
      "divider",
      { label: "Copy File Path", action: run("copyDownloadPath", download.id) },
      { label: "Copy Source URL", enabled: download.source != null, action: run("copyDownloadSource", download.id) },
    ],
  });

export default defineComponent({
  name: "DownloadsPanel",
  title: "Downloads panel",
  icon: "tray.and.arrow.down",
  summary: "The files you’ve downloaded, opened by the Downloads button.",
  uses: ["downloads"],
  alwaysOpen: false,
  width: 216,
  transition: "slide",
  slideFrom: "bottom",
  background: "glass",
  cornerRadius: 8,
  border: "outline",
  // Downloads and quick settings share the space above the Sidebar's buttons.
  onOpen: close("QuickSettings"),
  render: (props, state) =>
    column([
      row([
        text("Downloads", { size: 12, weight: "semibold", grow: true }),
        button({ icon: "folder", size: 11, help: "Open Downloads Folder", action: "openDownloadsFolder" }),
      ], { padding: [10, 2] }),
      divider(),
      state.downloads.length === 0
        ? text("No downloads", { size: 12, color: "secondary", padding: [10, 10] })
        : scroll(state.downloads.slice(0, 30).map(downloadRow), { spacing: 0, padding: [2, 4], maxHeight: 240 }),
    ], { spacing: 0 }),
});
