const parameterName = "encoding";
const payloadVersion = "v1.";

function bytesToBase64(bytes) {
  let binary = "";
  const chunkSize = 0x8000;

  for (let start = 0; start < bytes.length; start += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(start, start + chunkSize));
  }

  return btoa(binary);
}

function base64ToBytes(base64) {
  const binary = atob(base64);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

export function encodeSharedEncoding(encoding) {
  const base64 = bytesToBase64(new TextEncoder().encode(encoding));
  return payloadVersion + base64
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/, "");
}

export function decodeSharedEncoding(payload) {
  if (!payload.startsWith(payloadVersion)) {
    throw new Error("Unsupported shared encoding version.");
  }

  const base64URL = payload.slice(payloadVersion.length);
  if (!/^[A-Za-z0-9_-]*$/.test(base64URL) || base64URL.length % 4 === 1) {
    throw new Error("Malformed shared encoding.");
  }

  const base64 = base64URL
    .replaceAll("-", "+")
    .replaceAll("_", "/")
    .padEnd(Math.ceil(base64URL.length / 4) * 4, "=");
  return new TextDecoder("utf-8", { fatal: true }).decode(base64ToBytes(base64));
}

export function sharedEncodingFromURL(href) {
  const url = new URL(href);
  const parameters = new URLSearchParams(url.hash.slice(1));
  const payload = parameters.get(parameterName);

  if (payload === null) {
    return null;
  }

  try {
    const encoding = decodeSharedEncoding(payload);
    return /\S/u.test(encoding) ? encoding : null;
  } catch {
    return null;
  }
}

export function urlWithSharedEncoding(href, encoding) {
  const url = new URL(href);
  const parameters = new URLSearchParams();
  parameters.set(parameterName, encodeSharedEncoding(encoding));
  url.hash = parameters.toString();
  return url.href;
}

export function urlWithoutSharedEncoding(href) {
  const url = new URL(href);
  const parameters = new URLSearchParams(url.hash.slice(1));

  if (!parameters.has(parameterName)) {
    return url.href;
  }

  parameters.delete(parameterName);
  url.hash = parameters.toString();
  return url.href;
}
