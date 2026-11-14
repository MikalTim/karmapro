<script lang="ts">
  // The main window (`MainWindowController`): the menu bar, the toolbar, the pull
  // request banner, and the panes file tree | source viewer | flow panel. It keeps the
  // file open in the source viewer, the back and forward history and the window
  // title, and installs the actions the other windows call through `navigation.ts`.
  import { onMount, untrack } from "svelte";
  import { on } from "../../lib/events";
  import MenuBar from "../../lib/ui/MenuBar.svelte";
  import type { MenuItem } from "../../lib/ui/contextMenu.svelte";
  import { pickPath } from "../../lib/ui/directoryPicker.svelte";
  import { showAlert } from "../../lib/ui/alert.svelte";
  import { FlowPanel } from "../graphs";
  import { SourceViewer } from "../source";
  import { PRBanner, PRMenu, reviewState } from "../pr";
  import { openAboutWindow, openHelpWindow, openMCPSettingsWindow, updateMenuItems } from "../app";
  import { openLicensingWindow, openPackageScanWindow } from "../scan";
  import { reportError } from "./errors";
  import FileTree from "./FileTree.svelte";
  import IndexBuildSheet from "./IndexBuildSheet.svelte";
  import MainToolbar from "./MainToolbar.svelte";
  import { buildMainMenus } from "./menus";
  import { installMainWindowActions } from "./navigation";
  import { DIVIDER_WIDTH, FLOW_WIDTH, TREE_WIDTH, clampFlowWidth, clampTreeWidth } from "./layout";
  import {
    EMPTY_HISTORY,
    canGoBack,
    canGoForward,
    historyMenuEntries,
    jumpToHistory,
    recordFile,
    stepHistory,
    type FileHistory,
  } from "./history";
  import { baseName } from "./paths";
  import { mainWindowTitle, pageTitle } from "./windowTitle";
  import { isMacPlatform, shortcutAction, type ShortcutAction } from "./shortcuts";
  import { loadBugCount, openProjectFolder, projectState, refreshProject } from "./projectState.svelte";
  import { loadLanguages, reloadTree } from "./treeState.svelte";
  import { quitApp } from "./project";

  interface ViewerHandle {
    display(path: string, line?: number): Promise<void>;
    clear(): void;
    find(): void;
  }

  interface FlowSelection {
    path: string;
    functionName: string;
  }

  const isMac = isMacPlatform(navigator);

  let viewer = $state<ViewerHandle>();
  let currentFile = $state<string | null>(null);
  let flowSelection = $state<FlowSelection | null>(null);
  let history = $state<FileHistory>(EMPTY_HISTORY);
  /** The review's title while no file is open, as AppKit sets the window title to it. */
  let reviewTitle = $state<string | null>(null);
  let treeVisible = $state(true);
  let treeWidth = $state(TREE_WIDTH.initial);
  let flowWidth = $state(FLOW_WIDTH.initial);
  let panesWidth = $state(0);

  const reviewHeading = $derived(reviewState.value?.review?.title ?? null);
  // Opening a file replaces the review's title with the file name, and a new review
  // brings its own title back.
  $effect(() => {
    reviewTitle = reviewHeading;
  });

  const windowTitle = $derived(
    reviewTitle ?? mainWindowTitle(projectState.name, currentFile === null ? null : baseName(currentFile)),
  );
  $effect(() => {
    document.title = pageTitle(windowTitle, projectState.openBugCount);
  });

  // The pull request's "Show All" toggles the tree's pruning on the server; a change in
  // whether it is offered means the tree must be read again.
  const showAllAvailable = $derived(reviewState.value?.review?.showAllAvailable ?? null);
  $effect(() => {
    void showAllAvailable;
    untrack(() => void reloadTree());
  });

  /** Shows a file in the source viewer. The history and the title follow from `viewerShown`. */
  function showFile(path: string, line?: number): void {
    flowSelection = null;
    void viewer?.display(path, line);
  }

  function viewerShown(path: string): void {
    currentFile = path;
    reviewTitle = null;
    flowSelection = null;
    history = recordFile(history, path);
  }

  function viewerFunctionSelected(path: string, functionName: string): void {
    flowSelection = { path, functionName };
  }

  function navigate(delta: -1 | 1): void {
    const next = stepHistory(history, delta);
    if (next === null) return;
    history = next;
    showFile(next.entries[next.index], 1);
  }

  function jumpTo(index: number): void {
    const next = jumpToHistory(history, index);
    if (next === null) return;
    history = next;
    showFile(next.entries[next.index], 1);
  }

  function historyItems(): MenuItem[] {
    const entries = historyMenuEntries(history);
    if (entries.length === 0) return [{ title: "No Files Opened Yet", disabled: true }];
    return entries.map((entry) => ({ title: entry.name, action: () => jumpTo(entry.index) }));
  }

  /** A folder was opened (or closed) on the server: the history and the viewer start again. */
  async function workspaceChanged(): Promise<void> {
    history = EMPTY_HISTORY;
    currentFile = null;
    flowSelection = null;
    viewer?.clear();
    try {
      await refreshProject();
    } catch (error) {
      reportError(error);
      return;
    }
    await reloadTree();
  }

  /** Open Folder (`promptForDirectory`): the Browse panel, then the folder becomes the project. */
  async function promptForDirectory(): Promise<void> {
    const picked = await pickPath({ message: "Choose a folder to browse its source code", prompt: "Browse" });
    if (picked === null) {
      await directoryRequiredAlert();
      return;
    }
    try {
      await openProjectFolder(picked);
    } catch (error) {
      reportError(error);
    }
  }

  async function directoryRequiredAlert(): Promise<void> {
    const choice = await showAlert({
      message: "No Folder Selected",
      informative: "A folder is required to browse source code.",
      buttons: ["Choose Folder", "Quit", "Cancel"],
    });
    if (choice === 0) await promptForDirectory();
    else if (choice === 1) await quitNow();
  }

  async function confirmQuit(): Promise<void> {
    const choice = await showAlert({
      message: "Are you sure you want to quit?",
      informative: "Closing the Karma Pro window will quit the app.",
      style: "warning",
      buttons: ["Quit", "Cancel"],
    });
    if (choice === 0) await quitNow();
  }

  async function quitNow(): Promise<void> {
    try {
      await quitApp();
    } catch (error) {
      reportError(error);
    }
  }

  function findInFile(): void {
    viewer?.find();
  }

  // The browser keeps the native editing of focused fields, so the Edit menu acts on
  // the last editable element the user focused, as AppKit acts on the first responder.
  let lastEditable: HTMLElement | null = null;

  function rememberEditable(event: FocusEvent): void {
    const target = event.target;
    if (target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement) lastEditable = target;
    else if (target instanceof HTMLElement && target.isContentEditable) lastEditable = target;
  }

  function editCommand(command: "undo" | "redo" | "cut" | "copy" | "delete" | "selectAll"): void {
    lastEditable?.focus();
    document.execCommand(command);
  }

  async function pasteClipboard(): Promise<void> {
    try {
      const text = await navigator.clipboard.readText();
      lastEditable?.focus();
      document.execCommand("insertText", false, text);
    } catch (error) {
      reportError(error);
    }
  }

  /** Scan project's packages: the menu's own alert when no folder is open. */
  function scanPackages(): void {
    if (projectState.root === null) {
      void showAlert({
        message: "No Project Folder Open",
        informative:
          "Open a project folder first so its dependency manifests and lockfiles can be detected, then run the package scan again.",
        style: "warning",
        buttons: ["OK"],
      });
      return;
    }
    openPackageScanWindow();
  }

  const menus = buildMainMenus({
    isMac,
    updateItems: updateMenuItems,
    actions: {
      about: openAboutWindow,
      settings: openMCPSettingsWindow,
      quit: () => void confirmQuit(),
      help: openHelpWindow,
      undo: () => editCommand("undo"),
      redo: () => editCommand("redo"),
      cut: () => editCommand("cut"),
      copy: () => editCommand("copy"),
      paste: () => void pasteClipboard(),
      delete: () => editCommand("delete"),
      selectAll: () => editCommand("selectAll"),
      find: findInFile,
      scanLicenses: openLicensingWindow,
      scanPackages,
    },
  });

  const shortcutTargets: Record<ShortcutAction, () => void> = {
    find: findInFile,
    settings: openMCPSettingsWindow,
    licensing: openLicensingWindow,
    packages: scanPackages,
    help: openHelpWindow,
    quit: () => void confirmQuit(),
  };

  /** Inside a feature window ⌘F belongs to that window, as AppKit sends it to the key window only. */
  function insideWindow(target: EventTarget | null): boolean {
    return target instanceof Element && target.closest('[role="dialog"]') !== null;
  }

  function keydown(event: KeyboardEvent): void {
    const action = shortcutAction(event, isMac);
    if (action === null) return;
    if (action === "find" && insideWindow(event.target)) return;
    event.preventDefault();
    shortcutTargets[action]();
  }

  /** Drags a divider; the panes keep the widths `layout.ts` allows. */
  function dragDivider(which: "tree" | "flow", event: PointerEvent): void {
    event.preventDefault();
    const startX = event.clientX;
    const startWidth = which === "tree" ? treeWidth : flowWidth;
    const move = (moved: PointerEvent) => {
      const delta = moved.clientX - startX;
      if (which === "tree") {
        treeWidth = clampTreeWidth(startWidth + delta, panesWidth, flowWidth);
      } else {
        const left = treeVisible ? treeWidth + DIVIDER_WIDTH : 0;
        flowWidth = clampFlowWidth(startWidth - delta, panesWidth, left);
      }
    };
    const up = () => {
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
    };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
  }

  async function startup(): Promise<void> {
    try {
      await Promise.all([loadLanguages(), loadBugCount()]);
    } catch (error) {
      reportError(error);
    }
    await workspaceChanged();
  }

  // Installed while the window is created, so the launch's Open Folder panel can use
  // it as soon as the window exists.
  installMainWindowActions({ showFile, promptForDirectory });

  onMount(() => {
    const unsubscribers = [
      on("workspace.changed", () => void workspaceChanged()),
      on<{ openCount: number }>("bugs.changed", (event) => {
        projectState.openBugCount = event.openCount;
      }),
      on("pr.review", () => void reloadTree()),
    ];
    void startup();
    return () => unsubscribers.forEach((unsubscribe) => unsubscribe());
  });
</script>

<svelte:window onkeydown={keydown} onfocusin={rememberEditable} />

<div class="main">
  <MenuBar {menus}>
    {#snippet right()}<PRMenu />{/snippet}
  </MenuBar>
  <MainToolbar
    canBack={canGoBack(history)}
    canForward={canGoForward(history)}
    historyItems={historyItems}
    back={() => navigate(-1)}
    forward={() => navigate(1)}
    openFolder={() => void promptForDirectory()}
    toggleSidebar={() => (treeVisible = !treeVisible)}
    findInFile={findInFile}
  />
  <PRBanner />
  <div class="panes" bind:clientWidth={panesWidth}>
    <div class="tree-pane" hidden={!treeVisible} style:width="{treeWidth}px">
      <FileTree onOpenFile={(path) => showFile(path)} />
    </div>
    <div
      class="divider"
      hidden={!treeVisible}
      role="separator"
      aria-orientation="vertical"
      onpointerdown={(event) => dragDivider("tree", event)}
    ></div>
    <div class="source-pane">
      <SourceViewer bind:this={viewer} onShown={viewerShown} onFunctionSelected={viewerFunctionSelected} />
    </div>
    <div
      class="divider"
      role="separator"
      aria-orientation="vertical"
      onpointerdown={(event) => dragDivider("flow", event)}
    ></div>
    <div class="flow-pane" style:width="{flowWidth}px">
      <FlowPanel path={flowSelection?.path ?? null} functionName={flowSelection?.functionName ?? null} />
    </div>
  </div>
</div>

{#if projectState.index}<IndexBuildSheet build={projectState.index} />{/if}

<style>
  .main {
    flex: 1;
    min-height: 0;
    min-width: 0;
    display: flex;
    flex-direction: column;
    background: var(--window-bg);
  }
  .panes {
    flex: 1;
    min-height: 0;
    display: flex;
    overflow: hidden;
  }
  .tree-pane,
  .flow-pane {
    flex: none;
    display: flex;
    flex-direction: column;
    min-width: 0;
    min-height: 0;
    overflow: hidden;
  }
  .source-pane {
    flex: 1;
    min-width: 500px;
    min-height: 0;
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }
  .divider {
    flex: none;
    width: 6px;
    cursor: col-resize;
    background: linear-gradient(to right, transparent 2px, rgba(0, 0, 0, 0.6) 2px, rgba(0, 0, 0, 0.6) 3px, transparent 3px);
  }
  .tree-pane[hidden],
  .divider[hidden] {
    display: none;
  }
</style>
