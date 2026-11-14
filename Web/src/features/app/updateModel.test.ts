import { describe, expect, it, vi, type Mock } from "vitest";
import {
  outcomeKey,
  outcomePresentation,
  updateMenuModel,
  type UpdateOutcomeDTO,
  type UpdateStateDTO,
} from "./updateModel";

const idle: UpdateStateDTO = {
  currentVersion: "0.18",
  automaticChecks: false,
  lastCheckedAt: null,
  checkRunning: false,
  checkMenuTitle: "Check for Updates…",
  knownNewerVersion: null,
  availableMenuTitle: null,
  downloadURL: "https://example.test/download",
  lastOutcome: null,
};

const available: UpdateOutcomeDTO = {
  kind: "updateAvailable",
  title: "Karma Pro 0.19 Is Available",
  message: "You have 0.18. Version 0.19 was released 2 days ago.",
  version: "0.19",
  publishedAt: "2026-11-12T10:00:00Z",
  downloadURL: "https://example.test/download",
};

interface MenuSpies {
  check: Mock<() => void>;
  setAutomatic: Mock<(enabled: boolean) => void>;
  openPage: Mock<(url: string) => void>;
}

function spies(): MenuSpies {
  return {
    check: vi.fn<() => void>(),
    setAutomatic: vi.fn<(enabled: boolean) => void>(),
    openPage: vi.fn<(url: string) => void>(),
  };
}

/** The titles of a menu section, with separators shown as "---". */
function labels(items: { title?: string; separator?: boolean }[]): string[] {
  return items.map((item) => item.title ?? (item.separator ? "---" : ""));
}

describe("updateMenuModel", () => {
  it("lists check, separator, automatic and a closing separator, with no availability row when nothing is newer", () => {
    expect(labels(updateMenuModel(idle, spies()))).toEqual([
      "Check for Updates…",
      "---",
      "Check for Updates Automatically",
      "---",
    ]);
  });

  it("shows the automatic check as ticked only when the daily check is on", () => {
    expect(updateMenuModel(idle, spies())[2].checked).toBe(false);
    expect(updateMenuModel({ ...idle, automaticChecks: true }, spies())[2].checked).toBe(true);
  });

  it("disables the check item and shows Checking… while a check runs", () => {
    const items = updateMenuModel({ ...idle, checkRunning: true, checkMenuTitle: "Checking…" }, spies());

    expect(items[0].title).toBe("Checking…");
    expect(items[0].disabled).toBe(true);
    expect(updateMenuModel(idle, spies())[0].disabled).toBe(false);
  });

  it("adds the availability row between automatic and the closing separator when a newer release is known", () => {
    const items = updateMenuModel(
      { ...idle, knownNewerVersion: "0.19", availableMenuTitle: "Update 0.19 Available" },
      spies(),
    );

    expect(labels(items)).toEqual([
      "Check for Updates…",
      "---",
      "Check for Updates Automatically",
      "Update 0.19 Available",
      "---",
    ]);
  });

  it("wires each item to its action", () => {
    const actions = spies();
    const items = updateMenuModel(
      { ...idle, automaticChecks: true, availableMenuTitle: "Update 0.19 Available" },
      actions,
    );

    items[0].action?.();
    items[2].action?.();
    items[3].action?.();

    expect(actions.check).toHaveBeenCalledOnce();
    expect(actions.setAutomatic).toHaveBeenCalledWith(false);
    expect(actions.openPage).toHaveBeenCalledWith("https://example.test/download");
  });

  it("offers turning automatic checks on when the state is not loaded yet", () => {
    const actions = spies();
    updateMenuModel(null, actions)[2].action?.();

    expect(actions.setAutomatic).toHaveBeenCalledWith(true);
  });
});

describe("outcomePresentation", () => {
  it("asks with Download and Later while the page has focus", () => {
    expect(outcomePresentation(available, true)).toEqual({
      via: "alert",
      buttons: ["Download", "Later"],
      download: true,
    });
  });

  it("notifies instead when the page is in the background", () => {
    expect(outcomePresentation(available, false)).toEqual({ via: "notification" });
  });

  it("shows up-to-date and failed outcomes as an OK alert, focused or not", () => {
    const upToDate: UpdateOutcomeDTO = { ...available, kind: "upToDate" };
    const failed: UpdateOutcomeDTO = { ...available, kind: "failed" };

    for (const outcome of [upToDate, failed]) {
      expect(outcomePresentation(outcome, true)).toEqual({ via: "alert", buttons: ["OK"], download: false });
      expect(outcomePresentation(outcome, false)).toEqual({ via: "alert", buttons: ["OK"], download: false });
    }
  });
});

describe("outcomeKey", () => {
  it("is empty before any check finished", () => {
    expect(outcomeKey(idle)).toBe("");
  });

  it("changes with every finished check, even when the result repeats", () => {
    const first: UpdateStateDTO = {
      ...idle,
      lastCheckedAt: "2026-11-13T09:00:00Z",
      lastOutcome: { ...available, kind: "failed" },
    };
    const second: UpdateStateDTO = { ...first, lastCheckedAt: "2026-11-13T09:05:00Z" };

    expect(outcomeKey(first)).not.toBe(outcomeKey(second));
    expect(outcomeKey(first)).toBe(outcomeKey({ ...first, checkRunning: true }));
  });
});
