// The open project as the server reports it (`KarmaWorkspace`): its folder, the
// index build that runs after a folder opens, and the open bug count. Every tab
// shows the same project, so this state is shared by the whole page.
import { trackJob } from "../../lib/jobs";
import { baseName } from "./paths";
import { fetchAppInfo, fetchProject, openProject } from "./project";

export interface IndexBuild {
  id: string;
  projectName: string;
  /** False until the first progress report; the window says "Indexing …" before that. */
  progressed: boolean;
  done: number;
  total: number;
  /** When the build was first followed, for the time-left estimate. */
  startedAt: number;
}

export const projectState = $state<{
  root: string | null;
  name: string | null;
  openBugCount: number;
  index: IndexBuild | null;
}>({
  root: null,
  name: null,
  openBugCount: 0,
  index: null,
});

/** The index job being followed. A job reported twice is followed once. */
let followedJob: string | null = null;

export function followIndex(id: string, projectName: string): void {
  if (followedJob === id) return;
  followedJob = id;
  projectState.index = { id, projectName, progressed: false, done: 0, total: 0, startedAt: Date.now() };
  const finish = () => {
    if (projectState.index?.id === id) projectState.index = null;
  };
  trackJob(id, (progress) => {
    const current = projectState.index;
    if (!current || current.id !== id) return;
    projectState.index = { ...current, progressed: true, done: progress.done, total: progress.total };
  }).promise.then(finish, finish);
}

/** Reads the open project from the server and follows its index build while it runs. */
export async function refreshProject(): Promise<void> {
  const info = await fetchProject();
  projectState.root = info.root ?? null;
  projectState.name = info.name ?? null;
  if (projectState.root === null) projectState.index = null;
  if (info.root && info.indexJobId && info.indexState === "building") {
    followIndex(info.indexJobId, info.name ?? baseName(info.root));
  }
}

/** Opens a folder as the project. The index build it starts is followed at once. */
export async function openProjectFolder(path: string): Promise<void> {
  const started = await openProject(path);
  followIndex(started.jobId, baseName(path));
}

export async function loadBugCount(): Promise<void> {
  projectState.openBugCount = (await fetchAppInfo()).openBugCount;
}
