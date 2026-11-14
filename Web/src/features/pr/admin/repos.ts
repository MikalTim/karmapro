// Rules of the Watched Repositories window: its table columns, the add form's state and the texts that
// depend on what the server reports. The component sends the form and renders the answers.
import type { Column } from "../../../lib/ui/Table.svelte";
import type { AccountChoiceDTO, DetectionDTO, PRChoiceDTO, RepoDTO } from "./dto";
import { statusLine, toneNamed, type StatusLine } from "./status";

// The Watching column is drawn with a checkbox by the component; the others read their text here.
export const repoColumns: Column<RepoDTO>[] = [
  { id: "Watching", title: "Watching", width: 80 },
  { id: "Repository", title: "Repository", width: 170, value: (repo) => repo.repoSlug },
  { id: "Type", title: "Type", width: 90, value: (repo) => repo.typeText },
  { id: "Account", title: "Account", width: 120, value: (repo) => repo.accountText },
  { id: "Depth", title: "Depth", width: 130, value: (repo) => repo.depthTitle },
  { id: "Source", title: "Source", width: 110, value: (repo) => repo.sourceText },
];

export interface RepoFormState {
  url: string;
  localPath: string;
  depth: string;
  baseBranches: string;
  isPrivate: boolean;
  accountIdentity: string | null;
}

/** The depth the form starts on: the one the status menu uses (`selected`), otherwise the first. */
export function defaultDepth(choices: PRChoiceDTO[]): string {
  return (choices.find((choice) => choice.selected) ?? choices[0])?.value ?? "";
}

/** After a repository is added the form forgets it, but keeps the depth, as the AppKit form does. */
export function afterRepoAdded(form: RepoFormState): RepoFormState {
  return { ...form, url: "", localPath: "", baseBranches: "", isPrivate: false, accountIdentity: null };
}

/** The explanation under Scan depth, for the depth now chosen. */
export function depthExplanation(choices: PRChoiceDTO[], value: string): string {
  return choices.find((choice) => choice.value === value)?.explanation ?? "";
}

/** The account picker appears only when there is a real choice. With one account the choice is made for the user. */
export function showsAccountPicker(choices: AccountChoiceDTO[]): boolean {
  return choices.length > 1;
}

/** The status line for a detection reply. An empty URL has no text, so the line is cleared. */
export function detectionLine(detection: DetectionDTO): StatusLine {
  return detection.statusText ? statusLine(detection.statusText, toneNamed(detection.statusTone)) : statusLine("");
}

/**
 * The notice that explains why no notifications appear. It replaces the macOS notification row: `permission` is
 * the browser's `Notification.permission`, or null where the browser has no notifications. Only states the user
 * can change are shown.
 */
export function notificationNotice(permission: string | null): StatusLine | null {
  switch (permission) {
    case "denied":
      return statusLine(
        "Browser notifications are turned off for Karma Pro. Turn them on in your browser's site settings, then wait for the next new pull request.",
        "error",
      );
    case "default":
      return statusLine("Karma Pro has not asked the browser for permission to post notifications yet.");
    default:
      return null;
  }
}
