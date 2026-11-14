<script lang="ts">
  // "Watched Repositories": the repositories polled for new pull requests, the review checkouts kept on disk,
  // and the form that adds a repository. A new repository starts public with no credentials; only ticking
  // "Private repository" makes the server look for an account.
  import { onMount } from "svelte";
  import { api, withQuery } from "../../../lib/api";
  import { on } from "../../../lib/events";
  import { runJob } from "../../../lib/jobs";
  import PopUp from "../../../lib/ui/PopUp.svelte";
  import Table from "../../../lib/ui/Table.svelte";
  import type { Column } from "../../../lib/ui/Table.svelte";
  import TextField from "../../../lib/ui/TextField.svelte";
  import { showAlert } from "../../../lib/ui/alert.svelte";
  import { pickPath } from "../../../lib/ui/directoryPicker.svelte";
  import type {
    AccountChoiceDTO,
    CachePromptDTO,
    ConfirmDTO,
    DetectionDTO,
    RepoDTO,
    RepositoriesDTO,
    StatusDTO,
  } from "./dto";
  import { createLatest } from "./latest";
  import {
    afterRepoAdded,
    defaultDepth,
    depthExplanation,
    detectionLine,
    notificationNotice,
    repoColumns,
    showsAccountPicker,
    type RepoFormState,
  } from "./repos";
  import { classifyFailure, messageOf, resultLine, statusColour, statusLine, type StatusLine } from "./status";

  /** How long the URL must stay unchanged before it is read; keeps a fast typist from one request per key. */
  const DETECT_DELAY_MS = 250;

  // The window host passes `windowId`; this window needs nothing from it.
  let { windowId }: { windowId: number } = $props();

  let data = $state<RepositoriesDTO | null>(null);
  let selectedId = $state<string | null>(null);
  let form = $state<RepoFormState>({
    url: "",
    localPath: "",
    depth: "",
    baseBranches: "",
    isPrivate: false,
    accountIdentity: null,
  });
  let accountChoices = $state<AccountChoiceDTO[]>([]);
  let status = $state<StatusLine>(statusLine(""));
  let testing = $state(false);
  let permission = $state<string | null>(null);

  const depthItems = $derived((data?.depthChoices ?? []).map((choice) => ({ title: choice.title, value: choice.value })));
  const accountItems = $derived(accountChoices.map((choice) => ({ title: choice.title, value: choice.identity })));
  const depthHint = $derived(depthExplanation(data?.depthChoices ?? [], form.depth));
  const notice = $derived(notificationNotice(permission));
  const detector = createLatest();
  let detectTimer: ReturnType<typeof setTimeout> | undefined;

  function selectedRepo(): RepoDTO | undefined {
    return data?.repos.find((repo) => repo.id === selectedId);
  }

  function notificationPermission(): string | null {
    return typeof Notification === "undefined" ? null : Notification.permission;
  }

  async function refresh() {
    try {
      const next = await api<RepositoriesDTO>("GET", "/api/pr/repos");
      data = next;
      if (form.depth === "") form.depth = defaultDepth(next.depthChoices);
      if (selectedId && !next.repos.some((repo) => repo.id === selectedId)) selectedId = null;
      permission = notificationPermission();
    } catch (error) {
      status = statusLine(messageOf(error), "error");
    }
  }

  /**
   * A failure whose text has a title and detail is an alert, as the dialog presents it; any other failure
   * goes to the status line in red.
   */
  async function reportFailure(error: unknown) {
    const failure = classifyFailure(messageOf(error));
    if (failure.kind === "alert") {
      await showAlert({ message: failure.title, informative: failure.detail, buttons: ["OK"] });
    } else {
      status = statusLine(failure.text, "error");
    }
  }

  function typedURL() {
    clearTimeout(detectTimer);
    detectTimer = setTimeout(() => void detect(true), DETECT_DELAY_MS);
  }

  /**
   * Reads the URL and the private/account choices as the add form does while it is typed. `fromURL` lets the
   * server tick the private box for a self-hosted forge, as AppKit does on a typed URL. Toggling the box or the
   * account never unticks it.
   */
  async function detect(fromURL: boolean) {
    const ticket = detector.next();
    try {
      const reply = await api<DetectionDTO>("POST", "/api/pr/repos/detect", {
        url: form.url,
        isPrivate: form.isPrivate,
        accountIdentity: form.accountIdentity,
      });
      if (!detector.isLatest(ticket)) return;
      if (fromURL && reply.isPrivate) form.isPrivate = true;
      accountChoices = reply.accounts;
      form.accountIdentity = reply.selectedAccountIdentity ?? null;
      status = detectionLine(reply);
    } catch (error) {
      if (detector.isLatest(ticket)) status = statusLine(messageOf(error), "error");
    }
  }

  function chooseAccount(identity: string) {
    form.accountIdentity = identity;
    void detect(false);
  }

  async function chooseLocalClone() {
    const path = await pickPath({ message: "Choose an existing local clone of the repository.", prompt: "Choose" });
    if (path) form.localPath = path;
  }

  /** Pauses or resumes one repository without removing it (the Watching checkbox). */
  async function setWatching(repo: RepoDTO, input: HTMLInputElement) {
    try {
      await api<RepoDTO>("PUT", `/api/pr/repos/${encodeURIComponent(repo.id)}`, { enabled: input.checked });
      await refresh();
    } catch (error) {
      input.checked = repo.enabled;
      status = statusLine(messageOf(error), "error");
    }
  }

  async function addRepository() {
    clearTimeout(detectTimer);
    // Answers to a detection still in flight would put back the URL that was just cleared.
    detector.next();
    try {
      await api<RepoDTO>("POST", "/api/pr/repos", {
        url: form.url,
        isPrivate: form.isPrivate,
        localPath: form.localPath,
        depth: form.depth,
        baseBranches: form.baseBranches,
        accountIdentity: form.accountIdentity,
      });
      form = afterRepoAdded(form);
      accountChoices = [];
      status = statusLine("");
      await refresh();
    } catch (error) {
      await reportFailure(error);
    }
  }

  async function testConnection() {
    testing = true;
    try {
      const run = runJob<StatusDTO>(
        api<{ jobId: string }>("POST", "/api/pr/repos/test", {
          url: form.url,
          isPrivate: form.isPrivate,
          accountIdentity: form.accountIdentity,
        }),
        (progress) => {
          status = statusLine(progress.stage);
        },
      );
      const outcome = await run.promise;
      if (outcome.result) status = resultLine(outcome.result);
    } catch (error) {
      status = statusLine(messageOf(error), "error");
    } finally {
      testing = false;
    }
  }

  async function removeSelected() {
    const repo = selectedRepo();
    if (!repo) return;
    try {
      const prompt = await api<ConfirmDTO>("GET", withQuery("/api/pr/repos/remove-prompt", { id: repo.id }));
      const choice = await showAlert({
        message: prompt.title,
        informative: prompt.message,
        buttons: [prompt.confirmTitle, prompt.cancelTitle],
      });
      if (choice !== 0) return;
      await api<{ ok: boolean }>("DELETE", withQuery("/api/pr/repos", { id: repo.id }));
      selectedId = null;
      await refresh();
    } catch (error) {
      status = statusLine(messageOf(error), "error");
    }
  }

  /**
   * Removes every review checkout after confirming. The server refuses while a review is open, because that
   * review reads its files from the cache. With nothing on disk the server answers "already empty".
   */
  async function clearCache() {
    try {
      const { prompt } = await api<CachePromptDTO>("GET", "/api/pr/cache/prompt");
      if (prompt) {
        const choice = await showAlert({
          message: prompt.title,
          informative: prompt.message,
          buttons: [prompt.confirmTitle, prompt.cancelTitle],
        });
        if (choice !== 0) return;
      }
      status = resultLine(await api<StatusDTO>("DELETE", "/api/pr/cache"));
    } catch (error) {
      await reportFailure(error);
    } finally {
      await refresh();
    }
  }

  function openRepo(repo: RepoDTO) {
    window.open(repo.webURL, "_blank", "noopener");
  }

  onMount(() => {
    void refresh();
    return on("pr.changed", () => void refresh());
  });
</script>

<div class="window-body">
  <div class="heading">Watched repositories</div>
  <div class="list">
    <Table
      columns={repoColumns}
      rows={data?.repos ?? []}
      rowKey={(repo) => repo.id}
      bind:selectedKey={selectedId}
      onDoubleClick={openRepo}
    >
      {#snippet cell(repo: RepoDTO, column: Column<RepoDTO>)}
        {#if column.id === "Watching"}
          <input
            type="checkbox"
            aria-label="Watching"
            title={repo.watchingTooltip}
            checked={repo.enabled}
            onclick={(event) => event.stopPropagation()}
            ondblclick={(event) => event.stopPropagation()}
            onchange={(event) => void setWatching(repo, event.currentTarget)}
          />
        {:else}
          <span class="cell-text" title={repo.webURL}>{column.value?.(repo) ?? ""}</span>
        {/if}
      {/snippet}
    </Table>
  </div>

  {#if data?.pollErrorDetail}
    <p class="poll-error">{data.pollErrorDetail}</p>
  {/if}
  {#if notice}
    <p class="notice" style:color={statusColour(notice.tone)}>{notice.text}</p>
  {/if}

  <div class="row">
    <button class="btn" onclick={removeSelected}>Remove</button>
  </div>
  <div class="row between">
    <span class="cache" title={data?.cache.path ?? ""}>{data?.cache.label ?? ""}</span>
    <button class="btn" onclick={clearCache}>Clear Cache</button>
  </div>

  <div class="heading">Add a repository</div>
  <div class="grid">
    <span>Repository</span>
    <TextField
      bind:value={form.url}
      placeholder="https://github.com/owner/name (or a git remote URL)"
      onChange={typedURL}
      onEnter={addRepository}
    />
    {#if showsAccountPicker(accountChoices)}
      <span>Account</span>
      <PopUp items={accountItems} value={form.accountIdentity ?? ""} onChange={chooseAccount} />
    {/if}
    <span>Local clone</span>
    <div class="inline">
      <TextField
        bind:value={form.localPath}
        placeholder="optional: use an existing local clone instead of downloading"
        onEnter={addRepository}
      />
      <button class="btn" onclick={chooseLocalClone}>Choose…</button>
    </div>
    <span>Scan depth</span>
    <PopUp items={depthItems} bind:value={form.depth} />
    <span></span>
    <p class="hint">{depthHint}</p>
    <span>Base branches</span>
    <TextField
      bind:value={form.baseBranches}
      placeholder="optional: base branches to watch, e.g. main, release"
      onEnter={addRepository}
    />
  </div>

  <label class="check">
    <input
      type="checkbox"
      checked={form.isPrivate}
      onchange={(event) => {
        form.isPrivate = event.currentTarget.checked;
        void detect(false);
      }}
    />
    <span>Private repository (requires a read-only token)</span>
  </label>

  <div class="row">
    <span class="status" style:color={statusColour(status.tone)}>{status.text}</span>
    <button class="btn wide" disabled={testing} onclick={testConnection}>Test Connection</button>
    <button class="btn default wide" onclick={addRepository}>Add Repository</button>
  </div>
</div>

<style>
  .window-body {
    flex: 1;
    min-height: 0;
    overflow: auto;
    padding: 16px;
    display: flex;
    flex-direction: column;
    gap: 8px;
    color: var(--label);
    background: var(--window-bg);
  }
  .check {
    display: inline-flex;
    align-items: center;
    gap: 6px;
  }
  .check input {
    accent-color: var(--accent);
    margin: 0;
  }
  .heading {
    font-size: 12px;
    font-weight: 700;
    margin-top: 8px;
  }
  .list {
    height: 160px;
    display: flex;
    flex-direction: column;
  }
  /* AppKit hides the column headers of both tables, so the rows show the columns alone. */
  .list :global(.header) {
    display: none;
  }
  .cell-text {
    display: block;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .row {
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .between {
    justify-content: space-between;
  }
  .cache {
    min-width: 0;
    font-size: 11px;
    color: var(--secondary-label);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .poll-error {
    margin: 0;
    font-size: 10px;
    color: var(--system-red);
  }
  .notice {
    margin: 0;
    font-size: 10px;
  }
  .grid {
    display: grid;
    grid-template-columns: max-content minmax(0, 1fr);
    gap: 8px 10px;
    align-items: center;
  }
  .grid > span {
    justify-self: end;
  }
  .grid > :global(.field) {
    width: 100%;
  }
  .grid > :global(.popup) {
    justify-self: start;
  }
  .inline {
    display: flex;
    align-items: center;
    gap: 8px;
    min-width: 0;
  }
  .inline :global(.field) {
    flex: 1;
    min-width: 0;
  }
  .hint {
    margin: 0;
    max-width: 420px;
    font-size: 10px;
    color: var(--secondary-label);
  }
  .status {
    flex: 1;
    min-width: 140px;
    font-size: 11px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .wide {
    min-width: 110px;
  }
</style>
