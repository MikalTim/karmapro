// The sidebar's filter and loaded tree (`FileTreeViewController`). The toolbar
// changes the language and the search text, and the tree shows the reply. Both
// read this state, so they stay in step without knowing about each other.
import { fetchLanguages, fetchTree, messageOf, type ProjectTreeDTO } from "./project";

export const ALL_LANGUAGES = "All Languages";

export const treeState = $state<{
  languages: string[];
  language: string;
  query: string;
  tree: ProjectTreeDTO | null;
  error: string | null;
}>({
  languages: [],
  language: ALL_LANGUAGES,
  query: "",
  tree: null,
  error: null,
});

/** Only the newest request may write the tree, so a slow reply cannot overwrite a newer one. */
let latestRequest = 0;

export async function reloadTree(): Promise<void> {
  const request = ++latestRequest;
  try {
    const tree = await fetchTree(treeState.language, treeState.query);
    if (request !== latestRequest) return;
    treeState.tree = tree;
    treeState.error = null;
  } catch (error) {
    if (request !== latestRequest) return;
    treeState.error = messageOf(error);
  }
}

export async function loadLanguages(): Promise<void> {
  treeState.languages = await fetchLanguages();
}

export function setLanguage(name: string): void {
  treeState.language = name;
  void reloadTree();
}
