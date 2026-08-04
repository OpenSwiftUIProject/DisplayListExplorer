import test from "node:test";
import assert from "node:assert/strict";
import {
  decodeSharedEncoding,
  encodeSharedEncoding,
  sharedEncodingFromURL,
  urlWithSharedEncoding,
  urlWithoutSharedEncoding,
} from "../url-state.js";

test("shared encodings round-trip UTF-8 text through Base64URL", () => {
  const encoding = "(DL(I:7 C)(I:8(E O(I:9 V:空视图))))";
  const payload = encodeSharedEncoding(encoding);

  assert.match(payload, /^v1\.[A-Za-z0-9_-]+$/);
  assert.equal(decodeSharedEncoding(payload), encoding);
});

test("shared URL preserves the deployment path and query", () => {
  const encoding = "(DL(I:42 C))";
  const href = urlWithSharedEncoding(
    "https://example.com/DisplayListExplorer/?preview=1#top",
    encoding,
  );
  const url = new URL(href);

  assert.equal(url.pathname, "/DisplayListExplorer/");
  assert.equal(url.search, "?preview=1");
  assert.equal(sharedEncodingFromURL(href), encoding);
});

test("invalid or unsupported shared payloads are ignored", () => {
  assert.equal(sharedEncodingFromURL("https://example.com/#encoding=v2.abc"), null);
  assert.equal(sharedEncodingFromURL("https://example.com/#encoding=v1.%25"), null);
  assert.equal(sharedEncodingFromURL("https://example.com/#encoding=v1."), null);
});

test("clearing an encoding preserves unrelated fragment parameters", () => {
  const href = urlWithoutSharedEncoding(
    "https://example.com/#tab=statistics&encoding=v1.REw",
  );

  assert.equal(href, "https://example.com/#tab=statistics");
});
