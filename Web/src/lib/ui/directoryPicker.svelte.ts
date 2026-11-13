// NSOpenPanel for choosing a folder (or a file) on the machine the server runs
// on. The browser cannot see that file system, so the picker lists it through
// GET /api/fs/list.
export interface PickerOptions {
  /** NSOpenPanel.message, shown above the list. */
  message?: string;
  /** NSOpenPanel.prompt: the title of the confirm button. Defaults to "Open". */
  prompt?: string;
  /** Allow choosing files instead of folders. */
  files?: boolean;
  /** Folder to start in. Defaults to the last chosen one, then the home folder. */
  startPath?: string;
}

export interface PendingPicker {
  options: PickerOptions;
  resolve: (path: string | null) => void;
}

export const pickerState = $state<{ pending: PendingPicker | null }>({ pending: null });

const LAST_KEY = "karma.lastPickedPath";

export function lastPickedPath(): string | null {
  return typeof localStorage === "undefined" ? null : localStorage.getItem(LAST_KEY);
}

export function rememberPickedPath(path: string): void {
  localStorage.setItem(LAST_KEY, path);
}

/** Opens the picker. Resolves with the chosen absolute path, or null when cancelled. */
export function pickPath(options: PickerOptions = {}): Promise<string | null> {
  const { promise, resolve } = Promise.withResolvers<string | null>();
  pickerState.pending = { options, resolve };
  return promise;
}

export function finishPicker(path: string | null): void {
  const pending = pickerState.pending;
  pickerState.pending = null;
  if (pending && path) rememberPickedPath(path);
  pending?.resolve(path);
}
