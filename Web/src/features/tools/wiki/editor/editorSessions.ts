// The open page editors, by slug. The window manager asks an editor to save before it
// closes (AppKit's windowShouldClose and windowWillClose). An editor that has not
// loaded yet has nothing to save, so it is not registered.
export interface EditorSession {
  /** Saves unsaved edits. Resolves false when the save failed, which keeps the window open. */
  saveIfDirty: () => Promise<boolean>;
}

const sessions = new Map<string, EditorSession>();

export function registerEditorSession(slug: string, session: EditorSession): void {
  sessions.set(slug, session);
}

export function unregisterEditorSession(slug: string): void {
  sessions.delete(slug);
}

/** Whether the page's window may close now. Saves its edits first. */
export async function editorMayClose(slug: string): Promise<boolean> {
  const session = sessions.get(slug);
  return session ? session.saveIfDirty() : true;
}
