import { describe, expect, it } from "vitest";
import {
  badgeColor,
  nodeLocation,
  outlineNodes,
  progressFraction,
  sitesText,
  traceDiagram,
  tracingCaption,
  type EntryGroup,
  type EntrySite,
  type EntryTrace,
} from "./entryPointsModel";

function site(id: string, overrides: Partial<EntrySite> = {}): EntrySite {
  return {
    id,
    path: "/project/src/vuln.c",
    relativePath: "src/vuln.c",
    line: 6,
    column: 5,
    apiName: "recv",
    apiPath: "socket.recv",
    category: "Network input",
    origin: "internet",
    confidence: "primary",
    entryVariable: "buf",
    snippet: "recv(fd, buf, n, 0);",
    displaySnippet: "recv(fd, buf, n, 0);",
    label: "src/vuln.c:6",
    sourceKind: "API call",
    ...overrides,
  };
}

function group(id: string, sites: EntrySite[]): EntryGroup {
  return {
    id,
    category: "Network input",
    origin: "internet",
    confidence: "primary",
    badge: "◉ remote",
    title: "Network input — 1 site",
    sites,
  };
}

const trace: EntryTrace = {
  siteID: "/project/src/vuln.c#42",
  caption: "Flow of “buf”",
  originLabel: "Remote",
  nodes: [
    { name: "Remote", isStart: false, isOrigin: true },
    { name: "main", path: "/project/src/vuln.c", line: 6, isStart: true, isOrigin: false },
    { name: "copy", path: "/project/src/util.c", line: 12, isStart: false, isOrigin: false },
  ],
  edges: [
    { from: "Remote", to: "main" },
    { from: "main", to: "copy" },
  ],
};

describe("sitesText", () => {
  it("pluralises the site count", () => {
    expect(sitesText(0)).toBe("0 sites");
    expect(sitesText(1)).toBe("1 site");
    expect(sitesText(2)).toBe("2 sites");
  });
});

describe("badgeColor", () => {
  it("colours remote entries blue and local ones green", () => {
    expect(badgeColor("internet")).toBe("var(--system-blue)");
    expect(badgeColor("local")).toBe("var(--system-green)");
  });
});

describe("outlineNodes", () => {
  it("lists each category with its sites as children, in order", () => {
    const nodes = outlineNodes([group("g1", [site("s1"), site("s2")]), group("g2", [])]);
    expect(nodes.map((node) => node.id)).toEqual(["g1", "g2"]);
    expect(nodes[0].children?.map((child) => child.id)).toEqual(["s1", "s2"]);
    expect(nodes[0].data.kind).toBe("group");
    expect(nodes[0].children?.[0].data.kind).toBe("site");
    expect(nodes[1].children).toEqual([]);
  });
});

describe("tracingCaption", () => {
  it("names the variable and the file's name without its folders", () => {
    expect(tracingCaption(site("s1"))).toBe("Tracing “buf” from vuln.c:6…");
  });
});

describe("traceDiagram", () => {
  it("is nil when the trace has no boxes, so the diagram stays empty", () => {
    expect(traceDiagram({ ...trace, nodes: [], edges: [] })).toBeNull();
  });

  it("draws the origin box on the top rank and highlights the entry box", () => {
    const graph = traceDiagram(trace);
    expect(graph?.highlight).toBe("main");
    expect(graph?.layoutDirection).toBe("topToBottom");
    expect(graph?.layoutSourceNodes).toEqual(["Remote"]);
    expect(graph?.animatedOnlyEdges).toBe(true);
    expect(graph?.nodes.find((node) => node.name === "Remote")?.isOrigin).toBe(true);
    expect(graph?.dataEdges).toEqual(trace.edges);
    expect(graph?.callEdges).toEqual(trace.edges);
  });

  it("pins nothing and highlights nothing when no box is the entry", () => {
    const graph = traceDiagram({
      ...trace,
      nodes: trace.nodes.map((node) => ({ ...node, isStart: false, isOrigin: false })),
    });
    expect(graph?.highlight).toBeUndefined();
    expect(graph?.layoutSourceNodes).toEqual([]);
  });
});

describe("nodeLocation", () => {
  it("opens the file and line of a flow box", () => {
    expect(nodeLocation(trace, "copy")).toEqual({ path: "/project/src/util.c", line: 12 });
  });

  it("opens nothing for the origin box or an unknown name", () => {
    expect(nodeLocation(trace, "Remote")).toBeNull();
    expect(nodeLocation(trace, "missing")).toBeNull();
  });
});

describe("progressFraction", () => {
  it("is done over total, and 0 while the total is unknown", () => {
    expect(progressFraction(3, 10)).toBeCloseTo(0.3);
    expect(progressFraction(0, 0)).toBe(0);
  });
});
