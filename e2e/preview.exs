unless Mix.env() == :test, do: raise("Browser fixtures must run with MIX_ENV=test")
Application.put_env(:evolving_minds_core, :persistence, false)
Application.put_env(:evolving_minds_core, :start_evolution, false)
Application.put_env(:evolving_minds_core, :cycle_epochs, false)

config = Application.fetch_env!(:evolving_minds, EvolvingMindsWeb.Endpoint)
Application.put_env(:evolving_minds, EvolvingMindsWeb.Endpoint, Keyword.merge(config,
  server: true, http: [ip: {127, 0, 0, 1}, port: 4003],
  url: [host: "127.0.0.1", port: 4003], check_origin: ["http://127.0.0.1:4003"]))
{:ok, _} = Application.ensure_all_started(:evolving_minds)
EvolvingMinds.World.pause()
for {name, i} <- Enum.with_index(~w(Aurelian Nyx Solenne Vesper Orion Lyra Caelum Nova)) do
  {:ok, _} = EvolvingMinds.World.spawn_entity(name: name, energy: 95 - i * 11,
    traits: %{aggression: 0.1 + i * 0.1, curiosity: 0.85 - i * 0.1},
    tribe: if(rem(i, 2) == 0, do: :solari, else: :umbra), generation: i + 1)
end
ids = EvolvingMinds.World.get_all_entities()
for [a, b] <- Enum.chunk_every(ids, 2), do: EvolvingMinds.Memory.remember(a, {:greet, b})
send(EvolvingMinds.Stats, :collect)
EvolvingMinds.Stats.get_history()
IO.puts("Preview ready on loopback port 4003; persistence disabled")
Process.sleep(:infinity)
