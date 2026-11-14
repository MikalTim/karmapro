<script lang="ts">
  // The toolbar (`MainWindowController` toolbar items, in `toolbarDefaultItemIdentifiers`
  // order). Each item keeps its AppKit label, tooltip and tint.
  import {
    Brain,
    Crosshair,
    FileSearch,
    Folder,
    Library,
    PanelLeft,
    ShieldHalf,
    Sparkles,
    StickyNote,
    TextSearch,
  } from "@lucide/svelte";
  import PopUp from "../../lib/ui/PopUp.svelte";
  import SearchField from "../../lib/ui/SearchField.svelte";
  import Toolbar from "../../lib/ui/Toolbar.svelte";
  import ToolbarButton from "../../lib/ui/ToolbarButton.svelte";
  import type { MenuItem } from "../../lib/ui/contextMenu.svelte";
  import { showAlert } from "../../lib/ui/alert.svelte";
  import { openAIWindow, openMLScanWindow, openMLTrainingWindow } from "../ai";
  import { openFileSearchWindow, openScanWindow } from "../scan";
  import { openBugListWindow, openNotesWindow, openWikiWindow } from "../tools";
  import BugsButton from "./BugsButton.svelte";
  import HistoryButton from "./HistoryButton.svelte";
  import { projectState } from "./projectState.svelte";
  import { ALL_LANGUAGES, reloadTree, setLanguage, treeState } from "./treeState.svelte";

  let {
    canBack,
    canForward,
    historyItems,
    back,
    forward,
    openFolder,
    toggleSidebar,
    findInFile,
  }: {
    canBack: boolean;
    canForward: boolean;
    historyItems: () => MenuItem[];
    back: () => void;
    forward: () => void;
    openFolder: () => void;
    toggleSidebar: () => void;
    findInFile: () => void;
  } = $props();

  const languageItems = $derived(treeState.languages.map((name) => ({ title: name, value: name })));

  /** The file search starts with the language chosen in the popup; "All Languages" means none. */
  const searchLanguage = $derived(treeState.language === ALL_LANGUAGES ? null : treeState.language);

  /** ML Scan needs a folder first; without one AppKit shows this alert and stops. */
  async function mlScan(): Promise<void> {
    if (projectState.root === null) {
      await showAlert({
        message: "No Folder Open",
        informative: "Open a source folder before running an ML scan.",
        buttons: ["OK"],
      });
      return;
    }
    openMLScanWindow();
  }

  /** The AI assistant needs a project; its alert offers to choose one. */
  async function aiAssistant(): Promise<void> {
    if (projectState.root === null) {
      const choice = await showAlert({
        message: "No Project Selected",
        informative: "You need to first select a project before using the AI assistant.",
        buttons: ["Open Folder", "Cancel"],
      });
      if (choice === 0) openFolder();
      return;
    }
    openAIWindow();
  }
</script>

<Toolbar>
  <div class="history-group" role="group" aria-label="History" title="Navigate between recently opened files">
    <HistoryButton direction="back" enabled={canBack} items={historyItems} onClick={back} />
    <HistoryButton direction="forward" enabled={canForward} items={historyItems} onClick={forward} />
  </div>
  <ToolbarButton label="Open Folder" tooltip="Open a source code folder to browse" onClick={() => openFolder()}>
    {#snippet icon()}<Folder size={16} />{/snippet}
  </ToolbarButton>
  <ToolbarButton label="Toggle Sidebar" tooltip="Show or hide the file sidebar" onClick={() => toggleSidebar()}>
    {#snippet icon()}<PanelLeft size={16} />{/snippet}
  </ToolbarButton>
  <span class="language" role="group" aria-label="Language">
    <PopUp items={languageItems} value={treeState.language} width={200} onChange={setLanguage} />
  </span>
  <ToolbarButton label="Find in File" tooltip="Find text within the current file" onClick={() => findInFile()}>
    {#snippet icon()}<TextSearch size={16} />{/snippet}
  </ToolbarButton>
  <ToolbarButton
    label="Search in Files"
    tooltip="Search text across all files in the project"
    onClick={() => openFileSearchWindow({ language: searchLanguage })}
  >
    {#snippet icon()}<FileSearch size={16} />{/snippet}
  </ToolbarButton>
  <SearchField bind:value={treeState.query} placeholder="Find files…" width={200} onInput={() => void reloadTree()} />
  <div class="spacer"></div>
  <ToolbarButton label="Security Scan" tooltip="Scan the project for common vulnerabilities" onClick={() => openScanWindow()}>
    {#snippet icon()}<span class="tint" style:color="var(--system-red)"><ShieldHalf size={16} /></span>{/snippet}
  </ToolbarButton>
  <ToolbarButton label="Train ML" tooltip="Train the Bayesian classifier from patch files" onClick={() => openMLTrainingWindow()}>
    {#snippet icon()}<span class="tint" style:color="var(--system-purple)"><Brain size={16} /></span>{/snippet}
  </ToolbarButton>
  <ToolbarButton label="ML Scan" tooltip="Scan the project with a trained model and highlight risky lines" onClick={() => void mlScan()}>
    {#snippet icon()}<span class="tint" style:color="var(--system-teal)"><Crosshair size={16} /></span>{/snippet}
  </ToolbarButton>
  <ToolbarButton label="Notes" tooltip="Show all notes and go to their locations" onClick={() => openNotesWindow()}>
    {#snippet icon()}<span class="tint" style:color="var(--system-orange)"><StickyNote size={16} /></span>{/snippet}
  </ToolbarButton>
  <ToolbarButton label="Wiki" tooltip="Open the private research wiki" onClick={() => openWikiWindow()}>
    {#snippet icon()}<span class="tint" style:color="var(--system-purple)"><Library size={16} /></span>{/snippet}
  </ToolbarButton>
  <BugsButton count={projectState.openBugCount} onClick={() => openBugListWindow()} />
  <ToolbarButton label="AI" tooltip="Open the AI assistant for the current project" onClick={() => void aiAssistant()}>
    {#snippet icon()}<span class="tint" style:color="var(--system-indigo)"><Sparkles size={16} /></span>{/snippet}
  </ToolbarButton>
</Toolbar>

<style>
  .history-group {
    display: flex;
    gap: 2px;
  }
  .language {
    display: inline-flex;
  }
  .spacer {
    flex: 1;
  }
  .tint {
    display: grid;
    place-items: center;
  }
</style>
