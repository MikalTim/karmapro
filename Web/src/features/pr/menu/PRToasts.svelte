<script lang="ts">
  // The in-page notices for new pull requests: the page's own copy of the system notice, with the actions a
  // browser notice cannot show (`PRNotifier`'s Review and Ignore). The close button is "Not Now".
  import { X } from "@lucide/svelte";
  import { dismissToast, toastList } from "./toasts.svelte";
  import { ignorePullRequest, reviewPullRequest } from "./reviewActions";
  import type { PRToast } from "./notifyPolicy";

  function review(toast: PRToast) {
    dismissToast(toast.key);
    void reviewPullRequest(toast.repoID, toast.prID);
  }

  function ignore(toast: PRToast) {
    dismissToast(toast.key);
    void ignorePullRequest(toast.repoID, toast.prID);
  }
</script>

<div class="toasts">
  {#each toastList.list as toast (toast.key)}
    <div class="toast" role="alert">
      <div class="head">
        <span class="title">{toast.title}</span>
        <button class="close" title="Not Now" aria-label="Not Now" onclick={() => dismissToast(toast.key)}>
          <X size={12} strokeWidth={3} />
        </button>
      </div>
      <div class="body">{toast.body}</div>
      <div class="buttons">
        <button class="btn" onclick={() => ignore(toast)}>Ignore</button>
        <button class="btn default" onclick={() => review(toast)}>Review</button>
      </div>
    </div>
  {/each}
</div>

<style>
  .toasts {
    position: fixed;
    right: 16px;
    bottom: 16px;
    z-index: 90000;
    display: flex;
    flex-direction: column;
    gap: 8px;
    width: 360px;
    pointer-events: none;
  }
  .toast {
    pointer-events: auto;
    background: var(--title-bar);
    border: 1px solid rgba(255, 255, 255, 0.14);
    border-radius: 10px;
    box-shadow: var(--shadow);
    padding: 12px 14px;
  }
  .head {
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .title {
    flex: 1;
    min-width: 0;
    font-size: 13px;
    font-weight: 700;
    color: var(--label);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .close {
    display: flex;
    background: none;
    border: 0;
    padding: 2px;
    color: var(--secondary-label);
    cursor: default;
  }
  .close:hover {
    color: var(--label);
  }
  .body {
    margin-top: 6px;
    font-size: 11px;
    color: var(--label);
    white-space: pre-line;
    overflow-wrap: anywhere;
  }
  .buttons {
    display: flex;
    flex-direction: row-reverse;
    gap: 8px;
    margin-top: 10px;
  }
</style>
