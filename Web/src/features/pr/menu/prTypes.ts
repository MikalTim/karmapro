// The pull request DTOs the server sends (`Sources/KarmaCore/service/PRService.swift`). The field names are
// the JSON keys. Optional Swift properties are absent from the JSON when they are nil.

export interface PRChoice {
  /** The value to send back to select this option. */
  value: string;
  title: string;
  explanation?: string;
  selected: boolean;
}

export interface PRItem {
  repoID: string;
  repoSlug: string;
  prID: number;
  number: number;
  title: string;
  author: string;
  headBranch: string;
  baseBranch: string;
  webURL: string;
  isNew: boolean;
}

export interface PRReviewBanner {
  /** "PR #12 Fix login". */
  title: string;
  /** "Reviewing PR #12 · owner/name · 3 files". */
  subtitle: string;
  /** The repository's web address, shown as the tooltip. */
  detail: string;
  showAllAvailable: boolean;
}

/** Everything the pull request menu and the review banner show. */
export interface PRState {
  monitoringEnabled: boolean;
  pollingIntervalMinutes: number;
  depthChoices: PRChoice[];
  notifyChoices: PRChoice[];
  pollError?: string;
  pollErrorDetail?: string;
  items: PRItem[];
  repoCount: number;
  gitAvailable: boolean;
  gitUnavailableMessage?: string;
  review?: PRReviewBanner;
}

export type PRDiffKind = "hunk" | "added" | "removed" | "meta" | "context";

export interface PRDiffLine {
  text: string;
  kind: PRDiffKind;
  /** An added line the heuristic wants read closely. */
  suspicious: boolean;
}

export interface PRChangedFile {
  path: string;
  /** Absolute path in the review checkout; opening it shows the file in the source viewer. */
  absolutePath: string;
  /** The picker's text: "M  src/a.c" or "A  src/b.c (added)". */
  title: string;
  summary: string;
  lines: PRDiffLine[];
}

export interface PRChanges {
  windowTitle: string;
  files: PRChangedFile[];
  emptyTitle: string;
  emptyMessage: string;
}

export interface PRReport {
  windowTitle: string;
  markdown: string;
  suggestedName: string;
  statusText: string;
  saveMessage: string;
}

export interface PRScanPrompt {
  title: string;
  message: string;
  /** In button order: "headOnly", "both", "none". */
  choices: PRChoice[];
}

export interface PRAbout {
  title: string;
  message: string;
}

/** One alert for a new pull request, as the `pr.notify` event carries it. */
export interface PRNotification {
  repoID: string;
  prID: number;
  /** "owner/name #12". */
  title: string;
  body: string;
}

export interface PRNotifyEvent {
  items: PRNotification[];
  allowSound: boolean;
}
