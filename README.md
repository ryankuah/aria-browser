<p align="center">
  <img src="docs/media/aria-icon.png" width="100" alt="Aria app icon">
</p>

<h1 align="center">Aria</h1>

<p align="center">A minimal, native browser for macOS.</p>

<p align="center">
  <strong><a href="https://github.com/ryankuah/aria-browser/releases">Download for Mac</a></strong>
  &nbsp; · &nbsp;
  <a href="https://github.com/ryankuah/aria-browser/issues">Report an issue</a>
  &nbsp; · &nbsp;
  <a href="docs/development.md">Build from source</a>
</p>

<p align="center"><sub>macOS 15+ &nbsp; · &nbsp; Apple Silicon & Intel &nbsp; · &nbsp; SwiftUI + WebKit</sub></p>

> [!WARNING]
> **Under active development.** Aria is experimental and not yet polished. Features may be incomplete, and bugs may affect browsing, downloads, or saved data. Use it as a secondary browser, keep backups of important data, and avoid relying on it for sensitive or critical tasks.

![Aria displaying NASA’s Webb website with its sidebar hidden and a thin frame around the page.](docs/media/aria-browser.png)

<p align="center"><sub>Captured in Aria 1.5.4, the current development build. Public releases may differ.</sub></p>

## More room for the web

Aria gives almost the entire window to the page. A thin bezel frames what you’re reading, watching, or working on.

Move your pointer to the left edge to reveal your tabs, bookmarks, and navigation controls. Move back to the page and the sidebar slips away.

## A new tab, without losing your place

Press **⌘ T** and a floating search field appears over your current page. Type a website or search query, then press **Return** to open it. Your page stays in view until you’re ready to go.

Suggestions help you return to visited pages and switch to tabs you already have open.

![Aria’s floating new-tab prompt with swift.org entered, followed by the Swift website opening.](docs/media/new-tab.gif)

## Familiar controls. A lighter interface.

Swipe with two fingers to move back and forward through your browsing history. Find text with **⌘ F**, step through matches with **⌘ G**, and adjust page zoom from the keyboard.

Built with **SwiftUI and WebKit**, Aria uses the web engine supplied with macOS.

![Aria’s compact find panel searching for Webb and stepping through matches on the page.](docs/media/find-in-page.gif)

## The everyday details

| Feature | What you can do |
| --- | --- |
| **Tabs & bookmarks** | Drag to reorder tabs, keep favourite sites in the bookmark shelf, and mute tabs playing audio. |
| **Session restore** | Return to your open tabs after relaunching, or reopen a tab you just closed. |
| **Downloads** | See progress and transfer speed, open completed files, and reveal them in Finder. |
| **Your choice of search** | Choose Google, DuckDuckGo, or Brave. |
| **Userscripts** | Customise websites with JavaScript, URL matching, and optional sidebar buttons. |
| **Saved passwords** | Save website passwords in the macOS Keychain and autofill returning logins. |
| **Site permissions** | Control camera and microphone access for the current website. |
| **Appearance** | Choose a simple bezel, or Liquid Glass on macOS 26 and later. |

## Customize the layout

Open **View → Customize Layout…** (⌥⌘L). Choose **Docked** or **Overlay**, then drag a component from the library or preview to a window edge. You can also select a component and click an edge. Components on the same edge with the same placement share a panel. Select one to change the panel size or visibility script, reorder its contents, or remove the component. **Save Layout** applies the changes to your open window.

Aria saves placement in `~/Library/Application Support/com.ryankuah.browser/ui-config.json`. **Open Scripts Folder** opens the adjacent `PanelScripts` directory. Each UTF-8 `.js` file is the body of a visibility rule. For example, save this as `multiple-tabs.js` to show a panel when the window has more than one tab.

```js
return state.tabCount > 1;
```

Rules can read `state.edge`, `mode`, `pointerAtEdge`, `pointerInsidePanel`, `tabCount`, `activeDownloadCount`, and `host` on the same state object. Return a boolean. Aria reevaluates rules when these inputs change and reloads files when the app becomes active or you click **Reload Scripts**. Select the filename in the panel’s **Visibility** menu. The editor shows all placed panels, including ones hidden by their scripts.

## Get Aria

1. Download the DMG from [GitHub Releases](https://github.com/ryankuah/aria-browser/releases).
2. Open it and drag **Aria** into **Applications**.
3. Launch Aria and press **⌘ T** to start browsing.

Requires **macOS 15 or later**. Install updates from the releases page.

<details>
<summary><strong>Keyboard shortcuts</strong></summary>

| Action | Shortcut |
| --- | --- |
| Open a new tab | ⌘ T |
| Close the current tab | ⌘ W |
| Reopen a closed tab | ⇧ ⌘ T |
| Find in page | ⌘ F |
| Next / previous match | ⌘ G / ⇧ ⌘ G |
| Show history | ⌘ Y |
| Copy the page link | ⇧ ⌘ C |
| Zoom in / out / reset | ⌘ + / ⌘ − / ⌘ 0 |

</details>

<details>
<summary><strong>Build and release</strong></summary>

Open `Browser.xcodeproj` in **Xcode 26 or newer**, select the `Browser` scheme and your development signing team, then run.

See the [development guide](docs/development.md) for DMG packaging, signing, and notarisation.

</details>

---

Made by [Ryan Kuah](https://ryankuah.com). Website content shown in the demos belongs to [NASA](https://science.nasa.gov/mission/webb/) and [Swift.org](https://www.swift.org/).
