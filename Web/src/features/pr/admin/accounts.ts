// Rules of the Pull Request Accounts window: its table columns, the form state and the explanation text.
// The window component renders what these return and leaves validation to the server.
import type { Column } from "../../../lib/ui/Table.svelte";
import type { AccountDTO, ProviderDTO } from "./dto";

export const accountColumns: Column<AccountDTO>[] = [
  { id: "Provider", title: "Provider", width: 130, value: (account) => account.providerName },
  { id: "Host", title: "Host", width: 160, value: (account) => account.host },
  { id: "Account", title: "Account", width: 150, value: (account) => account.username },
  { id: "Token", title: "Token", width: 80, value: (account) => account.tokenStatus },
];

export interface AccountFormState {
  providerId: string;
  host: string;
  username: string;
  token: string;
}

/**
 * Whether a typed host should be sent to move the provider list. Only an editable host field asks, because
 * AppKit ignores typing in the disabled Bitbucket host, and an empty host names no forge.
 */
export function asksForProvider(provider: ProviderDTO | undefined, host: string): boolean {
  return provider?.hostEnabled === true && host.trim() !== "";
}

/** After a save the token is cleared so it is not left on screen; provider, host and username stay for the next account. */
export function afterSave(form: AccountFormState): AccountFormState {
  return { ...form, token: "" };
}

const LINUX_STORAGE =
  "Tokens are stored in a file that only your user account can read (mode 0600) and are never written to Karma Pro's settings or included in a report.";
const MACOS_STORAGE =
  "Tokens are stored in your macOS Keychain and are never written to Karma Pro's settings or included in a report.";

/**
 * The explanation at the top of the window. Only the storage sentence depends on the platform: on macOS
 * tokens go to the Keychain, and elsewhere the server keeps them in a file readable only by its user.
 */
export function accountsExplanation(platform: string | null): string[] {
  const storage = platform === "linux" ? LINUX_STORAGE : MACOS_STORAGE;
  return [
    "Read-only credentials for private repositories.",
    `Karma Pro never approves, comments on, or posts to a pull request, so a token with read-only scope is enough. ${storage}`,
    "Public repositories need no account at all — you only need one for repositories you mark private.",
  ];
}
