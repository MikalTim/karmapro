<script lang="ts">
  // The "Export Model" alert, which carries a popup of the trained models as its
  // accessory view (`exportClicked`). It is a sheet over the training window.
  // Export is the default button: Enter chooses it, Escape cancels.
  import PopUp from "../../../lib/ui/PopUp.svelte";
  import Sheet from "../../../lib/ui/Sheet.svelte";
  import { keptChoice } from "./mlModel";

  let {
    windowId,
    names,
    onClose,
  }: { windowId: number; names: string[]; onClose: (name: string | null) => void } = $props();

  let chosen = $state("");
  const selected = $derived(keptChoice(chosen, names));

  function keydown(event: KeyboardEvent) {
    // Preventing the default keeps the window's own Escape handling from closing the window too.
    if (event.key === "Enter") {
      event.preventDefault();
      onClose(selected);
    } else if (event.key === "Escape") {
      event.preventDefault();
      onClose(null);
    }
  }
</script>

<svelte:window onkeydowncapture={keydown} />

<Sheet {windowId} width={420}>
  <div class="message">Export Model</div>
  <div class="informative">Choose a trained model to export:</div>
  <div class="choice">
    <PopUp items={names.map((title) => ({ title }))} value={selected} width={280} onChange={(value) => (chosen = value)} />
  </div>
  <div class="buttons">
    <button class="btn" onclick={() => onClose(null)}>Cancel</button>
    <button class="btn default" onclick={() => onClose(selected)}>Export</button>
  </div>
</Sheet>

<style>
  .message {
    font-size: 13px;
    font-weight: 700;
    margin-bottom: 8px;
  }
  .informative {
    font-size: 11px;
    color: var(--label);
    margin-bottom: 10px;
  }
  .choice {
    margin-bottom: 14px;
  }
  .buttons {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
  }
</style>
