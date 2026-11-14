// A press on a node of a call diagram opens the node's file at its line. Nodes
// without a location (the Remote, Local and Topmost origin boxes, the class node)
// do nothing, as in AppKit.
import type { DiagramGraphDTO } from "../flow";
import { showFileInMainWindow } from "../../main/navigation";

export function openGraphNode(graph: DiagramGraphDTO, name: string): void {
  const node = graph.nodes.find((candidate) => candidate.name === name);
  if (node?.path && node.line) showFileInMainWindow(node.path, node.line);
}
