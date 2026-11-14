// Wire types of the flow panel (`FlowService.FlowDTO`): the complexity, the callees and the
// control-flow chart of one function.

export type FlowNodeKind = "entry" | "exit" | "block" | "decision" | "switch" | "join";

export interface FlowNodeDTO {
  id: number;
  kind: FlowNodeKind;
  /** The text drawn in the node: "START", "END", "" for joins, otherwise the statement or condition. */
  label: string;
  line?: number;
  highlighted: boolean;
}

export interface FlowEdgeDTO {
  from: number;
  to: number;
  /** "T", "F", a case label, or absent for plain sequential flow. */
  branch?: string;
  isBackEdge: boolean;
}

export interface FlowChartDTO {
  nodes: FlowNodeDTO[];
  edges: FlowEdgeDTO[];
}

export interface FlowDTO {
  functionName: string;
  /** Absent when the function cannot be charted. */
  complexity?: number;
  lineCount?: number;
  callees: string[];
  chart?: FlowChartDTO;
}
