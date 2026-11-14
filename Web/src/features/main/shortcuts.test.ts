import { describe, expect, it } from "vitest";
import { isMacPlatform, shortcutAction, shortcutLabel, type KeyPress } from "./shortcuts";

function press(key: string, modifiers: Partial<Omit<KeyPress, "key">> = {}): KeyPress {
  return { key, metaKey: false, ctrlKey: false, shiftKey: false, altKey: false, ...modifiers };
}

describe("isMacPlatform", () => {
  it("recognises Apple platforms from the platform or the user agent", () => {
    expect(isMacPlatform({ platform: "MacIntel" })).toBe(true);
    expect(isMacPlatform({ platform: "", userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0)" })).toBe(true);
    expect(isMacPlatform({ platform: "Linux x86_64", userAgent: "Mozilla/5.0 (X11; Linux x86_64)" })).toBe(false);
  });
});

describe("shortcutAction", () => {
  it("uses ⌘ on a Mac and ignores Ctrl there", () => {
    expect(shortcutAction(press("f", { metaKey: true }), true)).toBe("find");
    expect(shortcutAction(press("f", { ctrlKey: true }), true)).toBeNull();
  });

  it("uses Ctrl elsewhere and ignores ⌘ there", () => {
    expect(shortcutAction(press("f", { ctrlKey: true }), false)).toBe("find");
    expect(shortcutAction(press("f", { metaKey: true }), false)).toBeNull();
  });

  it("maps every menu equivalent to its action", () => {
    expect(shortcutAction(press(",", { metaKey: true }), true)).toBe("settings");
    expect(shortcutAction(press("l", { metaKey: true }), true)).toBe("licensing");
    expect(shortcutAction(press("p", { metaKey: true }), true)).toBe("packages");
    expect(shortcutAction(press("q", { metaKey: true }), true)).toBe("quit");
  });

  it("reads ⌘? as help, where the question mark needs Shift", () => {
    expect(shortcutAction(press("?", { metaKey: true, shiftKey: true }), true)).toBe("help");
  });

  it("does not take a key with Shift or Alt added", () => {
    expect(shortcutAction(press("F", { metaKey: true, shiftKey: true }), true)).toBeNull();
    expect(shortcutAction(press("f", { metaKey: true, altKey: true }), true)).toBeNull();
  });

  it("ignores keys with no equivalent", () => {
    expect(shortcutAction(press("constructor", { metaKey: true }), true)).toBeNull();
    expect(shortcutAction(press("x"), true)).toBeNull();
  });
});

describe("shortcutLabel", () => {
  it("writes Mac equivalents with the modifier symbols", () => {
    expect(shortcutLabel("f", {}, true)).toBe("⌘F");
    expect(shortcutLabel("z", { shift: true }, true)).toBe("⇧⌘Z");
    expect(shortcutLabel("?", {}, true)).toBe("⌘?");
  });

  it("writes other platforms' equivalents with Ctrl", () => {
    expect(shortcutLabel("f", {}, false)).toBe("Ctrl+F");
    expect(shortcutLabel("z", { shift: true }, false)).toBe("Ctrl+Shift+Z");
  });
});
