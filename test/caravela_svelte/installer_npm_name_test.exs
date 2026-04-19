defmodule CaravelaSvelte.InstallerNpmNameTest do
  @moduledoc """
  Regression coverage for bug_improvements_3.md §2.2 and the npm
  name inconsistency flagged alongside it.

  Pre-v0.1.1, `mix caravela_svelte.install` wrote `"caravela_svelte"`
  into the consumer app's `package.json` and `app.js` imports, while
  [package.json] publishes as `"@caravela/svelte"` and every doc
  example uses the scoped name. Users following the docs or the
  Hex badge hit import errors because the npm alias the installer
  wrote didn't match what the docs taught.

  We can't drive the Igniter task end-to-end in a plain ExUnit
  module (no host project), so this test reads the task source
  directly and verifies the key emission sites use the scoped
  name. String-level assertions are acceptable here because the
  emission sites are literal strings in the task file — any
  restructure that breaks these assertions would also force a
  rewrite of the test, which is fine.
  """

  use ExUnit.Case, async: true

  @installer_path Path.expand("../../lib/mix/tasks/caravela_svelte.install.ex", __DIR__)

  setup_all do
    {:ok, source: File.read!(@installer_path)}
  end

  describe "installer emits the scoped npm package name" do
    test "app.js imports use `@caravela/svelte`", %{source: src} do
      assert src =~ ~s(from "@caravela/svelte")

      refute src =~ ~s(from "caravela_svelte"),
             "installer still writes the unscoped `caravela_svelte` import — fix all call sites"
    end

    test "vite.config import references `@caravela/svelte/vitePlugin`", %{source: src} do
      assert src =~ ~s(from "@caravela/svelte/vitePlugin")
    end

    test "optimizeDeps.include lists `@caravela/svelte`", %{source: src} do
      assert src =~ ~s(include: ["@caravela/svelte",)
    end

    test "package.json dependency key is `@caravela/svelte`", %{source: src} do
      # The file path still points at `deps/caravela_svelte` (the Mix-
      # resolved directory) but the npm alias must be scoped so
      # imports resolve against what's on npmjs.org. `\1` is the
      # captured prefix from the Regex.replace — in the source file
      # it appears escaped as `\\1` (two literal backslashes), so the
      # search string needs four backslashes to compile to two.
      assert String.contains?(src, ~s("@caravela/svelte": "\\\\1/caravela_svelte"))
    end

    test "server.js snippet imports `@caravela/svelte`", %{source: src} do
      assert src =~ ~s|import { getRender } from "@caravela/svelte"|
    end
  end
end
