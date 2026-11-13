<script lang="ts">
  let version = $state("…");
  fetch("/api/app/info", { headers: { "X-Karma-Client": "web" } })
    .then((r) => r.json())
    .then((info) => (version = info.version));
</script>

<main>Karma Pro {version}</main>
