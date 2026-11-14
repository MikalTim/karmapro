import { describe, expect, it } from "vitest";
import { fileNameOf, matchRows, searchColumns, searchRequest, searchWindowTitle } from "./searchModel";

describe("searchWindowTitle", () => {
  it("names the language the window searches", () => {
    expect(searchWindowTitle("Swift")).toBe("Search in Files (Swift)");
  });

  it("has no language suffix for every file", () => {
    expect(searchWindowTitle(null)).toBe("Search in Files");
    expect(searchWindowTitle("All Languages")).toBe("Search in Files");
  });
});

describe("searchRequest", () => {
  it("sends the term and the language, leaving the language out for every file", () => {
    expect(searchRequest("strcpy", "C")).toEqual({ term: "strcpy", language: "C" });
    expect(JSON.stringify(searchRequest("strcpy", null))).toBe('{"term":"strcpy"}');
  });
});

describe("matchRows", () => {
  it("labels each match with its file name and line, and its text as the body", () => {
    const [first] = matchRows([{ path: "/project/src/vuln.c", relativePath: "src/vuln.c", line: 6, text: "  strcpy(buf, argv[1]);" }]);
    expect(first.head).toBe("vuln.c:6");
    expect(first.body).toBe("  strcpy(buf, argv[1]);");
    expect(first.id).toBe("/project/src/vuln.c:6");
  });
});

describe("fileNameOf", () => {
  it("returns the last path component", () => {
    expect(fileNameOf("/project/app.py")).toBe("app.py");
    expect(fileNameOf("app.py")).toBe("app.py");
  });
});

describe("searchColumns", () => {
  it("fills the table but is never narrower than 600", () => {
    expect(searchColumns(900)[0].width).toBe(900);
    expect(searchColumns(400)[0].width).toBe(600);
  });
});
