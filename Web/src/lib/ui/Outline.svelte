<script lang="ts" module>
  export interface TreeNode<D> {
    id: string;
    data: D;
    children?: TreeNode<D>[];
  }
</script>

<script lang="ts" generics="Data">
  // NSOutlineView: a tree with disclosure triangles. Which nodes are expanded
  // is remembered per node id, so a reloaded tree keeps its shape.
  import type { Snippet } from "svelte";
  import { isAlternateRow, stripeBackground } from "./stripes";

  let {
    nodes,
    label,
    selectedId = $bindable(null),
    expanded = $bindable({}),
    rowHeight = 20,
    onSelect,
    onDoubleClick,
    onContextMenu,
    expandAll = false,
  }: {
    nodes: TreeNode<Data>[];
    label: Snippet<[TreeNode<Data>]>;
    selectedId?: string | null;
    expanded?: Record<string, boolean>;
    rowHeight?: number;
    onSelect?: (node: TreeNode<Data> | null) => void;
    onDoubleClick?: (node: TreeNode<Data>) => void;
    onContextMenu?: (node: TreeNode<Data> | null, event: MouseEvent) => void;
    /** Treat nodes without an explicit state as expanded. */
    expandAll?: boolean;
  } = $props();

  interface Flat {
    node: TreeNode<Data>;
    depth: number;
  }

  const isOpen = (node: TreeNode<Data>) => expanded[node.id] ?? expandAll;

  const flat = $derived.by(() => {
    const out: Flat[] = [];
    const walk = (list: TreeNode<Data>[], depth: number) => {
      for (const node of list) {
        out.push({ node, depth });
        if (node.children && node.children.length > 0 && isOpen(node)) walk(node.children, depth + 1);
      }
    };
    walk(nodes, 0);
    return out;
  });

  // NSOutlineView with `usesAlternatingRowBackgroundColors`: the empty space under the rows keeps alternating.
  const filler = $derived(stripeBackground(rowHeight, isAlternateRow(flat.length)));

  function toggle(node: TreeNode<Data>) {
    expanded[node.id] = !isOpen(node);
  }

  function select(node: TreeNode<Data> | null) {
    selectedId = node ? node.id : null;
    onSelect?.(node);
  }

  function keydown(event: KeyboardEvent) {
    const index = flat.findIndex((f) => f.node.id === selectedId);
    if (event.key === "ArrowDown" && index < flat.length - 1) {
      event.preventDefault();
      select(flat[index + 1].node);
    } else if (event.key === "ArrowUp" && index > 0) {
      event.preventDefault();
      select(flat[index - 1].node);
    } else if (event.key === "ArrowRight" && index >= 0 && flat[index].node.children?.length) {
      expanded[flat[index].node.id] = true;
    } else if (event.key === "ArrowLeft" && index >= 0 && flat[index].node.children?.length) {
      expanded[flat[index].node.id] = false;
    }
  }
</script>

<div
  class="outline"
  role="tree"
  tabindex="0"
  onkeydown={keydown}
  onclick={(e) => e.target === e.currentTarget && select(null)}
  oncontextmenu={(e) => {
    if (e.target === e.currentTarget) {
      e.preventDefault();
      onContextMenu?.(null, e);
    }
  }}
>
  {#each flat as { node, depth }, index (node.id)}
    <div
      class="row"
      class:alt={isAlternateRow(index)}
      class:selected={node.id === selectedId}
      style="height:{rowHeight}px; padding-left:{4 + depth * 14}px"
      role="treeitem"
      aria-selected={node.id === selectedId}
      tabindex="-1"
      onclick={() => select(node)}
      ondblclick={() => (node.children?.length ? toggle(node) : onDoubleClick?.(node))}
      oncontextmenu={(e) => {
        e.preventDefault();
        select(node);
        onContextMenu?.(node, e);
      }}
      onkeydown={() => {}}
    >
      <span
        class="twisty"
        class:hidden={!node.children || node.children.length === 0}
        role="presentation"
        onclick={(e) => {
          e.stopPropagation();
          toggle(node);
        }}>{isOpen(node) ? "▾" : "▸"}</span
      >
      {@render label(node)}
    </div>
  {/each}
  <div class="filler" style="background:{filler}"></div>
</div>

<style>
  .outline {
    flex: 1;
    min-height: 0;
    overflow: auto;
    background: var(--control-bg);
    outline: none;
    display: flex;
    flex-direction: column;
  }
  .filler {
    flex: 1 1 0;
    min-height: 0;
    pointer-events: none;
  }
  .row {
    display: flex;
    flex: none;
    align-items: center;
    white-space: nowrap;
    min-width: max-content;
  }
  .row.alt {
    background: var(--row-alt);
  }
  .row.selected {
    background: var(--accent);
    color: #fff;
  }
  .twisty {
    width: 14px;
    flex: none;
    text-align: center;
    font-size: 10px;
    color: var(--secondary-label);
  }
  .twisty.hidden {
    visibility: hidden;
  }
  .row.selected .twisty {
    color: #fff;
  }
</style>
