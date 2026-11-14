import { describe, expect, it } from "vitest";
import { accountColumns, accountsExplanation, afterSave, asksForProvider, type AccountFormState } from "./accounts";
import type { AccountDTO, ProviderDTO } from "./dto";

const github: ProviderDTO = {
  id: "github",
  name: "GitHub",
  tokenPlaceholder: "read-only token",
  hostPlaceholder: "host, e.g. gitlab.com",
  hostEnabled: true,
  defaultHost: "github.com",
};

const bitbucket: ProviderDTO = {
  id: "bitbucket",
  name: "Bitbucket",
  tokenPlaceholder: "app password (read-only)",
  hostPlaceholder: "bitbucket.org (Cloud only)",
  hostEnabled: false,
  defaultHost: "bitbucket.org",
};

const account: AccountDTO = {
  identity: "gitlab|gitlab.example.com|alice",
  provider: "gitlab",
  providerName: "GitLab",
  host: "gitlab.example.com",
  username: "alice",
  tokenStatus: "not checked",
};

describe("account table", () => {
  it("has the four AppKit columns with their widths", () => {
    expect(accountColumns.map((column) => [column.id, column.title, column.width])).toEqual([
      ["Provider", "Provider", 130],
      ["Host", "Host", 160],
      ["Account", "Account", 150],
      ["Token", "Token", 80],
    ]);
  });

  it("shows the provider name, host, username and token status of an account", () => {
    expect(accountColumns.map((column) => column.value?.(account))).toEqual([
      "GitLab",
      "gitlab.example.com",
      "alice",
      "not checked",
    ]);
  });
});

describe("provider host", () => {
  it("asks the server only for an editable host that has text", () => {
    expect(asksForProvider(github, "gitlab.com")).toBe(true);
    expect(asksForProvider(github, "   ")).toBe(false);
    expect(asksForProvider(github, "")).toBe(false);
  });

  it("never asks for Bitbucket, whose host field is disabled", () => {
    expect(asksForProvider(bitbucket, "bitbucket.org")).toBe(false);
  });

  it("never asks before the provider list has loaded", () => {
    expect(asksForProvider(undefined, "gitlab.com")).toBe(false);
  });
});

describe("account form", () => {
  it("clears only the token after a save", () => {
    const form: AccountFormState = {
      providerId: "gitlab",
      host: "gitlab.example.com",
      username: "alice",
      token: "glpat-secret",
    };

    expect(afterSave(form)).toEqual({ ...form, token: "" });
  });
});

describe("account explanation", () => {
  it("names the Keychain on macOS and the owner-only file elsewhere", () => {
    const macOS = accountsExplanation("macos").join("\n");
    const linux = accountsExplanation("linux").join("\n");

    expect(macOS).toContain("stored in your macOS Keychain");
    expect(linux).not.toContain("Keychain");
    expect(linux).toContain("mode 0600");
  });

  it("uses the macOS wording while the platform is still unknown", () => {
    expect(accountsExplanation(null)).toEqual(accountsExplanation("macos"));
  });

  it("keeps the AppKit paragraphs", () => {
    const [heading, , publicRepos] = accountsExplanation("macos");

    expect(heading).toBe("Read-only credentials for private repositories.");
    expect(publicRepos).toBe("Public repositories need no account at all — you only need one for repositories you mark private.");
  });
});
