// Types for Aria's component files.
// Aria rewrites this file on launch so it always matches the app.
//
// Aria draws almost nothing itself: the page, the window frame, and the camera,
// microphone and password prompts. Everything else, from the sidebar to the
// new-tab prompt, is a component file in Components/. Edit them, delete them,
// or add your own.
//
// Start each file in Components/ with:
//   // @ts-check
//   /// <reference path="../aria.d.ts" />
//
// A file can define helper functions and constants above `export default`.

type JSONValue = string | number | boolean | null;
type JSONData = JSONValue | readonly JSONData[] | { readonly [key: string]: JSONData };

// MARK: Props

interface PropOptions {
  /** The label shown in the layout editor. Defaults to the prop's name. */
  label?: string;
}

interface PropDeclaration<T extends JSONValue> {
  readonly kind: "number" | "choice" | "toggle" | "text";
  readonly default: T;
}

/** Declares a prop. Each kind becomes a control in the layout editor's inspector. */
declare const prop: {
  /** A slider with a number field. */
  number(value?: number, options?: PropOptions & { min?: number; max?: number; step?: number }): PropDeclaration<number>;
  /** A menu of options. */
  choice<T extends string>(options: readonly T[], value?: T, extra?: PropOptions): PropDeclaration<T>;
  /** A switch. */
  toggle(value?: boolean, options?: PropOptions): PropDeclaration<boolean>;
  /** A text field. */
  text(value?: string, options?: PropOptions): PropDeclaration<string>;
};

// MARK: Browser state

/** A token for favicon(): a tab's, a bookmark's, or a suggestion's. */
type FaviconToken = string;

interface Tab {
  readonly id: string;
  readonly title: string;
  readonly url: string;
  readonly host: string;
  readonly subtitle: string;
  readonly isActive: boolean;
  readonly isLoading: boolean;
  /** Playing sound. */
  readonly isAudible: boolean;
  readonly isMuted: boolean;
  readonly isBookmarked: boolean;
  readonly favicon: FaviconToken;
}

/** A bookmark. Opening one gives it a tab of its own, which isn't in `tabs`. */
interface Bookmark {
  readonly id: string;
  readonly title: string;
  readonly url: string;
  readonly host: string;
  /** Its tab, while it has one open. */
  readonly tabId: string | null;
  readonly isOpen: boolean;
  /** Its tab is the active one. */
  readonly isActive: boolean;
  readonly favicon: FaviconToken;
}

interface Download {
  readonly id: string;
  readonly name: string;
  readonly status: "downloading" | "finished" | "failed";
  /** 0 to 1, or null while the size is unknown. */
  readonly progress: number | null;
  readonly receivedBytes: number;
  readonly expectedBytes: number | null;
  readonly speedBytesPerSecond: number | null;
  /** Sizes, speed or where it was saved, written out. */
  readonly detail: string;
  readonly canCancel: boolean;
  readonly canRetry: boolean;
  readonly source: string | null;
}

interface PageState {
  /** 1 is actual size. */
  readonly zoom: number;
  readonly zoomText: string;
  /** The zoom, written out, for a moment after it changes. Otherwise null. */
  readonly zoomFlash: string | null;
  readonly security: "none" | "secure" | "local" | "insecure" | "certificateError";
  readonly securityLabel: string;
  /** An SF Symbol for the security state. */
  readonly securityIcon: string;
  /** There is a page to give camera and microphone permissions for. */
  readonly canSetPermissions: boolean;
  readonly camera: boolean;
  readonly microphone: boolean;
  /** The last find in page. `matched` is null before a search. */
  readonly find: { readonly query: string; readonly matched: boolean | null };
  /** The page failed to load. */
  readonly failed: boolean;
}

interface Option {
  readonly id: string;
  readonly label: string;
}

interface SettingsState {
  readonly bezelStyle: string;
  /** The bezel styles this Mac can show. */
  readonly bezelStyles: readonly Option[];
  readonly searchEngine: string;
  readonly searchEngines: readonly Option[];
  readonly passwordAutofill: boolean;
  readonly passwordSavePrompt: boolean;
  readonly removeQuarantine: boolean;
  readonly isDefaultBrowser: boolean;
  readonly downloadsFolder: string;
  readonly scriptsFolder: string;
}

interface UserScript {
  readonly id: string;
  readonly name: string;
  readonly enabled: boolean;
  /** Set when the script asks for a button (`@sidebar-icon`). Run it with run("runScript", id). */
  readonly button?: { readonly icon: string; readonly label: string };
}

interface ConsoleMessage {
  readonly id: string;
  readonly level: string;
  readonly source: string;
  readonly message: string;
  readonly url: string | null;
  readonly time: string;
}

/** A download notice. Camera, microphone and password prompts stay with Aria. */
interface Notice {
  readonly id: string;
  readonly title: string;
  readonly message: string;
  readonly icon: string;
  readonly status: "pending" | "success" | "failure";
  readonly progress: number | null;
  readonly downloadId: string | null;
}

/** The parts of the state a component names in `uses` to read them. */
type StateSection = "tabs" | "bookmarks" | "downloads" | "page" | "settings" | "scripts" | "console" | "notices";

/**
 * What render, when() rules and functions can read. The first group is always
 * there. The rest only when the component lists it in `uses`, so components
 * redraw only when what they read changes; reading one that isn't listed throws.
 */
interface BrowserState {
  readonly tabCount: number;
  readonly activeDownloadCount: number;
  /** There is an active tab. */
  readonly hasPage: boolean;
  readonly canGoBack: boolean;
  readonly canGoForward: boolean;
  readonly isLoading: boolean;
  readonly url: string;
  readonly host: string;
  readonly title: string;
  /** A video or other element is fullscreen. Components are hidden meanwhile. */
  readonly isFullscreen: boolean;
  readonly appearance: { readonly dark: boolean; readonly accent: string };

  /** Open tabs, in order. Needs uses: ["tabs"]. */
  readonly tabs: readonly Tab[];
  /** Needs uses: ["bookmarks"]. */
  readonly bookmarks: readonly Bookmark[];
  /** Newest first. Needs uses: ["downloads"]. */
  readonly downloads: readonly Download[];
  /** The active page. Needs uses: ["page"]. */
  readonly page: PageState;
  /** Needs uses: ["settings"]. */
  readonly settings: SettingsState;
  /** Needs uses: ["scripts"]. */
  readonly scripts: readonly UserScript[];
  /** The latest 500 messages. Needs uses: ["console"]. */
  readonly console: readonly ConsoleMessage[];
  /** Needs uses: ["notices"]. */
  readonly notices: readonly Notice[];
}

/** A component's own state: what it set with set(), over its file's `local`. Cleared when it closes. */
type Local = { readonly [key: string]: JSONData };

// MARK: Actions

/**
 * Commands Aria runs. Those that take an argument are written run("name", arg).
 *
 * Page: back, forward, reload (stops while loading), stop, retry, zoomIn, zoomOut,
 *   resetZoom, copyLink, copy (text), togglePermission ("camera" | "microphone"),
 *   find ({ query, backwards } or the query), findNext, findPrevious, clearFind.
 * Tabs: newTab (an address, or nothing for a blank tab), closeTab (id, or the active tab),
 *   reopenTab, selectTab (id), selectItem (1 to 9: bookmarks, then tabs), moveTab ({ id, before }),
 *   muteTab (id), bookmarkTab (id), unpinTab (id).
 * Bookmarks: openBookmark, editBookmark, copyBookmark, removeBookmark (each takes an id).
 * Downloads: openDownload, revealDownload, cancelDownload, retryDownload, copyDownloadPath,
 *   copyDownloadSource (each takes an id), openDownloadsFolder, dismissNotice (a notice's id).
 * Settings: setBezelStyle (id), setSearchEngine (id), setPasswordAutofill, setPasswordSavePrompt,
 *   (each true or false), makeDefaultBrowser. Download quarantine is controlled in native Settings.
 * Scripts and console: runScript (id), setScriptEnabled ({ id, enabled }), reloadScripts,
 *   openScriptsFolder, clearConsole, copyConsole.
 * Windows: history, settings, customize.
 * Prompts Aria doesn't draw, which do nothing until a component `handles` them: console, editAddress.
 *
 * Any command can be taken over: see `handles`.
 */
type Command =
  | "back" | "forward" | "reload" | "stop" | "retry" | "zoomIn" | "zoomOut" | "resetZoom" | "copyLink" | "copy"
  | "togglePermission" | "find" | "findNext" | "findPrevious" | "clearFind"
  | "newTab" | "closeTab" | "reopenTab" | "selectTab" | "selectItem" | "moveTab" | "muteTab" | "bookmarkTab" | "unpinTab"
  | "openBookmark" | "editBookmark" | "copyBookmark" | "removeBookmark"
  | "openDownload" | "revealDownload" | "cancelDownload" | "retryDownload" | "copyDownloadPath" | "copyDownloadSource"
  | "openDownloadsFolder" | "dismissNotice"
  | "setBezelStyle" | "setSearchEngine" | "setPasswordAutofill" | "setPasswordSavePrompt"
  | "makeDefaultBrowser" | "runScript" | "setScriptEnabled" | "reloadScripts" | "openScriptsFolder"
  | "clearConsole" | "copyConsole" | "history" | "settings" | "customize" | "console" | "editAddress";

interface ActionValue {
  readonly kind: "open" | "close" | "toggle" | "command" | "set" | "openTab" | "navigate";
  readonly target: string;
}

/** Opens a component by name. Leave the name out for the component it's in. */
declare function open(name?: string): ActionValue;
/** Closes a component by name. Leave the name out for the component it's in. */
declare function close(name?: string): ActionValue;
/** Opens a component if it's closed, and closes it if it's open. */
declare function toggle(name?: string): ActionValue;
/** Runs a command with an argument. A bare command name works too, like action: "back". */
declare function run(command: Command, arg?: JSONData): ActionValue;
/** Sets a key of the component's own state. Without a value, it takes the event's: the text typed, say. */
declare function set(key: string, value?: JSONData): ActionValue;
/** Opens an address or search in a new tab. */
declare function openTab(address: string): ActionValue;
/** Opens an address or search in the active tab. */
declare function navigate(address: string): ActionValue;

/** What a function can ask Aria to do. It all happens once the function returns. */
interface Aria {
  open(name?: string): void;
  close(name?: string): void;
  toggle(name?: string): void;
  run(command: Command, arg?: JSONData): void;
  openTab(address: string): void;
  navigate(address: string): void;
  /** Sets one key of the component's own state, or several from an object. */
  set(key: string, value: JSONData): void;
  set(values: { [key: string]: JSONData }): void;
  /** Finds text in the page. find next and previous repeat it. */
  find(query: string, options?: { backwards?: boolean }): void;
  /** Copies text to the clipboard. */
  copy(text: string): void;
}

/**
 * A function the component's file runs when the action happens. `event` is what
 * happened: the text in a text field, what was dropped, or a command's argument.
 */
type ActionFunction = (aria: Aria, state: BrowserState, local: Local, event: JSONData) => void;

type Action = Command | ActionValue | ActionFunction;

// MARK: Pieces

/** Colours: "primary", "secondary", "tertiary", "accent", "red", "orange", "yellow", "green",
 *  "blue", "purple", "pink", "gray", "white", "black", "clear" or "#RRGGBB(AA)". Add "/0.2"
 *  for opacity, like "primary/0.08". */
type Color = string;

interface MenuItem {
  label: string;
  /** An SF Symbol name. */
  icon?: string;
  action?: Action;
  destructive?: boolean;
  enabled?: boolean;
}

/** Options every piece takes. */
interface PieceOptions {
  /** Take the leftover space along the row or column this piece is in. */
  grow?: boolean;
  width?: number;
  height?: number;
  minWidth?: number;
  maxWidth?: number;
  minHeight?: number;
  maxHeight?: number;
  /** Space around the piece: one number, or [horizontal, vertical]. */
  padding?: number | [number, number];
  /** Text and icon colour. */
  color?: Color;
  /** A colour, or "glass". */
  background?: Color | "glass";
  /** The background while the pointer is over the piece. */
  hoverBackground?: Color;
  /** A colour for a hairline around the piece. */
  border?: Color;
  /** For the background, border and hover. Defaults to 7. */
  cornerRadius?: number;
  opacity?: number;
  /** Shown when the pointer rests on the piece. */
  help?: string;
  /** Runs when the piece is clicked. Buttons, switches and text fields use it their own way. */
  action?: Action;
  /** A right-click menu. Use "divider" between groups. */
  menu?: (MenuItem | "divider" | null | false)[];
  /** Makes the piece draggable. The text is what a drop receives, like "tab:" + tab.id. */
  drag?: string;
  /** Accepts drops. The event is the dropped text: another piece's `drag`, a link, or text. */
  onDrop?: Action;
  /** Tracks the pointer, for pieces inside marked showOnHover. */
  hoverGroup?: boolean;
  /** Shown only while the pointer is over the nearest hoverGroup around it. */
  showOnHover?: boolean;
}

interface Piece {
  readonly kind: string;
}

type Child = Piece | string | number | null | undefined | false | Child[];

interface StackOptions extends PieceOptions {
  /** Space between children. Defaults to 8. */
  spacing?: number;
  /** Columns: "leading", "center" or "trailing". Rows: "top", "center" or "bottom". */
  align?: "leading" | "center" | "trailing" | "top" | "bottom";
}

interface TextOptions extends PieceOptions {
  style?: "body" | "title" | "caption" | "secondary";
  /** A point size. It overrides the style's. */
  size?: number;
  weight?: "light" | "regular" | "medium" | "semibold" | "bold" | "heavy";
  lineLimit?: number;
  /** Where long text is cut. Defaults to "tail". */
  truncate?: "head" | "middle" | "tail";
  /** Digits line up, for numbers that change. */
  monospaced?: boolean;
}

interface ButtonOptions extends PieceOptions {
  /** An SF Symbol name. */
  icon?: string;
  label?: string;
  weight?: TextOptions["weight"];
  enabled?: boolean;
  /** Show the button as pressed. Buttons that toggle an open component do this themselves. */
  active?: boolean;
  /** A number shown in the corner when it's above zero. */
  badge?: number;
  /** The icon's size. */
  size?: number;
  /** More to draw in the button, after its icon and label. */
  children?: Child[];
  /** Shown hanging from the button while it's pressed, in a system popover. Clicking elsewhere closes it. */
  popover?: Child;
}

/** Key names onKey takes. */
type FieldKey = "up" | "down" | "escape" | "tab" | "shift+tab" | "shift+enter";

interface TextFieldOptions extends PieceOptions {
  /** The key of the component's own state that holds the text. Defaults to "text". */
  bind?: string;
  placeholder?: string;
  /** A point size. Defaults to 13. */
  size?: number;
  weight?: TextOptions["weight"];
  /** Focus the field when it appears. */
  autofocus?: boolean;
  /** Select its text when it appears. */
  selectAll?: boolean;
  enabled?: boolean;
  /**
   * A key of the component's own state to keep address suggestions in, for what's typed:
   * { query, items: Suggestion[], completion }. `completion` is the address the top
   * site or page would complete the text to.
   */
  suggest?: string;
  /** Runs on Return. The event is the text. */
  onSubmit?: Action;
  /** Runs as the text changes. The event is the text. */
  onChange?: Action;
  /** Runs on keys the field would otherwise keep. The event is the text. */
  onKey?: Partial<Record<FieldKey, Action>>;
}

/** An address suggestion, in the key a text field's `suggest` names. */
interface Suggestion {
  readonly id: string;
  readonly kind: "tab" | "site" | "page";
  readonly title: string;
  readonly subtitle: string;
  readonly address: string;
  /** For an open tab. */
  readonly tabId?: string;
  readonly favicon: FaviconToken;
}

interface SlotOptions extends PieceOptions {
  /** "row" (the default) or "column". */
  direction?: "row" | "column";
  /** Space between the components in it. Defaults to 8. */
  spacing?: number;
  align?: StackOptions["align"];
}

/** Children side by side. */
declare function row(children: Child[], options?: StackOptions): Piece & LayoutPiece;
/** Children top to bottom. They take the column's full width. */
declare function column(children: Child[], options?: StackOptions): Piece & LayoutPiece;
/** Children on top of each other, the first at the back. `align` places them. */
declare function layers(children: Child[], options?: StackOptions): Piece;
/** Children in a column, or a row with direction: "row", that scrolls when they don't fit. */
/** Supply a changing followEnd token to scroll to the newest entry. */
declare function scroll(children: Child[], options?: StackOptions & { direction?: "row" | "column"; indicators?: boolean; followEnd?: string }): Piece;
/** Takes up leftover space in a row or column. */
declare function spacer(options?: PieceOptions): Piece & LayoutPiece;
declare function divider(options?: PieceOptions): Piece & LayoutPiece;
declare function text(value: string | number, options?: TextOptions): Piece;
/** An SF Symbol. */
declare function icon(name: string, options?: PieceOptions & { size?: number; weight?: TextOptions["weight"] }): Piece;
/** A favicon from the state, like tab.favicon. `icon` is the SF Symbol shown without one; it defaults to a globe. */
declare function favicon(token: FaviconToken, options?: PieceOptions & { size?: number; icon?: string }): Piece;
/** A progress bar, 0 to 1. Null or nothing shows it moving, for progress of unknown length. */
declare function progress(value?: number | null, options?: PieceOptions): Piece;
/** A text field. Its text lives in the component's own state, under `bind`. */
declare function textField(options?: TextFieldOptions): Piece;
/** An on-off switch. It shows `on`, and runs its action when flipped. */
declare function switchControl(options: PieceOptions & { on: boolean; label?: string; size?: number; enabled?: boolean }): Piece;
/** A button. Give it an action to run, a popover to show, or both. */
declare function button(options: ButtonOptions): Piece;
/** An area that moves the window when dragged, for a custom title bar. */
declare function dragRegion(options?: PieceOptions): Piece;
/** The window's close, minimise and zoom buttons. */
declare function windowControls(options?: PieceOptions): Piece;
/**
 * A place for other components. In the layout editor, drag components into it;
 * they line up in a row or column, each drawn by its own file. Components in a
 * slot that aren't open aren't drawn, so a slot can hold panels a button opens.
 */
declare function slot(name: string, options?: SlotOptions): Piece & LayoutPiece;

// MARK: Parts

/** Where a part goes in a component's layout. */
interface LayoutPiece {
  readonly kind: "row" | "column" | "spacer" | "divider" | "part" | "slot";
}

/** A part the component's `parts` defines, placed in its layout. */
declare function part(name: string, options?: PieceOptions): LayoutPiece & Piece;

/** One named part: draws one thing, like a button or the tab list. */
type PartDefinition<Props> =
  | ((props: Props, state: BrowserState, local: Local) => Child)
  | {
      /** The name shown in the layout editor. Defaults to the part's key. */
      title?: string;
      /** An SF Symbol name for the layout editor. */
      icon?: string;
      render(props: Props, state: BrowserState, local: Local): Child;
    };

// MARK: Activators

interface Activator {
  readonly kind: "hover" | "shortcut" | "when";
}

/**
 * An invisible area you place in the layout editor. The component opens while
 * the pointer is over it, and stays open while the pointer is over the component.
 * A new hover area runs along `edge`, `size` points thick. An area on the edge of
 * the page reaches the window's edge. The component closes `closeDelay` seconds
 * after the pointer leaves; the default is 0.1.
 */
declare function hover(options?: { edge?: "left" | "right" | "top" | "bottom"; size?: number; closeDelay?: number }): Activator;
/** A keyboard shortcut that opens and closes the component, like "cmd+shift+d". */
declare function shortcut(keys: string): Activator;
/** Keeps the component open while the function returns true. */
declare function when(test: (state: BrowserState, local: Local) => boolean): Activator;

// MARK: Components

type Edge = "left" | "right" | "top" | "bottom";

interface ComponentSpec<Props extends Record<string, PropDeclaration<JSONValue>>> {
  /** The component's name. Starts with a capital letter; letters and digits only. */
  name: string;
  /** The name shown in the layout editor. Defaults to `name`. */
  title?: string;
  /** An SF Symbol name. */
  icon?: string;
  summary?: string;
  /** The parts of the state it reads, beyond the basics. */
  uses?: StateSection[];
  /**
   * What opens it, besides buttons in other components. With none, it is always
   * open where it's placed: in the window, or in another component's slot.
   */
  activate?: Activator[];
  /** Set false for a component only buttons, commands or keys open. */
  alwaysOpen?: boolean;
  /**
   * "placed": where you place it in the layout editor (the default).
   * "overlay": over the window, while something has it open.
   * "none": nowhere, for a component that only adds keys or takes over commands.
   * For a popover, render a button with a `popover`.
   */
  opensAs?: "placed" | "overlay" | "none";
  /** Its size when it opens as an overlay, or when it's first placed in the window. */
  width?: number;
  height?: number;
  /** How it appears. "slide" comes in from `slideFrom`, its hover edge, or the edge it sits nearest. */
  transition?: "fade" | "slide" | "scale" | "none";
  slideFrom?: Edge;
  /** An overlay's backdrop, which closes it when clicked. "none" leaves the window usable. */
  scrim?: "dim" | "accent" | "none";
  /** Where an overlay sits. */
  align?: "center" | "top";
  /** Clicks pass through it, for something that only shows information. */
  clickThrough?: boolean;
  /** Defaults for the style props every component gets. The background defaults to "none". */
  background?: "glass" | "solid" | "none";
  cornerRadius?: number;
  /** Which corners are rounded. */
  corners?: "all" | Edge;
  /** A hairline on one edge, or all around. */
  border?: "none" | "outline" | Edge;
  paddingX?: number;
  paddingY?: number;
  props?: Props;
  /** Its own state when it opens. set() changes it; it goes back to this when the component closes. */
  local?: { [key: string]: JSONData };
  /** Keys it binds, like { "cmd+l": run("editAddress") }. Write "+" as "plus". They work while it's closed. */
  keys?: { [keys: string]: Action };
  /**
   * Commands it takes over, from menus, keys and other components, like
   * { newTab: open() }. The event is the command's argument. When the component
   * runs a command it handles, Aria runs it, so it can take one over and still use it.
   */
  handles?: Partial<Record<Command, Action>>;
  /** Runs when it opens. */
  onOpen?: Action;
  /** Runs when it closes. */
  onClose?: Action;
  /**
   * Draws the component. Aria runs it again when its props, its own state or the
   * state it uses change. Give either render, or parts and a layout.
   */
  render?(props: ResolvedProps<Props>, state: BrowserState, local: Local): Child;
  /**
   * Named parts, each drawing one thing. The layout arranges them, and the layout
   * editor can rearrange them: double-click the component there.
   */
  parts?: Record<string, PartDefinition<ResolvedProps<Props>>>;
  /**
   * How the parts are arranged, made of row, column, spacer, divider, part and slot.
   * It can't depend on props or state; a part can draw nothing instead.
   *
   * For the layout editor to save changes, put a comment containing <aria:layout>
   * on the line before it and one containing </aria:layout> on the line after.
   * The editor rewrites the lines between them and leaves the rest of the file alone.
   */
  layout?: LayoutPiece;
}

type ResolvedProps<Props extends Record<string, PropDeclaration<JSONValue>>> =
  { readonly [K in keyof Props]: Props[K]["default"] } & Readonly<Record<string, JSONValue>>;

/**
 * Declares a component. Every component also gets `background`, `cornerRadius`,
 * `corners`, `border`, `paddingX` and `paddingY` props unless it declares its own.
 */
declare function defineComponent<Props extends Record<string, PropDeclaration<JSONValue>>>(
  spec: ComponentSpec<Props>
): ComponentSpec<Props>;
