// The server's answers of the trace windows (`FlowService` in
// Sources/KarmaCore/service/FlowService.swift). Optional Swift values may be
// absent from the JSON, so they are typed as possibly missing.
import type { DiagramGraphDTO } from "../flow";

export interface LineTextDTO {
  line: number;
  text: string;
}

/** "entry", "exit", "block", "decision", "switch" or "join". */
export type FlowNodeKind = "entry" | "exit" | "block" | "decision" | "switch" | "join";

export interface FlowNodeDTO {
  id: number;
  kind: FlowNodeKind;
  /** "START", "END", "" for joins, otherwise the statement or condition. */
  label: string;
  line?: number | null;
  highlighted: boolean;
}

export interface FlowEdgeDTO {
  from: number;
  to: number;
  /** "T", "F", a case label, or absent for plain flow. */
  branch?: string | null;
  isBackEdge: boolean;
}

export interface FlowChartDTO {
  nodes: FlowNodeDTO[];
  edges: FlowEdgeDTO[];
}

export interface VariableNodeDTO {
  id: string;
  functionName: string;
  variableName: string;
  path: string;
  fileHint: string;
  depth: number;
  uses: LineTextDTO[];
  isStart: boolean;
}

export interface VariableEdgeDTO {
  from: string;
  to: string;
  callLine: number;
}

export interface CalloutDTO {
  callLine: number;
  functionName: string;
  variableName: string;
  path: string;
  fileHint: string;
  useLines: LineTextDTO[];
  children: CalloutDTO[];
}

export interface VariableFlowDTO {
  variableName: string;
  startFunction: string;
  windowTitle: string;
  title: string;
  caption: string;
  warnings: string[];
  nodes: VariableNodeDTO[];
  edges: VariableEdgeDTO[];
  callouts: CalloutDTO[];
  chart?: FlowChartDTO | null;
}

export interface ReachabilityDTO {
  functionName: string;
  windowTitle: string;
  title: string;
  caption: string;
  remoteReachable: boolean;
  localReachable: boolean;
  unverified: boolean;
  graph?: DiagramGraphDTO | null;
}

export interface ComplexityPointDTO {
  name: string;
  complexity: number;
  line: number;
  path: string;
}

export interface ComplexityDTO {
  windowTitle: string;
  summary: string;
  placeholder: string;
  points: ComplexityPointDTO[];
}

export interface ClassUsageSiteDTO {
  path: string;
  line: number;
  snippet: string;
}

export interface ClassUsageDTO {
  className: string;
  windowTitle: string;
  title: string;
  status: string;
  emptyMessage?: string | null;
  sites: ClassUsageSiteDTO[];
  graph?: DiagramGraphDTO | null;
}
