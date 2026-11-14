<script lang="ts">
  import { CircleAlert } from "@lucide/svelte";
  import { tick } from "svelte";
  import { alertQueue, resolveAlert, type PendingAlert } from "./alert.svelte";
  import { windowStore } from "./windows.svelte";

  const current = $derived(alertQueue.list[0] as PendingAlert | undefined);
  let values = $state<string[]>([]);
  let shownId = 0;
  let dialog: HTMLDivElement | undefined = $state();

  $effect(() => {
    const alert = current;
    if (!alert || alert.id === shownId) return;
    shownId = alert.id;
    values = (alert.options.fields ?? []).map((f) => f.value ?? "");
    void tick().then(() => {
      const first = dialog?.querySelector<HTMLInputElement>("input");
      if (first) first.focus();
      else dialog?.focus();
    });
  });

  const area = $derived.by(() => {
    const sheet = current?.options.sheetOf;
    const win = sheet === undefined ? undefined : windowStore.list.find((w) => w.id === sheet);
    return win ? `left:${win.x}px;top:${win.y}px;width:${win.width}px;height:${win.height}px;z-index:${100 + win.z + 5000};` : "inset:0;";
  });

  function press(index: number) {
    if (current) resolveAlert(current.id, { button: index, values: [...values] });
  }

  function keydown(event: KeyboardEvent) {
    if (!current) return;
    const buttons = current.options.buttons ?? ["OK"];
    if (event.key === "Enter" && !(event.target instanceof HTMLButtonElement)) {
      event.preventDefault();
      press(0);
    } else if (event.key === "Escape") {
      const cancel = buttons.findIndex((title) => title === "Cancel");
      event.preventDefault();
      event.stopPropagation();
      if (cancel >= 0) press(cancel);
    }
  }
</script>

<svelte:window onkeydowncapture={keydown} />

{#if current}
  {@const options = current.options}
  <div class="scrim" style={area}>
    <div class="alert" role="alertdialog" aria-modal="true" aria-label={options.message} tabindex="-1" bind:this={dialog}>
      <div class="body">
        {#if options.style && options.style !== "informational"}
          <div class="icon"><CircleAlert size={44} color={options.style === "critical" ? "var(--system-red)" : "var(--system-yellow)"} /></div>
        {/if}
        <div class="text">
          <div class="message selectable">{options.message}</div>
          {#if options.informative}
            <div class="informative selectable">{options.informative}</div>
          {/if}
          {#if options.fields && options.fields.length > 0}
            <div class="fields">
              {#each options.fields as field, i (i)}
                <label>
                  {#if field.label}<span>{field.label}</span>{/if}
                  <input
                    class="field"
                    type={field.secure ? "password" : "text"}
                    placeholder={field.placeholder ?? ""}
                    style="width:{field.width ?? 280}px"
                    bind:value={values[i]}
                  />
                </label>
              {/each}
            </div>
          {/if}
        </div>
      </div>
      <div class="buttons">
        {#each options.buttons ?? ["OK"] as title, i (i)}
          <button class="btn" class:default={i === 0} onclick={() => press(i)}>{title}</button>
        {/each}
      </div>
    </div>
  </div>
{/if}

<style>
  .scrim {
    position: fixed;
    background: rgba(0, 0, 0, 0.35);
    display: flex;
    align-items: flex-start;
    justify-content: center;
    /* Above the folder picker (100500): an alert that arrives while the picker is open must stay reachable. */
    z-index: 101000;
  }
  .alert {
    margin-top: 12vh;
    min-width: 420px;
    max-width: 560px;
    background: #323234;
    border-radius: 10px;
    box-shadow: var(--shadow);
    padding: 20px 20px 16px;
    outline: none;
  }
  .body {
    display: flex;
    gap: 16px;
  }
  .icon {
    flex: none;
  }
  .text {
    flex: 1;
    min-width: 0;
  }
  .message {
    font-size: 13px;
    font-weight: 700;
    margin-bottom: 8px;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }
  .informative {
    font-size: 11px;
    color: var(--label);
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }
  .fields {
    margin-top: 12px;
    display: grid;
    gap: 8px;
  }
  .fields label {
    display: flex;
    align-items: center;
    gap: 10px;
  }
  .buttons {
    display: flex;
    flex-direction: row-reverse;
    gap: 10px;
    margin-top: 18px;
  }
  .buttons .btn {
    min-width: 72px;
  }
</style>
