<script lang="ts">
  /**
   * Dynamic root component for REST mode. Reads the current page
   * object from `pageState` and renders whichever Svelte
   * component `resolveComponent` maps the name to.
   *
   * Consumers don't instantiate this directly — `initRest()`
   * mounts it as the REST-mode root.
   */

  import type { Component } from "svelte";
  import { pageState } from "./page-state";

  interface Props {
    resolveComponent: (name: string) => Component | null | undefined;
  }

  let { resolveComponent }: Props = $props();

  const current = $derived($pageState);
  const Comp = $derived(current ? resolveComponent(current.component) : null);

  $effect(() => {
    if (current && !Comp) {
      console.error(
        `[caravela_svelte] unknown component "${current.component}"`,
      );
    }
  });
</script>

{#if current && Comp}
  <Comp {...current.props} live={null} />
{/if}
