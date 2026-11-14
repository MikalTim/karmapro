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

/**
 * The rows the outline shows, top to bottom: a folder's children follow it while it is
 * open. A folder with no recorded state is open, as AppKit expands the whole tree.
 */
export function visibleNodes(nodes: FileTreeNode[], expanded: Record<string, boolean>): FileTreeNode[] {
  const rows: FileTreeNode[] = [];
  const walk = (list: FileTreeNode[]) => {
    for (const node of list) {
      rows.push(node);
      if (node.children && node.children.length > 0 && (expanded[node.id] ?? true)) walk(node.children);
    }
  };
  walk(nodes);
  return rows;
}

/**
 * The file the keyboard selection lands on when an arrow key moves onto `over`, a row that
 * cannot be selected: the next file in the direction of travel, or null at the end of the list.
 * `selected` is the file selected before the key press (null for none, which counts as moving down).
 */
export function nextSelectableFile(rows: FileTreeNode[], selected: string | null, over: FileTreeNode): FileTreeNode | null {
  const target = rows.findIndex((row) => row.id === over.id);
  const step = selected !== null && rows.findIndex((row) => row.id === selected) > target ? -1 : 1;
  for (let index = target + step; index >= 0 && index < rows.length; index += step) {
    if (openablePath(rows[index].data) !== null) return rows[index];
  }
  return null;
}
