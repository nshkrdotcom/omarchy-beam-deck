exclude = if System.get_env("BEAM_DECK_INTEGRATION") == "1", do: [], else: [:integration]
ExUnit.start(exclude: exclude)
