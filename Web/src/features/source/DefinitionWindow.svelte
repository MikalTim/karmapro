<script lang="ts">
  // The definition popup's contents: the whole file that defines a name, with the definition's line selected,
  // highlighted for 2.5 s and scrolled to the middle (`DefinitionWindowController.load`). A failed read shows
  // the reason in place of the text.
  import { onMount } from "svelte";
  import { EditorView } from "@codemirror/view";
  import CodeView from "../../lib/code/CodeView.svelte";
  import type { TextRange, TokenRange } from "../../lib/code/decorations";
  import { loadFile } from "./sourceApi";
  import { definitionLocation, lineRange, tokenRanges } from "./sourceModel";

  const HIGHLIGHT_MS = 2500;

  let {
    path,
    text,
    line,
  }: {
    windowId: number;
    path: string;
    text: string;
    line: number | null;
  } = $props();

  let host: HTMLDivElement | undefined = $state();
  let tokens = $state.raw<TokenRange[]>([]);
  let highlight = $state.raw<TextRange | null>(null);

  const target = $derived(line === null ? null : lineRange(text, line));
  const matches = $derived<TextRange[]>(highlight ? [highlight] : []);

  // Colour comes from the server's tokens. Without them the text still shows, uncoloured, because the
  // definition itself has already been read.
  $effect(() => {
    if (line === null) return;
    let current = true;
    loadFile(path).then(
      (file) => {
        if (current) tokens = tokenRanges(file.tokens);
      },
      () => {},
    );
    return () => {
      current = false;
    };
  });

  function centre(): void {
    const range = target;
    const element = host?.querySelector<HTMLElement>(".cm-editor");
    const view = element ? EditorView.findFromDOM(element) : null;
    if (range === null || view === null) return;
    view.dispatch({
      selection: { anchor: range.location, head: range.location + range.length },
      effects: EditorView.scrollIntoView(range.location, { y: "center" }),
    });
  }

  onMount(() => {
    if (target === null) return;
    highlight = target;
    const frame = requestAnimationFrame(centre);
    const fade = window.setTimeout(() => {
      highlight = null;
    }, HIGHLIGHT_MS);
    return () => {
      cancelAnimationFrame(frame);
      window.clearTimeout(fade);
    };
  });
</script>

<div class="definition" bind:this={host}>
  <div class="location">{definitionLocation(path, line)}</div>
  <div class="body">
    {#if line === null}
      <pre class="plain">{text}</pre>
    {:else}
      <CodeView source={text} {tokens} {matches} />
    {/if}
  </div>
</div>

<style>
  .definition {
    display: flex;
    flex-direction: column;
    height: 100%;
    min-height: 0;
    font-size: 12px;
  }
  .location {
    flex: none;
    padding: 12px 16px 0;
    font-size: 11px;
    color: var(--secondary-label);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .body {
    flex: 1;
    min-height: 0;
    margin-top: 8px;
  }
  .definition :global(.cm-editor) {
    font-size: 12px;
  }
  .plain {
    margin: 0;
    padding: 4px 8px;
    font: 12px var(--font-mono);
    color: var(--label);
    white-space: pre-wrap;
  }
</style>
