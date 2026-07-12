import Config

# Tests run against a world they fully control: no background seeding,
# reproduction, or evaluation from the EvolutionEngine.
if config_env() == :test do
  config :evolving_minds_core, start_evolution: false, cycle_epochs: false

  # Print only warnings and errors during test
  config :logger, level: :warning
end
