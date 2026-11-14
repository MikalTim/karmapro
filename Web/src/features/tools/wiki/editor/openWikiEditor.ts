// Opens the page editor, the window AppKit keeps one of per page (`editors[slug]`).
// Opening a page that is already open focuses its window. The following of links lives
// here, not in the component, so the component does not import its own opener.
import { api, withQuery } from "../../../../lib/api";
import { asWindowContent, closeWindow, openWindow, windowStore } from "../../../../lib/ui/windows.svelte";
import { editorWindowKey, type WikiPageSummary, type WikiResolution } from "./editorModel";
import { editorMayClose } from "./editorSessions";
import WikiEditorWindow from "./WikiEditorWindow.svelte";

export function openWikiEditorWindow(options: { slug: string }): void {
  const { slug } = options;
  openWindow({
    key: editorWindowKey(slug),
    title: "Wiki Page",
    width: 820,
    height: 620,
    minWidth: 520,
    minHeight: 360,
    escCloses: true,
    component: asWindowContent(WikiEditorWindow),
    props: { slug, followLink: followWikiLink },
    canClose: () => editorMayClose(slug),
  });
}

/**
 * Closes the open editor of a page, saving its edits first. Resolves false when that editor
 * refuses to close (its save failed), so the caller must not change the page under it.
 * Resolves true when it closed, or when none was open.
 */
export async function closeWikiEditorWindow(slug: string): Promise<boolean> {
  const key = editorWindowKey(slug);
  const open = windowStore.list.find((entry) => entry.spec.key === key);
  return open ? closeWindow(open.id) : true;
}

/**
 * Follows a wiki link (AppKit's `onNavigate`): opens the page the target names, creating
 * it when there is none. The current editor closes first, saving its edits. When it
 * refuses to close because the save failed, nothing opens.
 */
async function followWikiLink(target: string, fromWindowId: number): Promise<void> {
  const resolution = await api<WikiResolution>("GET", withQuery("/api/wiki/resolve", { target }));
  const slug = resolution.slug ?? (await api<WikiPageSummary>("POST", "/api/wiki", { title: target })).slug;
  if (await closeWindow(fromWindowId)) openWikiEditorWindow({ slug });
}
