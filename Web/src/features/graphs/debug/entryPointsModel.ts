// The entry-point finder's data: the server's DTOs, the outline rows built from
// them, and the diagram model of a traced entry. Plain data only, so the rules
// (row labels, badge colours, which node opens which file) can be tested.
import type { DiagramFlowStyle, DiagramGraphDTO, GraphEdgeDTO, GraphNodeDTO } from "../flow/diagramModel";

export const ENTRY_POINTS_TITLE = "Find external entries to the application";

/** The red dashed flow of an entry (`EntryPointsWindowController`'s `FlowEdgeStyle`). */
export const ENTRY_FLOW_STYLE: DiagramFlowStyle = {
  color: "var(--system-red)",
  dashes: [10, 4, 2, 4],
  lineWidth: 3,
  phaseStep: 4,
};

export interface EntrySite {
  /** `"<path>#<charIndex>"`; the trace endpoint takes it. */
  id: string;
  path: string;
  relativePath: string;
  line: number;
  column: number;
  apiName: string;
  apiPath: string;
  category: string;
  origin: "internet" | "local";
  confidence: "primary" | "indirect";
  entryVariable?: string | null;
  snippet: string;
  displaySnippet: string;
  /** "<relative path>:<line>". */
  label: string;
  sourceKind: string;
}

export interface EntryGroup {
  id: string;
  category: string;
  origin: "internet" | "local";
  confidence: "primary" | "indirect";
  /** "◉ remote", "◈ local" or "~ indirect". */
  badge: string;
  title: string;
  sites: EntrySite[];
}

export interface EntryTraceNode {
  name: string;
  path?: string | null;
  line?: number | null;
  isStart: boolean;
  isOrigin: boolean;
}

export interface EntryTraceEdge {
  from: string;
  to: string;
}

export interface EntryTrace {
  siteID: string;
  caption: string;
  /** "Remote" or "Local". */
  originLabel: string;
  nodes: EntryTraceNode[];
  edges: EntryTraceEdge[];
}

/** `EntryPointsService.EntryPointsStateDTO`: everything the window shows. */
export interface EntryPointsState {
  title: string;
  busy: boolean;
  progressText: string;
  progressDone: number;
  progressTotal: number;
  indirectEnabled: boolean;
  countText: string;
  truncated: boolean;
  groups: EntryGroup[];
  trace?: EntryTrace | null;
}

/** One outline row: a category or one of its entry sites. */
export type EntryRow = { kind: "group"; group: EntryGroup } | { kind: "site"; site: EntrySite };

export interface EntryTreeNode {
  id: string;
  data: EntryRow;
  children?: EntryTreeNode[];
}

/** "1 site", "2 sites": the count the group headers and the window show. */
export function sitesText(count: number): string {
  return `${count} site${count === 1 ? "" : "s"}`;
}

/** The badge colour: remote entries blue, local ones green. */
export function badgeColor(origin: EntryGroup["origin"]): string {
  return origin === "internet" ? "var(--system-blue)" : "var(--system-green)";
}

/** Categories at the top, each with its sites below; every category starts expanded. */
export function outlineNodes(groups: readonly EntryGroup[]): EntryTreeNode[] {
  return groups.map((group) => ({
    id: group.id,
    data: { kind: "group", group },
    children: group.sites.map((site) => ({ id: site.id, data: { kind: "site", site } })),
  }));
}

/** The file name of an absolute path. */
export function fileName(path: string): string {
  return path.slice(path.lastIndexOf("/") + 1);
}

/** The caption shown while a variable's flow is traced (`trace(site:)`). */
export function tracingCaption(site: EntrySite): string {
  return `Tracing “${site.entryVariable ?? ""}” from ${fileName(site.path)}:${site.line}…`;
}

/**
 * The flow of a trace as a diagram: the origin box, the flow boxes and their arrows. The
 * diagram lays the origin out on the top rank, animates the arrows only, and highlights the
 * box of the selected entry. Nil when the trace has no boxes (the diagram is then cleared).
 */
export function traceDiagram(trace: EntryTrace): DiagramGraphDTO | null {
  if (trace.nodes.length === 0) return null;
  const nodes: GraphNodeDTO[] = trace.nodes.map((node) => ({
    name: node.name,
    path: node.path ?? undefined,
    line: node.line ?? undefined,
    isOrigin: node.isOrigin,
    isGreyed: false,
    isOutlined: false,
    originColor: undefined,
  }));
  const edges: GraphEdgeDTO[] = trace.edges.map((edge) => ({ from: edge.from, to: edge.to }));
  const start = trace.nodes.find((node) => node.isStart);
  return {
    nodes,
    callEdges: edges,
    dataEdges: edges,
    highlight: start?.name,
    layoutDirection: "topToBottom",
    layoutSourceNodes: trace.nodes.filter((node) => node.isOrigin).map((node) => node.name),
    layoutCenterNode: undefined,
    focusNodes: undefined,
    animatedOnlyEdges: true,
  };
}

/** Where a clicked box opens: its file and line. Origin boxes and unknown names open nothing. */
export function nodeLocation(trace: EntryTrace, name: string): { path: string; line: number } | null {
  const node = trace.nodes.find((candidate) => candidate.name === name);
  if (!node || node.isOrigin || !node.path || !node.line) return null;
  return { path: node.path, line: node.line };
}

/** The bar's value: done over total while the total is known, else 0. */
export function progressFraction(done: number, total: number): number {
  return total > 0 ? done / total : 0;
}
