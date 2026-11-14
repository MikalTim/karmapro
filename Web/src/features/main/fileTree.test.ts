import { describe, expect, it } from "vitest";
import { nextSelectableFile, openablePath, rowLabel, treeNodes, visibleNodes } from "./fileTree";
import type { FileNodeDTO, ProjectTreeDTO } from "./project";

const app: FileNodeDTO = {
  name: "app",
  path: "/work/app",
  isDirectory: true,
  children: [
    { name: "src", path: "/work/app/src", isDirectory: true, children: [
      { name: "Main.java", path: "/work/app/src/Main.java", isDirectory: false, badge: "A" },
    ] },
    { name: "README.md", path: "/work/app/README.md", isDirectory: false, badge: "M" },
    { name: "util.c", path: "/work/app/util.c", isDirectory: false },
  ],
};

describe("treeNodes", () => {
  it("is empty while no project is open", () => {
    expect(treeNodes(null)).toEqual([]);
    expect(treeNodes({ root: null, matches: null })).toEqual([]);
  });

  it("shows the project folder as the single top node, with its children nested", () => {
    const [top] = treeNodes({ root: app });
    expect(top.data.name).toBe("app");
    expect(top.children?.map((node) => node.data.name)).toEqual(["src", "README.md", "util.c"]);
    expect(top.children?.[0].children?.[0].data.path).toBe("/work/app/src/Main.java");
  });

  it("keeps the badge the server sent for each file", () => {
    const [top] = treeNodes({ root: app });
    expect(top.children?.[0].children?.[0].data.badge).toBe("A");
    expect(top.children?.[1].data.badge).toBe("M");
    expect(top.children?.[2].data.badge).toBeNull();
  });

  it("lists a search reply as a flat list in the order the server gave", () => {
    const search: ProjectTreeDTO = {
      root: null,
      matches: [
        { name: "Main.java", path: "/work/app/src/Main.java", isDirectory: false },
        { name: "src", path: "/work/app/src", isDirectory: true },
      ],
    };
    const nodes = treeNodes(search);
    expect(nodes.map((node) => node.data.name)).toEqual(["Main.java", "src"]);
    expect(nodes.every((node) => node.children === undefined)).toBe(true);
  });
});

describe("rowLabel", () => {
  it("writes an added file's badge in front of its name, in the added tone", () => {
    const row = { name: "Main.java", path: "/x", isDirectory: false, badge: "A" };
    expect(rowLabel(row)).toEqual({ text: "A  Main.java", tone: "added" });
  });

  it("uses the modified tone for any other badge", () => {
    const row = { name: "README.md", path: "/x", isDirectory: false, badge: "M" };
    expect(rowLabel(row)).toEqual({ text: "M  README.md", tone: "modified" });
  });

  it("shows a plain name when there is no badge or the row is a folder", () => {
    expect(rowLabel({ name: "util.c", path: "/x", isDirectory: false, badge: null })).toEqual({
      text: "util.c",
      tone: null,
    });
    expect(rowLabel({ name: "src", path: "/x/src", isDirectory: true, badge: "A" })).toEqual({
      text: "src",
      tone: null,
    });
  });
});

describe("openablePath", () => {
  it("opens a file and never a folder", () => {
    expect(openablePath({ name: "util.c", path: "/x/util.c", isDirectory: false, badge: null })).toBe("/x/util.c");
    expect(openablePath({ name: "src", path: "/x/src", isDirectory: true, badge: null })).toBeNull();
  });
});

describe("visibleNodes", () => {
  const [top] = treeNodes({ root: app });

  it("lists every row while all folders are open, which is how a loaded tree starts", () => {
    expect(visibleNodes([top], {}).map((node) => node.data.name)).toEqual([
      "app",
      "src",
      "Main.java",
      "README.md",
      "util.c",
    ]);
  });

  it("leaves out the children of a folder recorded as closed", () => {
    expect(visibleNodes([top], { "/work/app/src": false }).map((node) => node.data.name)).toEqual([
      "app",
      "src",
      "README.md",
      "util.c",
    ]);
  });
});

describe("nextSelectableFile", () => {
  // Rows: app, a.c, dir, b.c, c.c
  const mixed: FileNodeDTO = {
    name: "app",
    path: "/w",
    isDirectory: true,
    children: [
      { name: "a.c", path: "/w/a.c", isDirectory: false },
      { name: "dir", path: "/w/dir", isDirectory: true, children: [{ name: "b.c", path: "/w/dir/b.c", isDirectory: false }] },
      { name: "c.c", path: "/w/c.c", isDirectory: false },
    ],
  };
  const rows = visibleNodes(treeNodes({ root: mixed }), {});

  it("moves on to the next file when the arrow key goes down onto a folder", () => {
    expect(nextSelectableFile(rows, "/w/a.c", rows[2])?.data.name).toBe("b.c");
    expect(nextSelectableFile(rows, null, rows[0])?.data.name).toBe("a.c");
  });

  it("moves to the previous file when the arrow key goes up onto a folder", () => {
    expect(nextSelectableFile(rows, "/w/dir/b.c", rows[2])?.data.name).toBe("a.c");
  });

  it("returns null when no file lies beyond the folder", () => {
    expect(nextSelectableFile(rows, "/w/a.c", rows[0])).toBeNull();
  });
});
