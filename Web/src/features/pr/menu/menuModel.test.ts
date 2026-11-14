import { describe, expect, it } from "vitest";
import { buildPRMenu, statusAccessibilityLabel, statusTooltip, type PRMenuEntry } from "./menuModel";
import type { PRState } from "./prTypes";

function state(overrides: Partial<PRState> = {}): PRState {
  return {
    monitoringEnabled: true,
    pollingIntervalMinutes: 15,
    depthChoices: [
      { value: "shallow", title: "Changed files", explanation: "Only the files the pull request touches", selected: false },
      { value: "deep", title: "Whole repository", explanation: "Every file in the repository", selected: true },
    ],
    notifyChoices: [
      { value: "off", title: "Never", selected: false },
      { value: "banner", title: "Show a banner", selected: true },
      { value: "bannerAndSound", title: "Show a banner and play a sound", selected: false },
    ],
    items: [],
    repoCount: 1,
    gitAvailable: true,
    ...overrides,
  };
}

/** The titles in order, with separators shown as "---". */
function titles(entries: PRMenuEntry[]): string[] {
  return entries.map((entry) => (entry.kind === "separator" ? "---" : entry.title));
}

describe("buildPRMenu", () => {
  it("offers only enabling and the way out while monitoring is off", () => {
    const entries = buildPRMenu(state({ monitoringEnabled: false }));

    expect(titles(entries)).toEqual([
      "Pull request monitoring is off",
      "---",
      "Enable Monitoring\u2026",
      "Manage Repositories\u2026",
      "Accounts\u2026",
      "---",
      "Quit Karma Pro",
    ]);
    const quit = entries[entries.length - 1];
    expect(quit.kind === "item" && quit.keyEquivalent).toBeFalsy();
  });

  it("lists the monitoring commands, the scan depth and the alert style, in AppKit's order", () => {
    expect(titles(buildPRMenu(state()))).toEqual([
      "Check Now",
      "Disable Monitoring",
      "---",
      "Scan depth:",
      "Changed files",
      "Whole repository",
      "Alert me about new PRs:",
      "Never",
      "Show a banner",
      "Show a banner and play a sound",
      "---",
      "Manage Repositories\u2026",
      "Accounts\u2026",
      "About Pull Request Reviews",
      "---",
      "Quit Karma Pro",
    ]);
  });

  it("puts the last poll's error first, as a disabled line", () => {
    const entries = buildPRMenu(state({ pollError: "GitHub returned 503 for owner/name." }));

    expect(entries[0]).toEqual({ kind: "label", title: "GitHub returned 503 for owner/name.", indented: false });
    expect(entries[1]).toEqual({ kind: "separator" });
  });

  it("leaves out the error line when the last poll worked", () => {
    expect(titles(buildPRMenu(state({ pollError: "" })))[0]).toBe("Check Now");
  });

  it("checks the selected depth and alert style and sends the server's values", () => {
    const entries = buildPRMenu(state());
    const deep = entries.find((entry) => entry.kind === "item" && entry.title === "Whole repository");
    const shallow = entries.find((entry) => entry.kind === "item" && entry.title === "Changed files");

    expect(deep).toEqual({
      kind: "item",
      title: "Whole repository",
      action: { kind: "setDepth", value: "deep" },
      checked: true,
      indented: true,
      tooltip: "Every file in the repository",
    });
    expect(shallow).toMatchObject({ checked: false, tooltip: "Only the files the pull request touches" });
    const banner = entries.find((entry) => entry.kind === "item" && entry.title === "Show a banner");
    expect(banner).toMatchObject({ checked: true, action: { kind: "setNotifyStyle", value: "banner" } });
  });

  it("gives an alert style no tooltip, as AppKit's alert items have none", () => {
    const banner = buildPRMenu(state()).find((entry) => entry.kind === "item" && entry.title === "Show a banner");

    expect(banner && banner.kind === "item" && banner.tooltip).toBeFalsy();
  });
});

describe("status icon", () => {
  it("says monitoring is on or off, in the tooltip and for screen readers", () => {
    expect(statusTooltip(true)).toBe("Karma Pro pull requests monitoring");
    expect(statusTooltip(false)).toBe("Karma Pro pull requests monitoring (off)");
    expect(statusAccessibilityLabel(true)).toBe("Pull request monitoring");
    expect(statusAccessibilityLabel(false)).toBe("Pull request monitoring, off");
  });
});
