import { describe, expect, it } from "vitest";
import { scanCountText, serviceButtonTitle, statsText, statusText } from "./mcp";

describe("statusText", () => {
  it("names the port while the service runs", () => {
    expect(statusText({ running: true, port: 8765 })).toBe("Running on 127.0.0.1:8765");
  });

  it("says Stopped otherwise, whatever the last port was", () => {
    expect(statusText({ running: false, port: 8765 })).toBe("Stopped");
  });
});

describe("serviceButtonTitle", () => {
  it("offers the action that changes the current state", () => {
    expect(serviceButtonTitle(true)).toBe("Stop Service");
    expect(serviceButtonTitle(false)).toBe("Start Service");
  });
});

describe("scanCountText", () => {
  it("pluralises the scan count", () => {
    expect(scanCountText(0)).toBe("0 scans served this session");
    expect(scanCountText(1)).toBe("1 scan served this session");
    expect(scanCountText(4)).toBe("4 scans served this session");
  });
});

describe("statsText", () => {
  const now = new Date("2026-11-14T12:10:30Z");

  it("shows the scan count alone when no start time is known", () => {
    expect(statsText({ scanCount: 2, startedAt: undefined }, now)).toBe("2 scans served this session");
    expect(statsText({ scanCount: 2, startedAt: null }, now)).toBe("2 scans served this session");
  });

  it("adds the uptime in whole minutes", () => {
    expect(statsText({ scanCount: 1, startedAt: "2026-11-14T12:00:00Z" }, now)).toBe(
      "1 scan served this session · up 10 min",
    );
  });

  it("ignores an unreadable start time", () => {
    expect(statsText({ scanCount: 0, startedAt: "not a date" }, now)).toBe("0 scans served this session");
  });
});
