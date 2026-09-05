#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

profile="$($ROOT/bin/beam-deck-profile --schedulers 8 --dirty-cpu 4 --dirty-io 2)"
[[ "$profile" == 'ERL_FLAGS="+S 8:8 +SDcpu 4:4 +SDio 2"' ]]
if "$ROOT/bin/beam-deck-profile" --schedulers 0 >/dev/null 2>&1; then
  echo "beam-deck-profile accepted zero schedulers" >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/config/beam-deck"

cat > "$tmp/bin/iex" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@"
STUB
chmod +x "$tmp/bin/iex"
cat > "$tmp/config/beam-deck/config.json" <<'JSON'
{"nodes":[{"name":"worker@omen","cookie_env":"BEAM_DECK_TEST_COOKIE"}]}
JSON

remsh_out="$(PATH="$tmp/bin:$PATH" XDG_CONFIG_HOME="$tmp/config" BEAM_DECK_TEST_COOKIE='never-write-this-cookie' "$ROOT/bin/beam-deck-remsh" worker@omen)"
printf '%s\n' "$remsh_out" | grep -Fx -- '--hidden' >/dev/null
printf '%s\n' "$remsh_out" | grep -Fx -- '--cookie' >/dev/null
printf '%s\n' "$remsh_out" | grep -Fx -- 'never-write-this-cookie' >/dev/null
printf '%s\n' "$remsh_out" | grep -Fx -- '--remsh' >/dev/null
printf '%s\n' "$remsh_out" | grep -Fx -- 'worker@omen' >/dev/null
! grep -q 'never-write-this-cookie' "$tmp/config/beam-deck/config.json"

# Simulate an Omarchy shell whose PATH has not refreshed after `mise use -g`.
# No erl/elixir/mix binaries exist, but `mise exec` reports a usable selected
# toolchain and receives both Mix invocations.
cat > "$tmp/bin/mise" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${BEAM_DECK_MISE_TEST_LOG:?}"
if [[ "${1:-}" == "exec" && "${2:-}" == "--" && "${3:-}" == "sh" ]]; then
  exit 0
fi
if [[ "${1:-}" == "exec" && "${2:-}" == "--" && "${3:-}" == "mix" ]]; then
  exit 0
fi
exit 1
STUB
chmod +x "$tmp/bin/mise"

mise_log="$tmp/mise.log"
PATH="$tmp/bin:$PATH" HOME="$tmp/home" BEAM_DECK_MISE_TEST_LOG="$mise_log" "$ROOT/bin/beam-deckd" >/dev/null 2>&1 || true
grep -F 'exec -- sh -c command -v erl' "$mise_log" >/dev/null
grep -F 'exec -- mix compile' "$mise_log" >/dev/null
grep -F 'exec -- mix run --no-compile --no-halt' "$mise_log" >/dev/null

echo "script checks: ok"
