import { describe, expect, it } from "vitest";
import { APP_TITLE, mainWindowTitle, pageTitle } from "./windowTitle";

describe("mainWindowTitle", () => {
  it("is the application name until a folder is open", () => {
    expect(mainWindowTitle(null, null)).toBe("Karma Pro");
    expect(APP_TITLE).toBe("Karma Pro");
  });

  it("names the project, and the file when one is shown", () => {
    expect(mainWindowTitle("app", null)).toBe("app Project");
    expect(mainWindowTitle("app", "App.java")).toBe("app Project (App.java)");
  });
});

describe("pageTitle", () => {
  it("is unchanged while no bug is open", () => {
    expect(pageTitle("app Project", 0)).toBe("app Project");
  });

  it("puts the open bug count in front", () => {
    expect(pageTitle("app Project (App.java)", 3)).toBe("(3) app Project (App.java)");
  });
});
