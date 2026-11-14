import { describe, expect, it } from "vitest";
import {
  needsPermissionRequest,
  notifyStyleOf,
  toastKey,
  withoutToast,
  withToast,
  type PRToast,
} from "./notifyPolicy";
import type { PRState } from "./prTypes";

function stateWithStyle(selected: string | null): PRState {
  return {
    monitoringEnabled: true,
    pollingIntervalMinutes: 15,
    depthChoices: [],
    notifyChoices: ["off", "banner", "bannerAndSound"].map((value) => ({
      value,
      title: value,
      selected: value === selected,
    })),
    items: [],
    repoCount: 1,
    gitAvailable: true,
  };
}

describe("notifyStyleOf", () => {
  it("reads the style the server marks as selected", () => {
    expect(notifyStyleOf(stateWithStyle("bannerAndSound"))).toBe("bannerAndSound");
  });

  it("treats no selection as off, so nothing is asked for", () => {
    expect(notifyStyleOf(stateWithStyle(null))).toBe("off");
  });
});

describe("needsPermissionRequest", () => {
  it("asks while alerts are wanted and the browser has not answered", () => {
    expect(needsPermissionRequest("banner", "default")).toBe(true);
    expect(needsPermissionRequest("bannerAndSound", "default")).toBe(true);
  });

  it("does not ask when alerts are off", () => {
    expect(needsPermissionRequest("off", "default")).toBe(false);
  });

  it("does not ask again once the browser has answered, or when it cannot ask", () => {
    expect(needsPermissionRequest("banner", "granted")).toBe(false);
    expect(needsPermissionRequest("banner", "denied")).toBe(false);
    expect(needsPermissionRequest("banner", "unsupported")).toBe(false);
  });
});

describe("toasts", () => {
  const first = { repoID: "repo-1", prID: 12, title: "owner/name #12", body: "#12 Fix login \u2014 ada" };
  const second = { repoID: "repo-1", prID: 13, title: "owner/name #13", body: "#13 Add tests \u2014 grace" };

  it("keys a toast by repository and pull request, so one pull request is one toast", () => {
    expect(toastKey(first)).toBe(toastKey({ repoID: "repo-1", prID: 12 }));
    expect(toastKey(first)).not.toBe(toastKey(second));
    expect(toastKey({ repoID: "a", prID: 1 })).not.toBe(toastKey({ repoID: "a1", prID: 0 }));
  });

  it("adds new notices at the end and replaces a notice for the same pull request", () => {
    const afterFirst = withToast([], first);
    const afterSecond = withToast(afterFirst, second);
    const refreshed = withToast(afterSecond, { ...first, body: "updated" });

    expect(afterSecond.map((toast) => toast.prID)).toEqual([12, 13]);
    expect(refreshed.map((toast) => toast.prID)).toEqual([13, 12]);
    expect(refreshed[1].body).toBe("updated");
  });

  it("removes a notice by its key and keeps the rest", () => {
    const toasts: PRToast[] = withToast(withToast([], first), second);
    const remaining = withoutToast(toasts, toastKey(first));

    expect(remaining.map((toast) => toast.title)).toEqual(["owner/name #13"]);
  });
});
