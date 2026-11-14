// The menu bar's menus (`main.swift` `makeMainMenu` and its targets). The window
// supplies every action; this module states what each menu contains and the key
// equivalent each item shows.
import type { MenuItem } from "../../lib/ui/contextMenu.svelte";
import { shortcutLabel } from "./shortcuts";

export interface MenuSpec {
  title: string;
  bold?: boolean;
  /** Read each time the menu opens, so the update section is current. */
  items: () => MenuItem[];
}

export interface MainMenuActions {
  about(): void;
  settings(): void;
  quit(): void;
  help(): void;
  undo(): void;
  redo(): void;
  cut(): void;
  copy(): void;
  paste(): void;
  delete(): void;
  selectAll(): void;
  find(): void;
  scanLicenses(): void;
  scanPackages(): void;
}

export interface MainMenuOptions {
  isMac: boolean;
  actions: MainMenuActions;
  /** The update section of the Karma Pro menu, `updateMenuItems()`. */
  updateItems: () => MenuItem[];
}

const SEPARATOR: MenuItem = { separator: true };

export function buildMainMenus({ isMac, actions, updateItems }: MainMenuOptions): MenuSpec[] {
  const key = (name: string, shift = false): string => shortcutLabel(name, { shift }, isMac);
  return [
    {
      title: "Karma Pro",
      bold: true,
      // The update section ends with its own separator, so Quit follows it directly.
      items: () => [
        { title: "About Karma Pro", action: actions.about },
        { title: "Settings…", action: actions.settings, shortcut: key(",") },
        ...updateItems(),
        { title: "Quit Karma Pro", action: actions.quit, shortcut: key("q") },
      ],
    },
    {
      title: "Edit",
      items: () => [
        { title: "Undo", action: actions.undo, shortcut: key("z") },
        { title: "Redo", action: actions.redo, shortcut: key("z", true) },
        SEPARATOR,
        { title: "Cut", action: actions.cut, shortcut: key("x") },
        { title: "Copy", action: actions.copy, shortcut: key("c") },
        { title: "Paste", action: actions.paste, shortcut: key("v") },
        { title: "Delete", action: actions.delete },
        { title: "Select All", action: actions.selectAll, shortcut: key("a") },
        SEPARATOR,
        { title: "Find in File…", action: actions.find, shortcut: key("f") },
      ],
    },
    {
      title: "Licensing",
      items: () => [{ title: "Scan Licenses", action: actions.scanLicenses, shortcut: key("l") }],
    },
    {
      title: "Packages",
      items: () => [{ title: "Scan project's packages", action: actions.scanPackages, shortcut: key("p") }],
    },
    {
      title: "Help",
      items: () => [{ title: "Karma Pro Help", action: actions.help, shortcut: key("?") }],
    },
  ];
}
