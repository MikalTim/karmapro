// JSON shapes of the pull request admin routes (Sources/KarmaServer/PRAdminRoutes.swift), mirroring the
// Swift DTOs in Sources/KarmaCore/service/PRAdminService.swift and PRService.swift. A Swift value that is
// nil may be left out of the JSON, so nullable fields are optional as well as `| null`.

export interface ProviderDTO {
  id: string;
  name: string;
  tokenPlaceholder: string;
  hostPlaceholder: string;
  hostEnabled: boolean;
  defaultHost: string;
}

export interface AccountDTO {
  identity: string;
  provider: string;
  providerName: string;
  host: string;
  username: string;
  /** "stored", "missing" or "not checked". */
  tokenStatus: string;
}

export interface AccountsDTO {
  accounts: AccountDTO[];
  providers: ProviderDTO[];
}

export interface AccountChoiceDTO {
  identity: string;
  title: string;
}

/** A one-line result for a status line. `success` false means the line is an error. */
export interface StatusDTO {
  text: string;
  success: boolean;
}

/** The question asked before a destructive action. */
export interface ConfirmDTO {
  title: string;
  message: string;
  confirmTitle: string;
  cancelTitle: string;
}

export interface PRChoiceDTO {
  value: string;
  title: string;
  explanation?: string | null;
  selected: boolean;
}

export interface RepoDTO {
  id: string;
  provider: string;
  webURL: string;
  repoSlug: string;
  localPath?: string | null;
  visibility: string;
  typeText: string;
  depth: string;
  depthTitle: string;
  baseBranches: string[];
  enabled: boolean;
  watchingTooltip: string;
  accountIdentity?: string | null;
  accountText: string;
  accountChoices: AccountChoiceDTO[];
  sourceText: string;
}

export interface CacheDTO {
  bytes: number;
  label: string;
  path: string;
}

export interface RepositoriesDTO {
  repos: RepoDTO[];
  depthChoices: PRChoiceDTO[];
  pollErrorDetail?: string | null;
  cache: CacheDTO;
}

/** What the add form shows for a URL being typed. `statusTone` is "error", "warning" or "info". */
export interface DetectionDTO {
  recognised: boolean;
  isPrivate: boolean;
  provider?: string | null;
  webURL?: string | null;
  repoSlug?: string | null;
  accounts: AccountChoiceDTO[];
  selectedAccountIdentity?: string | null;
  statusText?: string | null;
  statusTone?: string | null;
}

export interface CachePromptDTO {
  prompt: ConfirmDTO | null;
}
