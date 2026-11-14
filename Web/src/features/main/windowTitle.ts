// The main window's title (`MainWindowController.updateWindowTitle`) and the page
// title, which stands in for the Dock badge of open bugs.

export const APP_TITLE = "Karma Pro";

/** "<project> Project", with the shown file's name in parentheses after it. */
export function mainWindowTitle(projectName: string | null, fileName: string | null): string {
  if (projectName === null) return APP_TITLE;
  const project = `${projectName} Project`;
  return fileName === null ? project : `${project} (${fileName})`;
}

/** The browser tab title: the count in front while any bug is open, as the Dock badge shows it. */
export function pageTitle(windowTitle: string, openBugCount: number): string {
  return openBugCount > 0 ? `(${openBugCount}) ${windowTitle}` : windowTitle;
}
