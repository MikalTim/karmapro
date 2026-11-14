<script lang="ts">
  // The wiki page editor (WikiEditorWindowController): the title, the formatting bar,
  // the page body and a status line with Save. The page loads when the window opens
  // and saves with PUT. Closing the window saves unsaved edits first, as AppKit's
  // windowWillClose does. When that save fails the window stays open, so no edit is lost.
  import { onDestroy, onMount } from "svelte";
  import { api, ApiError } from "../../../../lib/api";
  import { showAlertWithFields } from "../../../../lib/ui/alert.svelte";
  import { closeWindow, setWindowTitle } from "../../../../lib/ui/windows.svelte";
  import {
    applyWikiLinks,
    characterCount,
    flatten,
    fromDocument,
    toDocument,
    wikiLinkURL,
    type Piece,
  } from "../richText";
  import {
    errorMessage,
    isSaveShortcut,
    linkFromFields,
    selectionLinkText,
    statusLine,
    type WikiPageDetail,
  } from "./editorModel";
  import { registerEditorSession, unregisterEditorSession } from "./editorSessions";
  import RichTextEditor from "./RichTextEditor.svelte";

  let {
    windowId,
    slug,
    followLink,
  }: {
    windowId: number;
    slug: string;
    /** Opens the page a link names, creating it when missing. Closes this window first. */
    followLink: (target: string, fromWindowId: number) => Promise<void>;
  } = $props();

  let initial = $state.raw<Piece[] | null>(null);
  let title = $state("");
  let plain = $state("");
  let dirty = $state(false);
  let errorText = $state("");
  let editor: ReturnType<typeof RichTextEditor> | undefined = $state();
  // Counts every change, so a save that finishes after a later change leaves the page marked edited.
  let revision = 0;

  const status = $derived(statusLine(dirty, title, characterCount(plain)));

  async function load(): Promise<void> {
    try {
      const detail = await api<WikiPageDetail>("GET", `/api/wiki/${encodeURIComponent(slug)}`);
      const pieces = applyWikiLinks(fromDocument(detail.document));
      title = detail.info.title;
      setWindowTitle(windowId, detail.info.title);
      plain = flatten(pieces);
      initial = pieces;
      registerEditorSession(slug, { saveIfDirty });
    } catch (error) {
      // AppKit's loadPage closes the editor when its page is gone.
      if (error instanceof ApiError && error.status === 404) {
        await closeWindow(windowId);
        return;
      }
      errorText = errorMessage(error);
    }
  }

  function markDirty(): void {
    revision++;
    dirty = true;
  }

  function edited(next: Piece[]): void {
    plain = flatten(next);
    markDirty();
  }

  /** Saves the title and the page (`saveNow`). A failed save leaves the page marked edited. */
  async function save(): Promise<boolean> {
    if (!editor) return false;
    const saving = revision;
    try {
      await api("PUT", `/api/wiki/${encodeURIComponent(slug)}`, {
        title,
        document: toDocument(editor.getContent()),
      });
      if (saving === revision) dirty = false;
      errorText = "";
      return true;
    } catch (error) {
      errorText = errorMessage(error);
      return false;
    }
  }

  async function saveIfDirty(): Promise<boolean> {
    if (!dirty) return true;
    return save();
  }

  /** The Link… button (`insertLinkClicked`). A selection becomes a link at once; otherwise a dialog asks for the text and the page. */
  async function insertLinkClicked(): Promise<void> {
    if (!editor) return;
    const span = editor.selection();
    if (span.end > span.start) {
      const text = selectionLinkText(editor.selectedText());
      if (text !== null) editor.insertLink(span, text, wikiLinkURL(text));
      return;
    }
    const result = await showAlertWithFields({
      message: "Insert Wiki Link",
      informative:
        "With a selection, the Link button hyperlinks it instantly. Here you can set the link text and the page it opens (created if missing).",
      buttons: ["Insert", "Cancel"],
      fields: [
        { label: "Link text:", placeholder: "e.g. Buffer Overflow Notes", width: 280 },
        { label: "Wiki page:", placeholder: "e.g. Buffer Overflows", width: 280 },
      ],
    });
    if (result.button !== 0) return;
    const link = linkFromFields(result.values[0] ?? "", result.values[1] ?? "");
    if (link !== null) editor.insertLink(span, link.text, wikiLinkURL(link.pageName));
  }

  async function openLink(target: string): Promise<void> {
    try {
      await followLink(target, windowId);
    } catch (error) {
      errorText = errorMessage(error);
    }
  }

  function keydown(event: KeyboardEvent): void {
    const mac = /Mac|iPhone|iPad/.test(navigator.platform);
    if (!isSaveShortcut(event.key, event.metaKey, event.ctrlKey, mac)) return;
    event.preventDefault();
    void save();
  }

  onMount(() => {
    void load();
  });

  onDestroy(() => {
    unregisterEditorSession(slug);
  });
</script>

<div class="wiki-window" role="presentation" onkeydown={keydown}>
  <input class="title" type="text" placeholder="Page Title" bind:value={title} oninput={markDirty} />
  <hr class="rule" />
  <!-- The toolbar keeps the page's selection: pressing a button must not move the focus out of the page. -->
  <div class="formats" role="toolbar" tabindex="-1" onmousedown={(event) => event.preventDefault()}>
    <button type="button" title="Bold" onclick={() => editor?.format("bold")}>B</button>
    <button type="button" title="Italic" onclick={() => editor?.format("italic")}>I</button>
    <button type="button" title="Underline" onclick={() => editor?.format("underline")}>U</button>
    <button type="button" title="Monospace code" onclick={() => editor?.format("code")}>Code</button>
    <button type="button" title="Heading style" onclick={() => editor?.format("heading")}>Heading</button>
    <button type="button" title="Body text style" onclick={() => editor?.format("body")}>Body</button>
    <button
      type="button"
      title="Insert a link to another wiki page"
      onclick={() => void insertLinkClicked()}>Link…</button
    >
  </div>
  <div class="frame">
    {#if initial}
      <RichTextEditor bind:this={editor} initial={initial} onChange={edited} onOpenLink={openLink} />
    {/if}
  </div>
  <div class="bottom">
    <span class="status">{status}</span>
    {#if errorText}<span class="error">{errorText}</span>{/if}
    <button type="button" onclick={() => void save()}>Save</button>
  </div>
</div>

<style>
  .wiki-window {
    display: flex;
    flex-direction: column;
    box-sizing: border-box;
    height: 100%;
    padding: 16px 16px 12px;
    color: var(--label);
    font: 13px var(--font-ui);
  }

  .title {
    flex: none;
    box-sizing: border-box;
    width: 100%;
    padding: 0;
    border: 0;
    outline: none;
    background: transparent;
    color: var(--label);
    font: 700 20px var(--font-ui);
  }

  .title::placeholder {
    color: var(--tertiary-label);
  }

  .rule {
    flex: none;
    margin: 8px 0;
    border: 0;
    border-top: 1px solid var(--separator);
  }

  .formats {
    flex: none;
    display: flex;
    align-items: center;
    gap: 6px;
    margin-bottom: 10px;
  }

  /* The page behind the editor is white, as in AppKit (`textView.backgroundColor = .white`). */
  .frame {
    flex: 1 1 auto;
    min-height: 0;
    overflow: auto;
    border: 1px solid var(--separator);
    background: #ffffff;
  }

  .bottom {
    flex: none;
    display: flex;
    align-items: center;
    gap: 10px;
    margin-top: 10px;
  }

  .status {
    flex: 1 1 auto;
    min-width: 0;
    overflow-wrap: anywhere;
    color: var(--secondary-label);
    font-size: 11px;
  }

  .error {
    color: var(--system-red);
    font-size: 11px;
  }

  button {
    padding: 2px 8px;
    border: 1px solid var(--separator);
    border-radius: 5px;
    background: var(--control-bg);
    color: var(--label);
    font: 11px var(--font-ui);
    cursor: default;
  }

  button:active {
    opacity: 0.7;
  }
</style>
