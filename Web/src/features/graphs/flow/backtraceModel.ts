// Wire types of the backtrace analyser (`FlowService.BacktraceDTO`).

export interface BacktraceFrameDTO {
  functionName: string;
  fileHint: string;
  /** Absent when the file is not part of the open project. */
  path?: string;
  line: number;
}

export interface BacktraceWarningDTO {
  messageText: string;
  informativeText: string;
}

export interface BacktraceDTO {
  frames: BacktraceFrameDTO[];
  status: string;
  /** Absent when every frame resolved. */
  warning?: BacktraceWarningDTO;
}
