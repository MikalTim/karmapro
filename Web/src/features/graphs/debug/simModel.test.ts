import { describe, expect, it } from "vitest";
import {
  focusRange,
  frameColor,
  frameLabel,
  lineRange,
  playButtonTitle,
  stepProduced,
  watchNameStyle,
  type SimFrame,
} from "./simModel";

const frame: SimFrame = {
  index: 0,
  functionName: "copy",
  fileName: "util.c",
  path: "/project/src/util.c",
  line: 12,
  isActive: true,
  isDone: false,
  isSelected: true,
};

describe("lineRange", () => {
  it("gives the range of a line without its line break", () => {
    expect(lineRange("ab\ncd", 1)).toEqual({ location: 0, length: 2 });
    expect(lineRange("ab\ncd", 2)).toEqual({ location: 3, length: 2 });
  });

  it("is nil for a line the text does not have", () => {
    expect(lineRange("ab\ncd", 0)).toBeNull();
    expect(lineRange("ab\ncd", 3)).toBeNull();
  });
});

describe("focusRange", () => {
  const source = "a\nb\nc\nd";

  it("keeps the function's own lines in focus and dims the rest", () => {
    expect(
      focusRange({ bodyLines: { start: 2, end: 3 }, displayedPath: "/p/a.c", entryPath: "/p/a.c" }, source),
    ).toEqual({ location: 2, length: 3 });
  });

  it("dims nothing when the shown file is not the entry file", () => {
    expect(
      focusRange({ bodyLines: { start: 2, end: 3 }, displayedPath: "/p/b.c", entryPath: "/p/a.c" }, source),
    ).toBeNull();
  });

  it("dims nothing without a body", () => {
    expect(focusRange({ bodyLines: null, displayedPath: "/p/a.c", entryPath: "/p/a.c" }, source)).toBeNull();
  });
});

describe("stack and watch rows", () => {
  it("reads a frame as function, file and line", () => {
    expect(frameLabel(frame)).toBe("copy — util.c:12");
  });

  it("shows the active frame in blue and the others in the secondary colour", () => {
    expect(frameColor(frame)).toBe("color: var(--system-blue)");
    expect(frameColor({ ...frame, isActive: false })).toBe("color: var(--secondary-label)");
  });

  it("shows a changed variable in orange", () => {
    expect(watchNameStyle({ name: "n", value: "3", changed: true, isParameter: false })).toBe(
      "color: var(--system-orange)",
    );
    expect(watchNameStyle({ name: "n", value: "3", changed: false, isParameter: false })).toBeUndefined();
  });
});

describe("play", () => {
  it("titles the button Pause while playing", () => {
    expect(playButtonTitle(true)).toBe("Pause");
    expect(playButtonTitle(false)).toBe("Play");
  });

  it("goes on only while a step was taken", () => {
    expect(stepProduced({ stepCount: 4 }, { stepCount: 5 })).toBe(true);
    expect(stepProduced({ stepCount: 5 }, { stepCount: 5 })).toBe(false);
  });
});
