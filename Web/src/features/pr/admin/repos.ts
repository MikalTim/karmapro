// Rules of the Watched Repositories window: its table columns, the add form's state and the texts that
// depend on what the server reports. The component sends the form and renders the answers.
import type { Column } from "../../../lib/ui/Table.svelte";
import type { AccountChoiceDTO, DetectionDTO, PRChoiceDTO, RepoDTO } from "./dto";
import { statusLine, toneNamed, type StatusLine } from "./status";

// The Swift columns (80, 170, 90, 120, 130 and 110 pt) total 700 pt, wider than the 626 pt of the table inside
// the 660 pt window. AppKit never sets `columnAutoresizingStyle` or a column `resizingMask`, so the table uses the
// default last-column-only style: only the last column gives way when the table frame is narrower than the
// columns, and the first five keep their widths. That leaves 626 - 590 = 36 pt for Source.
export const repoColumns: Column<RepoDTO>[] = [
  { id: "Watching", title: "Watching", width: 80 },
  { id: "Repository", title: "Repository", width: 170, value: (repo) => repo.repoSlug },
  { id: "Type", title: "Type", width: 90, value: (repo) => repo.typeText },
  { id: "Account", title: "Account", width: 120, value: (repo) => repo.accountText },
  { id: "Depth", title: "Depth", width: 130, value: (repo) => repo.depthTitle },
  { id: "Source", title: "Source", width: 36, value: (repo) => repo.sourceText },
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

const PUBLIC_HINT = "Public repository: no credentials are used or sent.";
const NO_FORGE_ACCOUNT_HINT = "Private repository: no saved account can reach the forge. Add one in Accounts\u2026 first.";

/**
 * The status line after the URL or the Private box was committed. `urlFieldChanged` and `privateToggled` always end
 * in `updatePrivacyHint`, which rewrites the line even when the field is empty or cannot be read, so the line is
 * never left as it was. With the box unticked it is the public hint. With it ticked, a readable URL gets the
 * server's account-specific text, and an unreadable one the orange "no saved account" hint that names no forge.
 *
 * `isPrivate` is the state of the box after the commit. It is passed in because the server's reply always treats
 * a Gitea host as private, while only a typed URL (never a click on the box) ticks the box in AppKit.
 */
export function detectionLine(detection: DetectionDTO, isPrivate: boolean): StatusLine {
  if (!isPrivate) return statusLine(PUBLIC_HINT);
  if (detection.recognised) return statusLine(detection.statusText ?? "", toneNamed(detection.statusTone));
  return statusLine(NO_FORGE_ACCOUNT_HINT, "warning");
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
