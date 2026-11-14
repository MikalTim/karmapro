// The source viewer's routes (`Sources/KarmaServer/FileRoutes.swift`) and the DTOs of
// `Sources/KarmaCore/service/FileService.swift` they return. Offsets are UTF-16 indexes into the file text.
import type { ComponentProps } from "svelte";
import type { DataFlowDiagram } from "../graphs";
import { api, withQuery } from "../../lib/api";

export interface TokenDTO {
  location: number;
  length: number;
  kind: string;
}

export interface NamedRangeDTO {
  name: string;
  location: number;
  length: number;
}

export interface MLLineDTO {
  line: number;
  probability: number;
  text: string;
}

export interface FileDTO {
  path: string;
  text: string;
  ext: string;
  tokens: TokenDTO[];
  functionRanges: NamedRangeDTO[];
  classRanges: NamedRangeDTO[];
  callSites: NamedRangeDTO[];
  noteLines: number[];
  mlLines: MLLineDTO[];
}

export interface FlowArrowDTO {
  fromLine: number;
  toLine: number;
  kind: string;
}

export interface FlowArrowsDTO {
  arrows: FlowArrowDTO[];
  lineStarts: number[];
}

export interface FocusChipDTO {
  name: string;
  path: string;
}

export interface FocusDTO {
  function: string;
  bodyLocation: number;
  bodyLength: number;
  callers: FocusChipDTO[];
  callees: FocusChipDTO[];
}

export interface ContextMenuDTO {
  copyEnabled: boolean;
  flowArrowsTitle: string;
  flowArrowsOn: boolean;
  exitFocusAvailable: boolean;
  /** Absent when the pointer is not on a clickable function name: the server leaves nil optionals out. */
  functionName?: string;
  flowDiagramSupported: boolean;
  /** Absent when no identifier is under the pointer or in the selection. */
  variableName?: string;
  variableFlowLocation: number;
  lineNumber: number;
  lineText: string;
}

export interface DefinitionDTO {
  path: string;
  text: string;
  line: number;
  name: string;
}

/** The graph the data-flow diagram draws; the wire type is the prop type of `DataFlowDiagram`. */
export type DiagramGraph = NonNullable<ComponentProps<typeof DataFlowDiagram>["graph"]>;

export interface DataFlowDTO {
  functionName: string;
  windowTitle: string;
  title: string;
  caption: string;
  /** Absent when the pane draws a diagram; an empty string when there is nothing to draw. */
  emptyMessage?: string;
  /** Absent when there is nothing to draw (the pane is hidden). */
  graph?: DiagramGraph;
}

/** `{"text": …}` as `/api/file/type` and the notes route answer it. */
export interface TextDTO {
  text: string | null;
}

export function loadFile(path: string): Promise<FileDTO> {
  return api<FileDTO>("GET", withQuery("/api/file", { path }));
}

export function loadFlowArrows(path: string): Promise<FlowArrowsDTO> {
  return api<FlowArrowsDTO>("GET", withQuery("/api/file/flow-arrows", { path }));
}

/** Null when the function has no body in this file. */
export function loadFocus(path: string, functionName: string): Promise<FocusDTO | null> {
  return api<FocusDTO | null>("GET", withQuery("/api/file/focus", { path, function: functionName }));
}

export function loadContextMenu(
  path: string,
  location: number,
  selection: { location: number; length: number },
  flags: { flowArrowsOn: boolean; focusActive: boolean },
): Promise<ContextMenuDTO> {
  return api<ContextMenuDTO>(
    "GET",
    withQuery("/api/file/context-menu", {
      path,
      location,
      selectionLocation: selection.location,
      selectionLength: selection.length,
      flowArrowsOn: flags.flowArrowsOn ? 1 : 0,
      focusActive: flags.focusActive ? 1 : 0,
    }),
  );
}

export async function loadTypeAt(path: string, location: number): Promise<string | null> {
  const reply = await api<TextDTO>("GET", withQuery("/api/file/type", { path, location }));
  return reply.text;
}

export function loadDataFlow(path: string, functionName: string): Promise<DataFlowDTO> {
  return api<DataFlowDTO>("GET", withQuery("/api/file/dataflow", { path, function: functionName }));
}

/** Null when the project index is not ready or nothing defines `name`. */
export function resolveCall(path: string, name: string): Promise<DefinitionDTO | null> {
  return api<DefinitionDTO | null>("POST", "/api/file/resolve-call", { path, name });
}

export function loadDefinition(path: string, nameOffset: number): Promise<DefinitionDTO> {
  return api<DefinitionDTO>("GET", withQuery("/api/definition", { path, nameOffset }));
}
