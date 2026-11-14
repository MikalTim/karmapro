import { describe, expect, it } from "vitest";
import { HELP_SPLASH_SRC, withSplashSource } from "./help";

describe("withSplashSource", () => {
  it("points the splash picture at the image source, whichever quote style the page uses", () => {
    const html = `<img src='${HELP_SPLASH_SRC}' style='max-width:320px'/><img src="${HELP_SPLASH_SRC}">`;

    expect(withSplashSource(html, "data:image/jpeg;base64,AAAA")).toBe(
      "<img src='data:image/jpeg;base64,AAAA' style='max-width:320px'/><img src=\"data:image/jpeg;base64,AAAA\">",
    );
  });

  it("leaves other images and text alone", () => {
    const html = "<p>See /api/resources/SplashImage.jpg</p><img src='https://example.test/a.png'/>";

    expect(withSplashSource(html, "data:image/jpeg;base64,AAAA")).toBe(html);
  });
});
