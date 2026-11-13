<script lang="ts">
  import Window from "./Window.svelte";
  import { windowStore } from "./windows.svelte";
</script>

{#each windowStore.list as win (win.id)}
  {@const Content = win.spec.component}
  <Window {win}>
    <Content {...win.spec.props} windowId={win.id} />
  </Window>
{/each}
