<script lang="ts">
  // The Licensing window (`LicensingWindowController`): the report the server builds
  // from the open project's license files, in a read-only monospaced view.
  import { onDestroy, onMount } from "svelte";
  import { api } from "../../../lib/api";
  import { runJob } from "../../../lib/jobs";
  import { errorText } from "./errorText";

  interface LicenseReport {
    report: string;
  }

  let { windowId }: { windowId: number } = $props();

  let report = $state("");
  let closed = false;

  onMount(async () => {
    try {
      const outcome = await runJob<LicenseReport>(api<{ jobId: string }>("POST", "/api/licenses")).promise;
      if (!closed && outcome.result) report = outcome.result.report;
    } catch (error) {
      if (!closed) report = errorText(error);
    }
  });

  onDestroy(() => {
    closed = true;
  });
</script>

<pre class="report">{report}</pre>

<style>
  .report {
    flex: 1;
    min-height: 0;
    margin: 0;
    padding: 15px;
    box-sizing: border-box;
    overflow: auto;
    background: var(--text-bg);
    color: var(--label);
    font: 13px/1.3 var(--font-mono);
    white-space: pre-wrap;
    overflow-wrap: anywhere;
    user-select: text;
  }
</style>
