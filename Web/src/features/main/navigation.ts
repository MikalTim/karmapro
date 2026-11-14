// What the feature windows need from the main window without importing it (the main window imports
// every feature, so the reverse import would be circular). `MainWindow.svelte` installs the real
// actions once it is mounted; until then the calls do nothing.

export interface MainWindowActions {
  /** `MainWindowController.showFile(at:line:)`: shows the file in the source viewer, scrolled to `line` (1-based). */
  showFile(path: string, line?: number): void;
  /** `MainWindowController.promptForDirectory`: the Browse panel, then opens the chosen folder as the project. */
  promptForDirectory(): Promise<void>;
}

let actions: MainWindowActions | null = null;

export function installMainWindowActions(installed: MainWindowActions): void {
  actions = installed;
}

export function showFileInMainWindow(path: string, line?: number): void {
  actions?.showFile(path, line);
}

export async function promptForDirectory(): Promise<void> {
  await actions?.promptForDirectory();
}
