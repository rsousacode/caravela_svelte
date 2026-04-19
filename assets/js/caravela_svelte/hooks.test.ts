// Vitest tests for getHooks' `asComponentResolver` contract.
// These verify the three input shapes getHooks/1 accepts without
// mounting a real LiveView — we only exercise the resolver that
// `hooks.svelte.js` builds internally.
//
// The resolver isn't exported directly because it's an
// implementation detail; instead we exercise the same contract
// through getHooks by observing which shape it survives without
// throwing. A "survives" observation only tells us getHooks
// accepted the input; to verify the shape resolves a named
// component we'd need to mount via Phoenix, which lives outside
// this package. Enough to catch the regression §2.1 flagged.

import { describe, it, expect } from "vitest";
import { getHooks } from "./hooks.svelte";

describe("getHooks — component input shapes", () => {
  it("accepts a pre-built `{ [name]: Component }` map", () => {
    const Component = { svelte: "stub" };
    const hooks = getHooks({ "library/BookIndex": Component });

    expect(hooks).toHaveProperty("CaravelaSvelteHook");
    expect(typeof hooks.CaravelaSvelteHook.mounted).toBe("function");
  });

  it("accepts the Vite `import.meta.glob` shape", () => {
    const shape = {
      default: [{ default: { svelte: "stub" } }],
      filenames: ["../svelte/library/BookIndex.svelte"],
    };

    const hooks = getHooks(shape);
    expect(hooks).toHaveProperty("CaravelaSvelteHook");
  });

  it("accepts a `{ resolveComponent }` shape (v0.1.1+)", () => {
    // Shape parity with `initRest({ resolveComponent })`. Lets an
    // app use one loader pattern across both runtimes.
    const hooks = getHooks({
      resolveComponent: (_name: string) => ({ svelte: "stub" }),
    });

    expect(hooks).toHaveProperty("CaravelaSvelteHook");
  });

  it("does not mutate a pre-built map on repeat calls", () => {
    const Component = { svelte: "stub" };
    const input = { "library/BookIndex": Component };
    const before = { ...input };

    getHooks(input);
    getHooks(input);

    expect(input).toEqual(before);
  });
});
