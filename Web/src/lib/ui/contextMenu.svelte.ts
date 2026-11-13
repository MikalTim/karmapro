// NSMenu: a pop-up menu opened at the pointer (context menus) or at a point.
export interface MenuItem {
  title?: string;
  action?: () => void;
  separator?: boolean;
  /** Disabled items are drawn dimmed and cannot be chosen. */
  disabled?: boolean;
  /** Draws a check mark (NSMenuItem.state == .on). */
  checked?: boolean;
  /** Right-aligned key equivalent text, for example "⌘F". */
  shortcut?: string;
  submenu?: MenuItem[];
}

export const contextMenu = $state<{ open: boolean; x: number; y: number; items: MenuItem[] }>({
  open: false,
  x: 0,
  y: 0,
  items: [],
});

/** Opens a context menu at the pointer position of `event`. */
export function showContextMenu(event: MouseEvent, items: MenuItem[]): void {
  event.preventDefault();
  showMenuAt(event.clientX, event.clientY, items);
}

export function showMenuAt(x: number, y: number, items: MenuItem[]): void {
  contextMenu.items = items;
  contextMenu.x = x;
  contextMenu.y = y;
  contextMenu.open = true;
}

export function closeContextMenu(): void {
  contextMenu.open = false;
}
