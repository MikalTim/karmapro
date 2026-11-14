import { describe, expect, it } from "vitest";
import {
  NO_MODELS_CHOICE,
  NO_PROJECT_FOR_SCAN,
  exportProblem,
  exportedAlert,
  hasProjectRoot,
  importedFromURLStatus,
  keptChoice,
  messageOf,
  modelAddress,
  modelChoice,
  modelPopupTitles,
  progressFraction,
  scanRequest,
  scanningStatus,
  trainRequest,
  type MLLanguageDTO,
} from "./mlModel";

const languages: MLLanguageDTO[] = [
  { name: "All Languages", extensions: [] },
  { name: "C / C++", extensions: [".c", ".cpp", ".h"] },
];

describe("trainRequest", () => {
  it("asks for a patch folder first", () => {
    expect(trainRequest(null, "", "C / C++")).toEqual({
      problem: {
        message: "No patch folder chosen",
        informative: "Use “Choose Patch Folder…” to select a directory of patches first.",
      },
    });
  });

  it("then asks for a model name, which may not be blank", () => {
    expect(trainRequest("/patches", "   ", "C / C++")).toEqual({
      problem: { message: "No model name", informative: "Enter a name for the training model." },
    });
  });

  it("sends the trimmed name with the folder and language", () => {
    expect(trainRequest("/patches", "  CVE-2024  ", "C / C++")).toEqual({
      value: { folder: "/patches", language: "C / C++", name: "CVE-2024" },
    });
  });
});

describe("modelAddress", () => {
  it("rejects a blank address", () => {
    expect(modelAddress("   ")).toEqual({
      problem: { message: "Invalid URL", informative: "Enter a valid web address." },
    });
  });

  it("rejects text that is not a web address", () => {
    expect("problem" in modelAddress("not a url")).toBe(true);
  });

  it("returns the trimmed address", () => {
    expect(modelAddress("  https://example.com/model.json  ")).toEqual({
      value: { url: "https://example.com/model.json" },
    });
  });
});

describe("export and import texts", () => {
  it("says there is nothing to export when the library is empty", () => {
    expect(exportProblem([])).toEqual({ message: "No Models", informative: "There are no trained models to export yet." });
    expect(exportProblem(["a"])).toBeNull();
  });

  it("names the file that was exported", () => {
    expect(exportedAlert("base", "base.karmamodel")).toEqual({
      message: "Exported",
      informative: "Model “base” exported to base.karmamodel",
    });
  });

  it("reports a URL import in the status line", () => {
    expect(importedFromURLStatus("base")).toBe("Imported model “base” from URL.");
  });
});

describe("popup choices", () => {
  it("keeps the current choice while it is still offered", () => {
    expect(keptChoice("b", ["a", "b"])).toBe("b");
  });

  it("selects the first item when the current one is gone", () => {
    expect(keptChoice("gone", ["a", "b"])).toBe("a");
    expect(keptChoice("gone", [])).toBe("");
  });

  it("shows the placeholder and selects it while there are no models", () => {
    expect(modelPopupTitles([])).toEqual([NO_MODELS_CHOICE]);
    expect(modelChoice("a", [])).toBe(NO_MODELS_CHOICE);
  });

  it("selects a model once the library has one", () => {
    expect(modelChoice(NO_MODELS_CHOICE, ["a", "b"])).toBe("a");
    expect(modelPopupTitles(["a", "b"])).toEqual(["a", "b"]);
  });
});

describe("progressFraction", () => {
  it("is done over total", () => {
    expect(progressFraction(1, 4)).toBe(0.25);
  });

  it("is zero before the job has a total", () => {
    expect(progressFraction(0, 0)).toBe(0);
  });
});

describe("scanRequest", () => {
  const ready = { hasRoot: true, model: "base", languages, language: "C / C++", threshold: 70 };

  it("needs an open folder before a model", () => {
    expect(scanRequest({ ...ready, hasRoot: false, model: "" })).toEqual({
      problem: { message: "No Folder Open", informative: "Open a source folder first." },
    });
  });

  it("needs a trained model", () => {
    expect(scanRequest({ ...ready, model: NO_MODELS_CHOICE })).toEqual({
      problem: { message: "No Model", informative: "Choose a trained model." },
    });
    expect(scanRequest({ ...ready, model: "" })).toEqual({
      problem: { message: "No Model", informative: "Choose a trained model." },
    });
  });

  it("sends the language's extensions and the threshold percentage", () => {
    expect(scanRequest(ready)).toEqual({
      value: { model: "base", extensions: [".c", ".cpp", ".h"], threshold: 70 },
    });
  });

  it("sends no extensions for All Languages, which means every file", () => {
    const request = scanRequest({ ...ready, language: "All Languages" });
    expect(request).toEqual({ value: { model: "base", extensions: [], threshold: 70 } });
  });

  it("sends no extensions for a language it does not know", () => {
    const request = scanRequest({ ...ready, language: "Unknown" });
    expect(request).toEqual({ value: { model: "base", extensions: [], threshold: 70 } });
  });
});

describe("status and entry texts", () => {
  it("names the model while a scan runs", () => {
    expect(scanningStatus("base")).toBe("Scanning with model “base”…");
  });

  it("is the menu's No Folder Open alert", () => {
    expect(NO_PROJECT_FOR_SCAN).toEqual({
      message: "No Folder Open",
      informative: "Open a source folder before running an ML scan.",
    });
  });

  it("finds an open folder only when the root is a path", () => {
    expect(hasProjectRoot({ root: "/work/app" })).toBe(true);
    expect(hasProjectRoot({ root: null })).toBe(false);
    expect(hasProjectRoot({})).toBe(false);
    expect(hasProjectRoot({ root: "" })).toBe(false);
  });

  it("reads the message of any thrown value", () => {
    expect(messageOf(new Error("boom"))).toBe("boom");
    expect(messageOf("plain")).toBe("plain");
  });
});
