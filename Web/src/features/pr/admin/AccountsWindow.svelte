<script lang="ts">
  // "Pull Request Accounts": the read-only forge credentials that private repositories use. The token is
  // sent once to the server and never shown again; the table only reports whether one is stored.
  import { onMount } from "svelte";
  import { api, withQuery } from "../../../lib/api";
  import { on } from "../../../lib/events";
  import { runJob } from "../../../lib/jobs";
  import PopUp from "../../../lib/ui/PopUp.svelte";
  import Table from "../../../lib/ui/Table.svelte";
  import TextField from "../../../lib/ui/TextField.svelte";
  import { showAlert } from "../../../lib/ui/alert.svelte";
  import {
    accountColumns,
    accountsExplanation,
    afterSave,
    asksForProvider,
    type AccountFormState,
  } from "./accounts";
  import type { AccountDTO, AccountsDTO, ConfirmDTO, StatusDTO } from "./dto";
  import { createLatest } from "./latest";
  import { messageOf, resultLine, statusColour, statusLine, type StatusLine } from "./status";

  // The window host passes `windowId`; this window needs nothing from it.
  let { windowId }: { windowId: number } = $props();

  let data = $state<AccountsDTO | null>(null);
  let platform = $state<string | null>(null);
  let selectedIdentity = $state<string | null>(null);
  let form = $state<AccountFormState>({ providerId: "", host: "", username: "", token: "" });
  let status = $state<StatusLine>(statusLine(""));

  const providers = $derived(data?.providers ?? []);
  const provider = $derived(providers.find((candidate) => candidate.id === form.providerId));
  const providerItems = $derived(providers.map((candidate) => ({ title: candidate.name, value: candidate.id })));
  const explanation = $derived(accountsExplanation(platform));
  const hostLookup = createLatest();

  function selectedAccount(): AccountDTO | undefined {
    return data?.accounts.find((account) => account.identity === selectedIdentity);
  }

  async function refresh() {
    try {
      const next = await api<AccountsDTO>("GET", "/api/pr/accounts");
      data = next;
      if (!next.providers.some((candidate) => candidate.id === form.providerId)) {
        form.providerId = next.providers[0]?.id ?? "";
      }
      if (selectedIdentity && !next.accounts.some((account) => account.identity === selectedIdentity)) {
        selectedIdentity = null;
      }
    } catch (error) {
      status = statusLine(messageOf(error), "error");
    }
  }

  async function loadPlatform() {
    try {
      platform = (await api<{ platform: string }>("GET", "/api/app/info")).platform;
    } catch (error) {
      status = statusLine(messageOf(error), "error");
    }
  }

  // Typing a known host moves the provider list to its forge, as `controlTextDidChange` does. The popup
  // moves only for the newest lookup, and only if neither the host nor the provider changed meanwhile.
  async function hostTyped(host: string) {
    const providerId = form.providerId;
    if (!asksForProvider(provider, host)) return;
    const ticket = hostLookup.next();
    try {
      const reply = await api<{ provider: string }>(
        "GET",
        withQuery("/api/pr/accounts/provider", { provider: providerId, host }),
      );
      if (hostLookup.isLatest(ticket) && form.providerId === providerId && form.host === host) {
        form.providerId = reply.provider;
      }
    } catch {
      // AppKit moves the popup silently and does nothing on failure; the popup stays where it is.
    }
  }

  async function save() {
    try {
      const result = await api<StatusDTO>("POST", "/api/pr/accounts", {
        provider: form.providerId,
        host: form.host,
        username: form.username,
        token: form.token,
      });
      form = afterSave(form);
      status = resultLine(result);
      await refresh();
    } catch (error) {
      status = statusLine(messageOf(error), "error");
    }
  }

  async function testSelected() {
    const account = selectedAccount();
    if (!account) {
      status = statusLine("Select an account to test.", "error");
      return;
    }
    status = statusLine(`Testing ${account.username}…`);
    try {
      const run = runJob<StatusDTO>(
        api<{ jobId: string }>("POST", "/api/pr/accounts/test", { identity: account.identity }),
      );
      const outcome = await run.promise;
      if (outcome.result) status = resultLine(outcome.result);
    } catch (error) {
      status = statusLine(messageOf(error), "error");
    }
  }

  async function removeSelected() {
    const account = selectedAccount();
    if (!account) return;
    try {
      const prompt = await api<ConfirmDTO>(
        "GET",
        withQuery("/api/pr/accounts/remove-prompt", { identity: account.identity }),
      );
      const choice = await showAlert({
        message: prompt.title,
        informative: prompt.message,
        style: "warning",
        buttons: [prompt.confirmTitle, prompt.cancelTitle],
      });
      if (choice !== 0) return;
      const result = await api<StatusDTO>("DELETE", withQuery("/api/pr/accounts", { identity: account.identity }));
      selectedIdentity = null;
      status = resultLine(result);
      await refresh();
    } catch (error) {
      status = statusLine(messageOf(error), "error");
    }
  }

  onMount(() => {
    void refresh();
    void loadPlatform();
    return on("pr.changed", () => void refresh());
  });
</script>

<div class="window-body">
  {#each explanation as paragraph (paragraph)}
    <p class="note">{paragraph}</p>
  {/each}

  <div class="heading">Saved accounts</div>
  <div class="list">
    <Table
      columns={accountColumns}
      rows={data?.accounts ?? []}
      rowKey={(account) => account.identity}
      showHeader={false}
      bind:selectedKey={selectedIdentity}
    />
  </div>
  <div class="row between">
    <button class="btn" onclick={removeSelected}>Remove Selected</button>
    <button class="btn" onclick={testSelected}>Test Connection</button>
  </div>

  <div class="heading">Add an account</div>
  <div class="grid">
    <span>Provider</span>
    <PopUp items={providerItems} bind:value={form.providerId} />
    <span>Host</span>
    <TextField
      bind:value={form.host}
      placeholder={provider?.hostPlaceholder ?? "host"}
      disabled={!provider?.hostEnabled}
      onChange={(value) => void hostTyped(value)}
    />
    <span>Username</span>
    <TextField bind:value={form.username} placeholder="username (a label for you)" />
    <span>Token</span>
    <TextField secure bind:value={form.token} placeholder={provider?.tokenPlaceholder ?? "read-only token"} />
  </div>

  <div class="row between">
    <span class="status" style:color={statusColour(status.tone)}>{status.text}</span>
    <button class="btn save" onclick={save}>Save Token</button>
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
  .note {
    margin: 0;
    font-size: 11px;
    color: var(--secondary-label);
  }
  /* AppKit separates the paragraphs with one blank line of the 11 pt text, about 13 px; the 8 px gap supplies part of it. */
  .note + .note {
    margin-top: 5px;
  }
  .heading {
    font-size: 12px;
    font-weight: 700;
    margin-top: 8px;
  }
  .list {
    flex: none;
    height: 140px;
    display: flex;
    flex-direction: column;
  }
  .row {
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .between {
    justify-content: space-between;
  }
  .grid {
    display: grid;
    grid-template-columns: max-content minmax(0, 1fr);
    gap: 8px 10px;
    align-items: center;
    max-width: 480px;
  }
  .grid > span {
    justify-self: end;
  }
  .grid :global(.field) {
    width: 100%;
  }
  .grid :global(.popup) {
    justify-self: start;
  }
  .status {
    flex: 1;
    min-width: 160px;
    font-size: 11px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .save {
    min-width: 90px;
  }
</style>
