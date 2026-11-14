import { describe, expect, it } from "vitest";
import type { DetectionDTO, PRChoiceDTO, RepoDTO } from "./dto";
import {
  afterRepoAdded,
  defaultDepth,
  depthExplanation,
  detectionLine,
  notificationNotice,
  repoColumns,
  showsAccountPicker,
  type RepoFormState,
} from "./repos";

const depths: PRChoiceDTO[] = [
  { value: "changedOnly", title: "Changed files only", explanation: "Reads the changed files.", selected: false },
  { value: "fullProject", title: "Whole project", explanation: "Reads the whole project.", selected: true },
];

const repo: RepoDTO = {
  id: "github|https://api.github.com|owner/name",
  provider: "github",
  webURL: "https://github.com/owner/name",
  repoSlug: "owner/name",
  localPath: null,
  visibility: "privateRepo",
  typeText: "Private",
  depth: "changedOnly",
  depthTitle: "Changed files only",
  baseBranches: [],
  enabled: true,
  watchingTooltip: "Watching this repository",
  accountIdentity: "github|api.github.com|alice",
  accountText: "alice",
  accountChoices: [],
  sourceText: "Remote",
};

describe("repository table", () => {
  it("has the six columns at the AppKit widths, with only the last one giving way to the 626 pt table", () => {
    expect(repoColumns.map((column) => [column.id, column.width])).toEqual([
      ["Watching", 80],
      ["Repository", 170],
      ["Type", 90],
      ["Account", 120],
      ["Depth", 130],
      ["Source", 36],
    ]);
    expect(repoColumns.reduce((sum, column) => sum + (column.width ?? 0), 0)).toBe(626);
  });

  it("shows the server's text in each text column", () => {
    expect(repoColumns.map((column) => column.value?.(repo))).toEqual([
      undefined,
      "owner/name",
      "Private",
      "alice",
      "Changed files only",
      "Remote",
    ]);
  });
});

describe("add form state", () => {
  it("starts on the depth the status menu uses", () => {
    expect(defaultDepth(depths)).toBe("fullProject");
  });

  it("falls back to the first depth when none is marked", () => {
    expect(defaultDepth(depths.map((choice) => ({ ...choice, selected: false })))).toBe("changedOnly");
    expect(defaultDepth([])).toBe("");
  });

  it("forgets the repository just added but keeps the chosen depth", () => {
    const form: RepoFormState = {
      url: "https://github.com/owner/name",
      localPath: "/src/name",
      depth: "changedOnly",
      baseBranches: "main, release",
      isPrivate: true,
      accountIdentity: "github|api.github.com|alice",
    };

    expect(afterRepoAdded(form)).toEqual({
      url: "",
      localPath: "",
      depth: "changedOnly",
      baseBranches: "",
      isPrivate: false,
      accountIdentity: null,
    });
  });

  it("explains the chosen depth and nothing for an unknown one", () => {
    expect(depthExplanation(depths, "changedOnly")).toBe("Reads the changed files.");
    expect(depthExplanation(depths, "missing")).toBe("");
  });

  it("shows the account picker only when there is a real choice", () => {
    const alice = { identity: "a", title: "alice (github.com)" };
    const bob = { identity: "b", title: "bob (github.com)" };

    expect(showsAccountPicker([])).toBe(false);
    expect(showsAccountPicker([alice])).toBe(false);
    expect(showsAccountPicker([alice, bob])).toBe(true);
  });
});

describe("detection status", () => {
  const detection = (recognised: boolean, statusText: string | null, tone: string | null): DetectionDTO => ({
    recognised,
    isPrivate: false,
    accounts: [],
    selectedAccountIdentity: null,
    statusText,
    statusTone: tone,
  });
  const publicHint = { text: "Public repository: no credentials are used or sent.", tone: "info" };

  it("shows the public hint with the box unticked, even for an empty or unreadable URL", () => {
    expect(detectionLine(detection(false, null, null), false)).toEqual(publicHint);
    expect(detectionLine(detection(false, "Could not read that as a repository URL.", "error"), false)).toEqual(publicHint);
  });

  it("shows the public hint after the box is unticked on a Gitea URL, which the server still reports as private", () => {
    expect(detectionLine(detection(true, "Private repository: no saved account can reach the forge.", "warning"), false)).toEqual(
      publicHint,
    );
  });

  it("shows the orange no-account hint without a forge name when the box is ticked and the URL is not readable", () => {
    const expected = {
      text: "Private repository: no saved account can reach the forge. Add one in Accounts\u2026 first.",
      tone: "warning",
    };
    expect(detectionLine(detection(false, null, null), true)).toEqual(expected);
    expect(detectionLine(detection(false, "Could not read that as a repository URL.", "error"), true)).toEqual(expected);
  });

  it("passes the server's line through for a readable URL with the box ticked", () => {
    expect(detectionLine(detection(true, "Private repository: no saved account can reach GitHub.", "warning"), true)).toEqual({
      text: "Private repository: no saved account can reach GitHub.",
      tone: "warning",
    });
    expect(detectionLine(detection(true, 'Private repository: uses account "alice" on api.github.com.', "info"), true).tone).toBe(
      "info",
    );
  });
});

describe("notification notice", () => {
  it("explains a denied permission in red and an unasked one in the secondary colour", () => {
    expect(notificationNotice("denied")).toEqual({
      text: "Browser notifications are turned off for Karma Pro. Turn them on in your browser's site settings, then wait for the next new pull request.",
      tone: "error",
    });
    expect(notificationNotice("default")).toEqual({
      text: "Karma Pro has not asked the browser for permission to post notifications yet.",
      tone: "info",
    });
  });

  it("stays silent when granted or when the browser has no notifications", () => {
    expect(notificationNotice("granted")).toBeNull();
    expect(notificationNotice(null)).toBeNull();
  });
});
