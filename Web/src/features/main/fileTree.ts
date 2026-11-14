// The sidebar's rows (`FileTreeViewController`). The server does the filtering
// (language, pull request pruning, search); this shapes its reply for the outline
// and decides how each row reads.
import type { FileNodeDTO, ProjectTreeDTO } from "./project";

export interface FileRow {
  name: string;
  path: string;
  isDirectory: boolean;
  /** "A" or "M" for a file the open pull request adds or changes. */
  badge: string | null;
}

export interface FileTreeNode {
  id: string;
  data: FileRow;
  children?: FileTreeNode[];
}

export type BadgeTone = "added" | "modified";

export interface RowLabel {
  text: string;
  tone: BadgeTone | null;
}

function toNode(node: FileNodeDTO): FileTreeNode {
  return {
    id: node.path,
    data: { name: node.name, path: node.path, isDirectory: node.isDirectory, badge: node.badge ?? null },
    children: node.children ? node.children.map(toNode) : undefined,
  };
}

/** The outline's nodes for a reply. A search reply is a flat list, however deep its files are. */
export function treeNodes(tree: ProjectTreeDTO | null): FileTreeNode[] {
  if (!tree) return [];
  if (tree.matches) return tree.matches.map(toNode);
  return tree.root ? [toNode(tree.root)] : [];
}

/** `"A  name"` in green for an added file and `"M  name"` in orange for a changed one. */
export function rowLabel(row: FileRow): RowLabel {
  if (row.isDirectory || row.badge === null) return { text: row.name, tone: null };
  return { text: `${row.badge}  ${row.name}`, tone: row.badge === "A" ? "added" : "modified" };
}

/** The file a row opens, or null for a folder, which the tree never opens on a click. */
export function openablePath(row: FileRow): string | null {
  return row.isDirectory ? null : row.path;
}
