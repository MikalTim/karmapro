// Wire types of the call and data-flow diagrams (`FlowService.DiagramGraphDTO` and the
// data-flow window's `FlowService.DataFlowDTO`). Swift omits nil optionals from the JSON,
// so those fields are optional here rather than `null`.

export interface GraphNodeDTO {
  name: string;
  path?: string;
  line?: number;
  /** Drawn as a square "origin" box (Internet, Local, the instantiating class). */
  isOrigin: boolean;
  /** Grey box with black text: the forward (callee) overlay. */
  isGreyed: boolean;
  /** Amber halo: the topmost boxes of an unverified reachability walk. */
  isOutlined: boolean;
  /** Origin box colour name ("orange"); absent means the accent colour. */
  originColor?: string;
}

export interface GraphEdgeDTO {
  from: string;
  to: string;
}

export interface DiagramGraphDTO {
  nodes: GraphNodeDTO[];
  /** Solid call edges; they also drive the layout ranking. */
  callEdges: GraphEdgeDTO[];
  /** Animated dashed data-flow edges. */
  dataEdges: GraphEdgeDTO[];
  highlight?: string;
  layoutDirection: "leftToRight" | "topToBottom";
  layoutSourceNodes: string[];
  layoutCenterNode?: string;
  /** When present, only these nodes (and the neighbours revealed from them) are drawn. */
  focusNodes?: string[];
  /** True when only the dashed data edges are drawn. */
  animatedOnlyEdges: boolean;
}

/** The look of the animated data-flow edges (`FlowEdgeStyle`). */
export interface DiagramFlowStyle {
  /** A CSS colour, for example `var(--system-red)`. */
  color: string;
  dashes: number[];
  lineWidth: number;
  /** Dash-phase drift per animation tick at 30 ticks per second. */
  phaseStep: number;
}

export interface DataFlowDTO {
  functionName: string;
  windowTitle: string;
  title: string;
  caption: string;
  /** Shown instead of the diagram when no flow was found in the file. */
  emptyMessage?: string;
  graph?: DiagramGraphDTO;
}
