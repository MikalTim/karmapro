// Opens the AI Assistant window (`MainWindowController.showAIAssistant`). The
// window is a singleton: opening it again brings it forward and renews its title.
import { api } from "../../../lib/api";
import { showAlert } from "../../../lib/ui/alert.svelte";
import { asWindowContent, openWindow, setWindowTitle } from "../../../lib/ui/windows.svelte";
import { promptForDirectory } from "../../main/navigation";
import AIWindow from "./AIWindow.svelte";
import { ask, startAssistant, stopIfRunning } from "./assistantStore.svelte";

/** The part of `GET /api/project` the title and the project check need. */
interface ProjectSummary {
  root?: string | null;
  name?: string | null;
}

/**
 * Opens the window and, with `prompt`, sends that question as the Send button
 * would. Without an open project it offers to open one instead, as AppKit does.
 */
export async function openAIWindow(options?: { prompt?: string }): Promise<void> {
  startAssistant();
  const project = await api<ProjectSummary>("GET", "/api/project");
  if (!project.root) {
    const choice = await showAlert({
      message: "No Project Selected",
      informative: "You need to first select a project before using the AI assistant.",
      buttons: ["Open Folder", "Cancel"],
    });
    if (choice === 0) await promptForDirectory();
    return;
  }
  const title = `AI Assistant \u2014 ${project.name ?? ""}`;
  const id = openWindow({
    key: "AIWindow",
    title,
    width: 880,
    height: 680,
    minWidth: 720,
    minHeight: 520,
    escCloses: true,
    component: asWindowContent(AIWindow),
    onClose: stopIfRunning,
  });
  setWindowTitle(id, title);
  if (options?.prompt !== undefined) await ask(options.prompt);
}
