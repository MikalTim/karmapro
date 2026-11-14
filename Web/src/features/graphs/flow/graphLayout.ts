// Port of `GraphLayout` (Sources/KarmaCore/graphs/GraphLayout.swift): the layered layout used
// by the data-flow, reachability and class-usage diagrams, and the butterfly layout centred on
// one function. Layout coordinates are the Swift ones; the diagram maps them to the screen.
// Where Swift iterates a Set or Dictionary (its order is random per process), names are
// visited in sorted order so the result is the same every time.

export interface LayoutEdge {
  readonly from: string;
  readonly to: string;
}

export interface LayoutPoint {
  x: number;
  y: number;
}

export interface LayoutSize {
  width: number;
  height: number;
}

export interface LayoutResult {
  /** Top-left corner of each node box, in layout coordinates. */
  positions: Map<string, LayoutPoint>;
  layerCount: number;
  size: LayoutSize;
}

export type LayoutDirection = "leftToRight" | "topToBottom";

// Node sizing, kept in sync with the diagram's node frames (`nodeSize(for:)`).
export const NODE_WIDTH = 128;
export const NODE_HEIGHT = 34;
const H_GAP = 44;
const V_GAP = 56;
const MAX_PER_ROW = 9;
const ROW_GAP = 18;
const MIN_WIDTH = 400;
const BARYCENTER_PASSES = 5;

type Adjacency = Map<string, string[]>;

function adjacencyOf(edges: readonly LayoutEdge[]): { outgoing: Adjacency; incoming: Adjacency } {
  const outgoing: Adjacency = new Map();
  const incoming: Adjacency = new Map();
  for (const { from, to } of edges) {
    push(outgoing, from, to);
    push(incoming, to, from);
  }
  return { outgoing, incoming };
}

function push(map: Adjacency, key: string, value: string): void {
  const list = map.get(key);
  if (list) list.push(value);
  else map.set(key, [value]);
}

/** Average index of a node's neighbours in the target rank; infinity when it has none there. */
function barycenter(node: string, edges: Adjacency, targetIndex: Map<string, number>): number {
  const neighbours = edges.get(node) ?? [];
  let sum = 0;
  let count = 0;
  for (const n of neighbours) {
    const index = targetIndex.get(n);
    if (index !== undefined) {
      sum += index;
      count += 1;
    }
  }
  return count > 0 ? sum / count : Infinity;
}

function indexOf(names: readonly string[]): Map<string, number> {
  return new Map(names.map((name, index) => [name, index]));
}

/** Sorts by barycenter, then by name, as the Swift `sort` closures do. */
function sortByBarycenter(names: string[], score: (name: string) => number): string[] {
  const scores = new Map(names.map((name) => [name, score(name)]));
  return names.slice().sort((a, b) => {
    const aa = scores.get(a) ?? Infinity;
    const bb = scores.get(b) ?? Infinity;
    if (aa !== bb) return aa < bb ? -1 : 1;
    return a < b ? -1 : a > b ? 1 : 0;
  });
}

/**
 * `GraphLayout.layered`: ranks by longest path (from the sinks, or from `sourceNodes` when
 * `topToBottom`), orders each rank by barycenter sweeps, and places rows of at most nine nodes.
 */
export function layered(
  names: readonly string[],
  callEdges: readonly LayoutEdge[],
  direction: LayoutDirection,
  sourceNodes: readonly string[],
): LayoutResult {
  const nodeNames = [...new Set(names)].sort();
  const { outgoing, incoming } = adjacencyOf(callEdges);
  const rank = new Map<string, number>();

  if (direction === "topToBottom") {
    const inProgress = new Set<string>();
    const depthOf = (n: string, depth: number): void => {
      if (inProgress.has(n)) return;
      const existing = rank.get(n);
      if (existing !== undefined && existing >= depth) return;
      rank.set(n, depth);
      inProgress.add(n);
      for (const next of outgoing.get(n) ?? []) depthOf(next, depth + 1);
      inProgress.delete(n);
    };
    for (const source of sourceNodes) depthOf(source, 0);
    for (const n of nodeNames) if (!rank.has(n)) depthOf(n, 0);
  } else {
    const inProgress = new Set<string>();
    const rankOf = (n: string): number => {
      const known = rank.get(n);
      if (known !== undefined) return known;
      if (inProgress.has(n)) return 0;
      inProgress.add(n);
      const next = outgoing.get(n);
      let r = 0;
      if (next !== undefined) {
        for (const m of next) r = Math.max(r, rankOf(m) + 1);
      }
      rank.set(n, r);
      inProgress.delete(n);
      return r;
    };
    for (const n of nodeNames) rankOf(n);
  }

  const maxRank = Math.max(0, ...rank.values());
  const layersCount = maxRank + 1;
  const layers: string[][] = Array.from({ length: layersCount }, () => []);
  for (const n of [...rank.keys()].sort()) layers[rank.get(n) ?? 0].push(n);

  for (let pass = 0; pass < BARYCENTER_PASSES; pass++) {
    for (let r = 0; r < layersCount; r++) {
      if (layers[r].length === 0) continue;
      if (r + 1 < layersCount) {
        const nextPosition = indexOf(layers[r + 1]);
        layers[r] = sortByBarycenter(layers[r], (n) => barycenter(n, outgoing, nextPosition));
      }
    }
    for (let r = layersCount - 1; r >= 0; r--) {
      if (layers[r].length === 0) continue;
      if (r > 0) {
        const previousPosition = indexOf(layers[r - 1]);
        layers[r] = sortByBarycenter(layers[r], (n) => barycenter(n, incoming, previousPosition));
      }
    }
  }

  const positions = new Map<string, LayoutPoint>();
  let maxWidth = 0;
  let maxRowIndex = 0;
  for (let r = 0; r <= maxRank; r++) {
    const nodes = layers[r];
    if (nodes.length === 0) continue;
    const rows = Math.max(1, Math.ceil(nodes.length / MAX_PER_ROW));
    let index = 0;
    for (let row = 0; row < rows; row++) {
      const rowNodes = nodes.slice(index, Math.min(index + MAX_PER_ROW, nodes.length));
      index += rowNodes.length;
      const total = NODE_WIDTH + (rowNodes.length - 1) * (NODE_WIDTH + H_GAP);
      maxWidth = Math.max(maxWidth, total);
      const rowY = r * (NODE_HEIGHT + V_GAP) + row * (NODE_HEIGHT + ROW_GAP);
      // The Swift code starts each row at `total / 2` for the node centre, which leaves
      // rows of different widths offset from one another. Kept as it is.
      let x = total / 2;
      for (const n of rowNodes) {
        positions.set(n, { x: x - NODE_WIDTH / 2, y: rowY });
        x += NODE_WIDTH + H_GAP;
      }
      maxRowIndex = Math.max(maxRowIndex, row);
    }
  }

  const height = maxRank * (NODE_HEIGHT + V_GAP) + maxRowIndex * (NODE_HEIGHT + ROW_GAP) + NODE_HEIGHT + 40;
  return { positions, layerCount: layersCount, size: { width: Math.max(maxWidth, MIN_WIDTH), height } };
}

/**
 * `GraphLayout.butterfly`: the centre sits in column 0, its transitive callers fan out to the
 * left (negative columns), its transitive callees to the right, and unrelated functions are
 * stacked in one block past the last callee column. Falls back to `layered` without a centre.
 */
export function butterfly(names: readonly string[], callEdges: readonly LayoutEdge[], center: string | null): LayoutResult {
  const nameSet = new Set(names);
  if (center === null || !nameSet.has(center)) {
    return layered(names, callEdges, "leftToRight", []);
  }

  const usable = callEdges.filter((e) => nameSet.has(e.from) && nameSet.has(e.to));
  const { outgoing, incoming } = adjacencyOf(usable);

  const closure = (edges: Adjacency): Set<string> => {
    const visited = new Set<string>([center]);
    let frontier = [center];
    while (frontier.length > 0) {
      const next: string[] = [];
      for (const n of frontier) {
        for (const m of edges.get(n) ?? []) {
          if (!visited.has(m)) {
            visited.add(m);
            next.push(m);
          }
        }
      }
      frontier = next;
    }
    return visited;
  };
  const callers = closure(incoming);
  const descendants = closure(outgoing);
  callers.delete(center);
  descendants.delete(center);
  // Nodes on a cycle with the centre sit above it: they stay on the caller side.
  const callees = new Set([...descendants].filter((n) => !callers.has(n)));
  const others = [...nameSet].filter((n) => n !== center && !callers.has(n) && !callees.has(n));

  const rank = new Map<string, number>([[center, 0]]);
  const rankTo = (n: string, via: Adjacency, allowed: Set<string>, inProgress: Set<string>): number => {
    const known = rank.get(n);
    if (known !== undefined) return known;
    if (inProgress.has(n)) return 0;
    inProgress.add(n);
    let r = 0;
    for (const c of via.get(n) ?? []) {
      if (allowed.has(c) || c === center) r = Math.max(r, rankTo(c, via, allowed, inProgress) + 1);
    }
    rank.set(n, r);
    inProgress.delete(n);
    return r;
  };
  for (const n of [...callers].sort()) rankTo(n, outgoing, callers, new Set());
  for (const n of [...callees].sort()) rankTo(n, incoming, callees, new Set());

  const columns = new Map<number, string[]>([[0, [center]]]);
  const addTo = (column: number, n: string): void => {
    const list = columns.get(column);
    if (list) list.push(n);
    else columns.set(column, [n]);
  };
  let maxForward = 0;
  for (const n of [...callees].sort()) {
    const c = Math.max(1, rank.get(n) ?? 1);
    maxForward = Math.max(maxForward, c);
    addTo(c, n);
  }
  for (const n of [...callers].sort()) {
    const c = Math.max(1, rank.get(n) ?? 1);
    addTo(-c, n);
  }
  const otherColumn = maxForward + 1;
  if (others.length > 0) columns.set(otherColumn, others.sort());

  const neighbourAverage = (node: string, position: Map<string, number>): number => {
    let sum = 0;
    let count = 0;
    for (const n of [...(outgoing.get(node) ?? []), ...(incoming.get(node) ?? [])]) {
      const index = position.get(n);
      if (index !== undefined) {
        sum += index;
        count += 1;
      }
    }
    return count > 0 ? sum / count : Infinity;
  };
  const sortColumn = (nodes: string[], neighbours: string[]): string[] => {
    const position = indexOf(neighbours);
    return sortByBarycenter(nodes, (n) => neighbourAverage(n, position));
  };

  const keys = [...columns.keys()];
  const minColumn = Math.min(...keys);
  const maxColumn = Math.max(...keys);
  for (let pass = 0; pass < BARYCENTER_PASSES; pass++) {
    for (let col = minColumn; col <= maxColumn; col++) {
      const nodes = columns.get(col);
      const left = columns.get(col - 1);
      if (!nodes || nodes.length <= 1 || !left || left.length === 0) continue;
      columns.set(col, sortColumn(nodes, left));
    }
    for (let col = maxColumn; col >= minColumn; col--) {
      const nodes = columns.get(col);
      const right = columns.get(col + 1);
      if (!nodes || nodes.length <= 1 || !right || right.length === 0) continue;
      columns.set(col, sortColumn(nodes, right));
    }
  }

  const positions = new Map<string, LayoutPoint>();
  const colSpacing = NODE_WIDTH + H_GAP;
  let maxRows = 1;
  for (let col = minColumn; col <= maxColumn; col++) {
    const nodes = columns.get(col);
    if (!nodes || nodes.length === 0) continue;
    const x = col * colSpacing + (colSpacing - NODE_WIDTH) / 2;
    let y = 0;
    for (const n of nodes) {
      positions.set(n, { x, y });
      y += NODE_HEIGHT + ROW_GAP;
    }
    maxRows = Math.max(maxRows, nodes.length);
  }

  const xs = [...positions.values()].map((p) => p.x);
  const minX = Math.min(...xs);
  const maxX = Math.max(...xs) + NODE_WIDTH;
  const height = maxRows * (NODE_HEIGHT + ROW_GAP) + 40;
  return {
    positions,
    layerCount: maxColumn - minColumn + 1,
    size: { width: Math.max(maxX - minX + H_GAP * 2, MIN_WIDTH), height },
  };
}
