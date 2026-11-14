// The main window's calls to the project and application routes
// (`ProjectRoutes.swift`, `AppRoutes.swift`, `InfrastructureRoutes.swift`).
import { api, withQuery } from "../../lib/api";

export type IndexState = "none" | "building" | "ready" | "cancelled" | "failed";

/** `ProjectInfoDTO`. The server omits a nil optional field, so those are optional here. */
export interface ProjectInfo {
  root?: string | null;
  name?: string | null;
  indexJobId?: string | null;
  indexState: IndexState;
  reviewing: boolean;
}

/** `FileNodeDTO`. `badge` is "A" or "M" beside a file the open pull request changes. */
export interface FileNodeDTO {
  name: string;
  path: string;
  isDirectory: boolean;
  badge?: string | null;
  children?: FileNodeDTO[] | null;
}

/** `ProjectTreeDTO`: `root` for a tree reply, `matches` for a search reply. */
export interface ProjectTreeDTO {
  root?: FileNodeDTO | null;
  matches?: FileNodeDTO[] | null;
}

/** `AppInfoDTO`. */
export interface AppInfo {
  version: string;
  platform: string;
  resourcesFound: boolean;
  tokenRequired: boolean;
  openBugCount: number;
}

export function fetchProject(): Promise<ProjectInfo> {
  return api<ProjectInfo>("GET", "/api/project");
}

export function openProject(path: string): Promise<{ jobId: string }> {
  return api<{ jobId: string }>("POST", "/api/project/open", { path });
}

export function fetchLanguages(): Promise<string[]> {
  return api<string[]>("GET", "/api/languages");
}

export function fetchTree(language: string, query: string): Promise<ProjectTreeDTO> {
  return api<ProjectTreeDTO>("GET", withQuery("/api/project/tree", { language, query }));
}

export function fetchAppInfo(): Promise<AppInfo> {
  return api<AppInfo>("GET", "/api/app/info");
}

export async function quitApp(): Promise<void> {
  await api("POST", "/api/app/quit");
}

/** The text to show for a failed request: the server's `error` field for an API failure. */
export function messageOf(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
