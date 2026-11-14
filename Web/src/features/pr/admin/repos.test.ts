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
  it("has the six AppKit columns with their widths", () => {
    expect(repoColumns.map((column) => [column.id, column.width])).toEqual([
      ["Watching", 80],
      ["Repository", 170],
      ["Type", 90],
      ["Account", 120],
      ["Depth", 130],
      ["Source", 110],
    ]);
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
  const detection = (statusText: string | null, statusTone: string | null): DetectionDTO => ({
    recognised: statusText !== null,
    isPrivate: false,
    accounts: [],
    selectedAccountIdentity: null,
    statusText,
    statusTone,
  });

  it("clears the line while the URL is empty", () => {
    expect(detectionLine(detection(null, null))).toEqual({ text: "", tone: "info" });
  });

  it("shows an unreadable URL in red and a missing account in orange", () => {
    expect(detectionLine(detection("Could not read that as a repository URL.", "error")).tone).toBe("error");
    expect(detectionLine(detection("Private repository: no saved account can reach GitHub.", "warning")).tone).toBe(
      "warning",
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
