import { describe, expect, it } from "vitest";

import { decideRedirectLegEntry } from "./redirect";

const SECRET = "cs_123_secret_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

describe("the /c/{id}/redirect page", () => {
  it("reads the key from the query and the secret from the fragment", () => {
    expect(
      decideRedirectLegEntry({
        search: "?key=pk_test_1",
        hash: `#${SECRET}`,
      }),
    ).toEqual({
      kind: "ready",
      key: "pk_test_1",
      clientSecret: SECRET,
    });
  });

  it("names the missing half of a broken link", () => {
    expect(decideRedirectLegEntry({ search: "", hash: `#${SECRET}` })).toEqual({
      kind: "error",
      code: "error.missing_key",
    });
    expect(
      decideRedirectLegEntry({ search: "?key=pk_test_1", hash: "" }),
    ).toEqual({
      kind: "error",
      code: "error.missing_secret",
    });
  });
});
