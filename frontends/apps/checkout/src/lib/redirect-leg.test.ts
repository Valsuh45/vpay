import { describe, expect, it } from "vitest";

import {
  REDIRECT_LEG_STORAGE_PREFIX,
  clearRedirectLeg,
  recallRedirectLeg,
  rememberRedirectLeg,
} from "./redirect-leg";

describe("the sheet redirect-leg marker", () => {
  function memoryStorage(): Storage {
    const map = new Map<string, string>();
    return {
      get length() {
        return map.size;
      },
      clear: () => map.clear(),
      getItem: (k: string) => map.get(k) ?? null,
      key: (i: number) => Array.from(map.keys())[i] ?? null,
      removeItem: (k: string) => map.delete(k),
      setItem: (k: string, v: string) => void map.set(k, v),
    };
  }

  it("is present after remember and absent before, per session id", () => {
    const storage = memoryStorage();
    expect(recallRedirectLeg(storage, "cs_1")).toBe(false);
    rememberRedirectLeg(storage, "cs_1");
    expect(recallRedirectLeg(storage, "cs_1")).toBe(true);
    expect(recallRedirectLeg(storage, "cs_2")).toBe(false);
    expect(storage.getItem(`${REDIRECT_LEG_STORAGE_PREFIX}cs_1`)).toBe("1");
  });

  it("clears so a later normal web checkout in the same tab is not suppressed", () => {
    const storage = memoryStorage();
    rememberRedirectLeg(storage, "cs_1");
    clearRedirectLeg(storage, "cs_1");
    expect(recallRedirectLeg(storage, "cs_1")).toBe(false);
  });

  it("degrades to 'not a redirect leg' on a storage that throws, never a broken page", () => {
    const hostile = {
      getItem: () => {
        throw new Error("blocked");
      },
      setItem: () => {
        throw new Error("blocked");
      },
      removeItem: () => {
        throw new Error("blocked");
      },
    } as unknown as Storage;
    expect(() => rememberRedirectLeg(hostile, "cs_1")).not.toThrow();
    expect(recallRedirectLeg(hostile, "cs_1")).toBe(false);
    expect(() => clearRedirectLeg(hostile, "cs_1")).not.toThrow();
  });

  it("is given no storage at all without complaint", () => {
    expect(() => rememberRedirectLeg(null, "cs_1")).not.toThrow();
    expect(recallRedirectLeg(undefined, "cs_1")).toBe(false);
  });
});
