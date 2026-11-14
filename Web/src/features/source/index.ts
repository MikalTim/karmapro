// The source viewer: one file with its syntax colours, clickable names and call sites, find bar, focus mode,
// flow arrows, note gutter, ML highlights, the function dataflow pane, the right-click menu and the definition popup.
//
// Public surface, as the main window uses it:
//   SourceViewer.svelte, props { onShown?: (path) => void, onFunctionSelected?: (path, functionName) => void }
//     display(path: string, line?: number): Promise<void>  shows a file; `line` is 1-based and is scrolled to
//     clear(): void                                         forgets the shown file
//     currentPath(): string | null                          the shown file's path, or null
//     find(): void                                          opens the find bar (Edit > Find in File)
//   openDefinitionWindow({ path, nameOffset }): Promise<void>  opens a definition popup for a name's offset
export { default as SourceViewer } from "./SourceViewer.svelte";
export { openDefinitionWindow } from "./definition";
