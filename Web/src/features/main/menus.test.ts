import { describe, expect, it, vi } from "vitest";
import { buildMainMenus, type MainMenuActions } from "./menus";
import type { MenuItem } from "../../lib/ui/contextMenu.svelte";

const noop = () => undefined;

function actions(): MainMenuActions {
  return {
    about: noop,
    settings: noop,
    quit: noop,
    help: noop,
    undo: noop,
    redo: noop,
    cut: noop,
    copy: noop,
    paste: noop,
    delete: noop,
    selectAll: noop,
    find: noop,
    scanLicenses: noop,
    scanPackages: noop,
  };
}

const updateItems = (): MenuItem[] => [{ title: "Check for Updates…" }, { separator: true }];

function titled(items: MenuItem[], title: string): MenuItem | undefined {
  return items.find((item) => item.title === title);
}

describe("buildMainMenus", () => {
  it("lists the menus in the order of the menu bar", () => {
    const menus = buildMainMenus({ isMac: true, actions: actions(), updateItems });
    expect(menus.map((menu) => menu.title)).toEqual(["Karma Pro", "Edit", "Licensing", "Packages", "Help"]);
    expect(menus[0].bold).toBe(true);
  });

  it("puts the update section between Settings and Quit, reading it each time the menu opens", () => {
    const readUpdates = vi.fn(updateItems);
    const [karma] = buildMainMenus({ isMac: true, actions: actions(), updateItems: readUpdates });
    const first = karma.items().map((item) => item.title ?? "—");
    expect(first).toEqual([
      "About Karma Pro",
      "Settings…",
      "Check for Updates…",
      "—",
      "Quit Karma Pro",
    ]);
    karma.items();
    expect(readUpdates).toHaveBeenCalledTimes(2);
  });

  it("shows Mac key equivalents with symbols and other platforms' with Ctrl", () => {
    const [macKarma] = buildMainMenus({ isMac: true, actions: actions(), updateItems });
    const [otherKarma] = buildMainMenus({ isMac: false, actions: actions(), updateItems });
    expect(titled(macKarma.items(), "Settings…")?.shortcut).toBe("⌘,");
    expect(titled(macKarma.items(), "Quit Karma Pro")?.shortcut).toBe("⌘Q");
    expect(titled(otherKarma.items(), "Quit Karma Pro")?.shortcut).toBe("Ctrl+Q");
  });

  it("gives Edit its standard items and the Find in File shortcut", () => {
    const [, edit] = buildMainMenus({ isMac: true, actions: actions(), updateItems });
    const titles = edit.items().map((item) => item.title ?? "—");
    expect(titles).toEqual(["Undo", "Redo", "—", "Cut", "Copy", "Paste", "Delete", "Select All", "—", "Find in File…"]);
    expect(titled(edit.items(), "Redo")?.shortcut).toBe("⇧⌘Z");
    expect(titled(edit.items(), "Find in File…")?.shortcut).toBe("⌘F");
  });

  it("gives the Licensing, Packages and Help items their shortcuts", () => {
    const [, , licensing, packages, help] = buildMainMenus({ isMac: true, actions: actions(), updateItems });
    expect(titled(licensing.items(), "Scan Licenses")?.shortcut).toBe("⌘L");
    expect(titled(packages.items(), "Scan project's packages")?.shortcut).toBe("⌘P");
    expect(titled(help.items(), "Karma Pro Help")?.shortcut).toBe("⌘?");
  });

  it("runs the window's action when an item is chosen", () => {
    const find = vi.fn();
    const [, edit] = buildMainMenus({ isMac: false, actions: { ...actions(), find }, updateItems });
    titled(edit.items(), "Find in File…")?.action?.();
    expect(find).toHaveBeenCalledOnce();
  });
});
