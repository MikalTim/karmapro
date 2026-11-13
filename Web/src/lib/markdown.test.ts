import { describe, expect, it } from "vitest";
import { escapeHtml, renderMarkdown } from "./markdown";

describe("renderMarkdown", () => {
  it("renders headings as bold text without the hashes", () => {
    expect(renderMarkdown("## Title")).toBe('<span class="md-bold">Title</span>\n');
  });

  it("styles bold runs and leaves a single * after a space literal", () => {
    expect(renderMarkdown("a **b** c *d* e")).toBe(
      '<span class="md-plain">a </span><span class="md-bold">b</span><span class="md-plain"> c *d* e</span>\n',
    );
  });

  it("leaves an unbalanced ** literal", () => {
    expect(renderMarkdown("a ** b")).toBe('<span class="md-plain">a ** b</span>\n');
  });

  it("styles inline code and keeps emphasis markers inside it literal", () => {
    expect(renderMarkdown("run `a**b` now")).toBe(
      '<span class="md-plain">run </span><span class="md-code-inline">a**b</span><span class="md-plain"> now</span>\n',
    );
  });

  it("renders fenced blocks without the language tag line", () => {
    expect(renderMarkdown("before\n```c\nint x = 1;\n```\nafter")).toBe(
      '<span class="md-plain">before</span>\n\n<span class="md-code-block">int x = 1;\n</span>\n<span class="md-plain">after</span>\n',
    );
  });

  it("keeps the first fence line when it is code, not a language tag", () => {
    expect(renderMarkdown("```\nint x;\n```")).toContain("int x;");
    expect(renderMarkdown("```a b\nc\n```")).toContain("a b");
  });

  it("hugging italic markers become italic", () => {
    expect(renderMarkdown("x*y*z")).toBe(
      '<span class="md-plain">x</span><span class="md-italic">y</span><span class="md-plain">z</span>\n',
    );
  });

  it("repeats the text before an unmatched italic marker, as the AppKit renderer does", () => {
    expect(renderMarkdown("x*y")).toBe('<span class="md-plain">x</span><span class="md-plain">x*y</span>\n');
  });

  it("escapes HTML everywhere", () => {
    expect(renderMarkdown("<img src=x onerror=1>")).not.toContain("<img");
    expect(renderMarkdown("```\n<b>\n```")).toContain("&lt;b&gt;");
    expect(renderMarkdown("# <i>")).toContain("&lt;i&gt;");
    expect(escapeHtml(`&<>"'`)).toBe("&amp;&lt;&gt;&quot;&#39;");
  });
});
