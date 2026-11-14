// The entry-point finder and the debugger simulation windows.
import { api } from "../../../lib/api";
import { showAlert } from "../../../lib/ui/alert.svelte";
import { asWindowContent, openWindow, setWindowTitle } from "../../../lib/ui/windows.svelte";
import { promptForDirectory } from "../../main/navigation";
import EntryPointsWindow from "./EntryPointsWindow.svelte";
import { ENTRY_POINTS_TITLE } from "./entryPointsModel";
import { beginEntrySearch, closeEntrySearch } from "./entryPointsSession.svelte";
import SimDebugWindow from "./SimDebugWindow.svelte";
import { loadSimulation, stopPlaying } from "./simSession.svelte";

interface ProjectInfo {
  root?: string | null;
}

/** Opens the entry-point finder and searches the open project (`showFindEntries`). */
export async function openEntryPointsWindow(): Promise<void> {
  const project = await api<ProjectInfo>("GET", "/api/project");
  if (!project.root) {
    const choice = await showAlert({
      message: "No Folder Open",
      informative: "Open a source folder before finding entry points.",
      buttons: ["Open Folder", "Cancel"],
    });
    if (choice === 0) await promptForDirectory();
    return;
  }
  openWindow({
    key: "EntryPointsWindow",
    title: ENTRY_POINTS_TITLE,
    width: 1180,
    height: 760,
    minWidth: 820,
    minHeight: 480,
    escCloses: true,
    component: asWindowContent(EntryPointsWindow),
    onClose: closeEntrySearch,
  });
  // The window searches again on every open, as `begin(projectRoot:sourceIndex:)` does.
  beginEntrySearch();
}

/** Opens the debugger on `functionName` of the file at `path`, or re-points the open one (`showSimulation`). */
export async function openSimDebugWindow(target: { path: string; functionName: string }): Promise<void> {
  const loaded = await loadSimulation(target.path, target.functionName);
  if (!loaded) return;
  const id = openWindow({
    key: "SimDebugWindow",
    title: loaded.title,
    width: 960,
    height: 640,
    minWidth: 760,
    minHeight: 480,
    escCloses: true,
    component: asWindowContent(SimDebugWindow),
    onClose: stopPlaying,
  });
  setWindowTitle(id, loaded.title);
}
