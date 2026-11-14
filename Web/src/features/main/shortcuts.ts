// Key equivalents of the menu bar (`main.swift`). The primary modifier is ⌘ on a
// Mac and Ctrl elsewhere. Keys the browser keeps for itself (⌘Q, Ctrl+Q) never
// reach the page, so their menu items are the way to reach those actions.

export type ShortcutAction = "find" | "settings" | "licensing" | "packages" | "help" | "quit";

/** The parts of a keyboard event that a key equivalent depends on. */
export interface KeyPress {
  key: string;
  metaKey: boolean;
  ctrlKey: boolean;
  shiftKey: boolean;
  altKey: boolean;
}

const KEY_ACTIONS: ReadonlyMap<string, ShortcutAction> = new Map([
  ["f", "find"],
  [",", "settings"],
  ["l", "licensing"],
  ["p", "packages"],
  ["?", "help"],
  ["q", "quit"],
]);

/** True for a Mac or iOS browser, from `navigator.platform` and `navigator.userAgent`. */
export function isMacPlatform(navigatorLike: { platform?: string; userAgent?: string }): boolean {
  return /Mac|iPhone|iPad|iPod/.test(`${navigatorLike.platform ?? ""} ${navigatorLike.userAgent ?? ""}`);
}

function primaryModifierPressed(press: KeyPress, isMac: boolean): boolean {
  return isMac ? press.metaKey && !press.ctrlKey : press.ctrlKey && !press.metaKey;
}

/** The menu action a key press is the key equivalent of, or null. */
export function shortcutAction(press: KeyPress, isMac: boolean): ShortcutAction | null {
  if (!primaryModifierPressed(press, isMac) || press.altKey) return null;
  // Shift belongs to "?" itself; with any other key it makes a different equivalent.
  if (press.shiftKey && press.key !== "?") return null;
  return KEY_ACTIONS.get(press.key.toLowerCase()) ?? null;
}

/** A key equivalent as the menu writes it: ⇧⌘Z on a Mac, Ctrl+Shift+Z elsewhere. */
export function shortcutLabel(key: string, options: { shift?: boolean }, isMac: boolean): string {
  const shown = key.toUpperCase();
  if (isMac) return `${options.shift ? "⇧" : ""}⌘${shown}`;
  return ["Ctrl", ...(options.shift ? ["Shift"] : []), shown].join("+");
}
