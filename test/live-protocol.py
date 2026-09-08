#!/usr/bin/env python3
"""Exercise the actual launcher, JSONL daemon, OTP peer and ZIP writer.

No stubs, target app dependency, external target, or live scheduler mutations.
Uses a private EPMD port, HOME and XDG tree. Requires installed OTP/Elixir/Mix.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import secrets
import selectors
import shutil
import socket
import stat
import subprocess
import tempfile
import time
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def stop(process: subprocess.Popen | None) -> None:
    if process is None or process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)


class Wire:
    def __init__(self, process: subprocess.Popen, secret: str) -> None:
        self.process = process
        self.secret = secret.encode()
        self.buffer = b""
        self.selector = selectors.DefaultSelector()
        self.selector.register(process.stdout, selectors.EVENT_READ)
        self.messages = 0
        self.last_snapshot = None
        self.errors = []

    def send(self, command: dict) -> None:
        self.process.stdin.write(json.dumps(command).encode() + b"\n")
        self.process.stdin.flush()

    def until(self, predicate, timeout: float = 45) -> dict:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            while b"\n" in self.buffer:
                line, self.buffer = self.buffer.split(b"\n", 1)
                assert self.secret not in line, "test cookie leaked onto protocol"
                value = json.loads(line)
                assert isinstance(value, dict) and isinstance(value.get("type"), str)
                self.messages += 1
                if value.get("type") == "snapshot":
                    self.last_snapshot = value
                elif value.get("type") == "error":
                    self.errors.append({
                        "error": value.get("error"),
                        "reason": value.get("reason"),
                    })
                    self.errors = self.errors[-8:]
                if predicate(value):
                    return value
            if self.process.poll() is not None:
                raise AssertionError(f"daemon exited: {self.process.returncode}")
            for key, _ in self.selector.select(min(1, max(0, deadline - time.monotonic()))):
                data = os.read(key.fd, 65536)
                if not data:
                    raise AssertionError("daemon protocol closed unexpectedly")
                self.buffer += data
                assert len(self.buffer) <= 32 * 1024 * 1024, "unbounded protocol line"
        safe = {"messages": self.messages, "errors": self.errors}
        if self.last_snapshot:
            safe["onboarding"] = self.last_snapshot.get("onboarding")
            safe["nodes"] = [
                {
                    "name": n.get("name"),
                    "attached": n.get("attached"),
                    "local": n.get("local"),
                    "error": n.get("error"),
                    "process_scan_error": n.get("process_scan_error"),
                    "hot_processes_count": len(n.get("hot_processes") or []),
                    "hot_processes_at_ms": n.get("hot_processes_at_ms"),
                }
                for n in self.last_snapshot.get("nodes", [])
            ]
        raise AssertionError(
            "timed out awaiting real daemon protocol response; safe_state="
            + json.dumps(safe, sort_keys=True)
        )

    def job(self, command: dict) -> dict:
        self.send(command)
        response = self.until(lambda m: (m.get("type") == "job"
                              and m.get("request_id") == command["request_id"]
                              and m.get("status") in ("complete", "error", "canceled"))
                              or (m.get("type") == "error" and m.get("command") == command["cmd"]))
        assert response.get("status") == "complete", response
        return response["result"]


def main() -> None:
    needed = [name for name in ("erl", "epmd", "elixir", "mix") if not shutil.which(name)]
    if needed:
        raise SystemExit("UNRUN: real protocol validation requires " + ", ".join(needed))
    epmd = peer = daemon = None
    with tempfile.TemporaryDirectory(prefix="beam-deck-protocol-") as temporary:
        home = Path(temporary)
        cookie = "BD_PROTOCOL_TEST_" + secrets.token_hex(16)
        cookie_file = home / ".erlang.cookie"
        cookie_file.write_text(cookie + "\n")
        cookie_file.chmod(0o400)
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", 0))
            port = probe.getsockname()[1]
        # The private EPMD listens only on loopback. Use explicit long names
        # on the same loopback address so Erlang distribution cannot resolve
        # the machine hostname to a non-loopback interface and escape the
        # isolated test topology.
        host = "127.0.0.1"
        node_name = "bd_protocol_" + secrets.token_hex(4)
        target = f"{node_name}@{host}"
        env = {key: val for key, val in os.environ.items()
               if key not in ("ERL_FLAGS", "ERL_AFLAGS", "ERL_ZFLAGS") and not key.startswith("BEAM_DECK_")}
        env.update(HOME=str(home), XDG_CONFIG_HOME=str(home / "config"),
                   XDG_CACHE_HOME=str(home / "cache"), XDG_STATE_HOME=str(home / "state"),
                   ERL_EPMD_PORT=str(port), BEAM_DECK_TEST_COOKIE=cookie,
                   BEAM_DECK_LONGNAMES="1", BEAM_DECK_NODE_HOST=host)
        config_dir = home / "config" / "beam-deck"
        config_dir.mkdir(parents=True)
        (config_dir / "config.json").write_text(json.dumps({
            "poll_interval_ms": 500, "deep_interval_ms": 1000,
            "nodes": [{"name": target, "cookie_env": "BEAM_DECK_TEST_COOKIE"}]}))
        with (home / "runtime.log").open("wb") as log:
            try:
                epmd = subprocess.Popen([shutil.which("epmd"), "-port", str(port), "-address", "127.0.0.1"],
                                        env=env, stdout=log, stderr=log)
                for _ in range(100):
                    try:
                        with socket.create_connection(("127.0.0.1", port), timeout=0.1):
                            break
                    except OSError:
                        time.sleep(0.05)
                else:
                    raise AssertionError("private EPMD did not become ready")
                expression = ("P=spawn(fun F()->receive _ -> F() end end),"
                              "register(bd_protocol_worker,P),"
                              "ets:new(bd_protocol_table,[named_table,public]),"
                              'ets:insert(bd_protocol_table,{private_data,"DO_NOT_EXPORT_ETS_CONTENT"}),'
                              "receive stop -> ok end.")
                peer = subprocess.Popen([shutil.which("erl"), "+S", "3:3", "+SDcpu", "1:1", "+SDio", "1",
                                         "-name", target, "-setcookie", cookie, "-noshell", "-eval", expression],
                                        cwd=home, env=env, stdout=log, stderr=log)
                daemon = subprocess.Popen([str(ROOT / "bin" / "beam-deckd")], cwd=ROOT, env=env,
                                          stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log)
                wire = Wire(daemon, cookie)
                snapshot = wire.until(lambda m: m.get("type") == "snapshot" and any(
                    n.get("name") == target and n.get("attached") for n in m.get("nodes", [])), 120)
                for key in ("forecasts", "incidents", "flight_recorder", "watchlist", "budget_trial", "crash_triage"):
                    assert key in snapshot, key
                assert snapshot["protocol"] == 1
                assert snapshot["provider"]["panel_open"] is False
                assert snapshot["provider"]["jobs"]["active"] <= 2
                assert snapshot["provider"]["jobs"]["queued"] <= 16
                assert snapshot["collection"]["duration_ms"] >= 0
                assert snapshot["collection"]["poll_interval_ms"] == 500
                assert isinstance(snapshot["sample_mono_ms"], int)
                wire.send({"cmd": "panel", "open": True})
                snapshot = wire.until(lambda m: m.get("type") == "snapshot" and any(
                    n.get("name") == target and n.get("hot_processes") for n in m.get("nodes", [])))
                node = next(n for n in snapshot["nodes"] if n["name"] == target)
                assert node["process_scan"]["scanned"] >= len(node["hot_processes"])
                assert node["process_scan"]["limit"] <= 100000
                assert node["local"], "isolated local target was misclassified"
                process = wire.job({"cmd": "inspect_process", "request_id": "protocol-process", "node": target,
                                    "pid": node["hot_processes"][0]["pid"]})
                assert process["creation"] == node["creation"]
                tables = wire.job({"cmd": "inspect_ets", "request_id": "protocol-ets", "node": target, "sort": "memory"})
                assert tables["scanned_tables"] > 0
                assert "DO_NOT_EXPORT_ETS_CONTENT" not in json.dumps(tables)
                for kind in ("process_window", "ets_window", "sample_process"):
                    survey = wire.job({"cmd": kind, "request_id": "protocol-"+kind, "node": target,
                                       "pid": process["pid"], "expected_creation": node["creation"], "duration_ms": 1000})
                    assert survey["creation"] == node["creation"]
                    assert survey["span_ms"] >= (750 if kind == "sample_process" else 1000)
                    assert "DO_NOT_EXPORT_ETS_CONTENT" not in json.dumps(survey)
                for mode in ("cancel", "historical", "close"):
                    request = "stop-survey-"+mode
                    wire.send({"cmd": "process_window", "request_id": request, "node": target,
                               "expected_creation": node["creation"], "duration_ms": 5000})
                    wire.until(lambda m: m.get("request_id") == request and m.get("status") == "started")
                    wire.send({"cmd": "cancel_job", "request_id": request} if mode == "cancel" else
                              {"cmd": "view", "historical": True} if mode == "historical" else {"cmd": "panel", "open": False})
                    canceled = wire.until(lambda m: m.get("request_id") == request and m.get("status") in ("canceled", "error", "complete"))
                    assert canceled["status"] == "canceled", canceled
                    wire.send({"cmd": "view", "historical": False})
                    wire.send({"cmd": "panel", "open": True})
                    wire.until(lambda m: m.get("type") == "snapshot" and m.get("provider", {}).get("panel_open") and not m["provider"].get("historical_mode"))
                wire.send({"cmd":"process_window","request_id":"survey-wrong-creation","node":target,
                           "expected_creation":node["creation"]+1,"duration_ms":1000})
                wrong_survey = wire.until(lambda m: m.get("request_id")=="survey-wrong-creation" and m.get("status")=="error")
                assert wrong_survey["error"] == "target_restarted_or_unavailable"
                frame_id = snapshot["flight_recorder"]["newest_frame_id"]
                frame = wire.job({"cmd": "recorder_frame", "request_id": "protocol-frame", "frame_id": frame_id})
                assert frame["frame_id"] == frame_id and "history" not in frame
                delta = wire.job({"cmd": "compare_frames", "request_id": "protocol-diff",
                                  "from_frame_id": frame_id, "to_frame_id": frame_id})
                assert delta["summary_delta"]["beam_rss_bytes"] == 0
                # UI read-only state is enforced at the actual daemon boundary too.
                wire.send({"cmd": "view", "historical": True})
                wire.until(lambda m: m.get("type") == "snapshot" and m.get("provider", {}).get("historical_mode") is True)
                wire.send({"cmd": "set_schedulers", "node": target, "value": 1})
                denied = wire.until(lambda m: m.get("type") == "action" and m.get("action") == "set_schedulers")
                assert denied["result"].get("error")
                wire.send({"cmd": "view", "historical": False})
                current = wire.until(lambda m: m.get("type") == "snapshot" and m.get("provider", {}).get("historical_mode") is False)
                assert next(n for n in current["nodes"] if n["name"] == target)["schedulers_online"] == 3
                wire.send({"cmd": "inspect_process", "request_id": "wrong-incarnation", "node": target,
                           "pid": process["pid"], "expected_creation": node["creation"] + 1})
                wrong = wire.until(lambda m: m.get("request_id") == "wrong-incarnation" and m.get("status") == "error")
                assert wrong["error"] == "target_restarted_or_unavailable"
                if int(node["otp"]) >= 28:
                    wire.send({"cmd": "deep_events", "node": target, "enabled": True, "expected_creation": node["creation"] + 1})
                    refused_probe = wire.until(lambda m: m.get("type") == "action" and m.get("action") == "deep_events")
                    assert refused_probe["result"].get("error"), "wrong-incarnation probe was started"
                    for _ in range(5):
                        wire.send({"cmd": "deep_events", "node": target, "enabled": True})
                    probe_state = wire.until(lambda m: m.get("type") == "snapshot" and m.get("provider", {}).get("active_probes") == 1)
                    assert probe_state["provider"]["pending_probes"] <= 1
                    wire.send({"cmd": "view", "historical": True})
                    wire.until(lambda m: m.get("type") == "snapshot" and m.get("provider", {}).get("active_probes") == 0 and m["provider"]["historical_mode"])
                    wire.send({"cmd": "view", "historical": False})
                wire.send({"cmd": "watchlist_add", "entry": {"kind": "registered_process", "node": target, "name": "bd_protocol_worker"}})
                wire.until(lambda m: m.get("type") == "snapshot" and any(
                    p.get("name") == "bd_protocol_worker" and p.get("status") == "present"
                    for p in m.get("watchlist", {}).get("entries", [])))
                bundle = wire.job({"cmd": "export_bundle", "request_id": "protocol-export"})
                path = Path(bundle["path"])
                assert home in path.parents and stat.S_IMODE(path.stat().st_mode) == 0o600
                expected = {"BEAM-DECK-DIAGNOSTICS.txt", "metadata.json", "current-snapshot.json",
                            "flight-recorder.json", "incidents.json", "recent-events.json", "crash-triage.json"}
                with zipfile.ZipFile(path) as archive:
                    assert set(archive.namelist()) == expected
                    for entry in archive.namelist():
                        content = archive.read(entry)
                        assert cookie.encode() not in content
                        assert b"DO_NOT_EXPORT_ETS_CONTENT" not in content
                        if entry.endswith(".json"):
                            json.loads(content)
                wire.send({"cmd": "inspect_process", "request_id": "invalid", "node": target, "pid": "not-a-pid"})
                wire.until(lambda m: m.get("type") == "error" and m.get("error") == "invalid_command")
                wire.send({"cmd": "panel", "open": False})
                wire.send({"cmd": "refresh"})
                wire.until(lambda m: m.get("type") == "snapshot")
                daemon.stdin.close()
                assert daemon.wait(timeout=20) == 0, "normal EOF did not stop daemon cleanly"
                print(f"real protocol: passed; {wire.messages} JSONL messages; actual OTP peer, process/ETS jobs, pins, frames/diff, private ZIP and EOF")
            except BaseException:
                log.flush()
                # Do not print raw logs: test cookie may appear in OTP diagnostics.
                print("Real protocol validation failed. Runtime logs are intentionally not printed (credential safety).")
                raise
            finally:
                stop(daemon)
                stop(peer)
                stop(epmd)


if __name__ == "__main__":
    main()
