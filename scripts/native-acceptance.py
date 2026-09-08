#!/usr/bin/env python3
"""Opt-in native BEAM Deck cycles and uninterrupted soak. Artifacts stay outside the plugin.

Requires a test-owned target PID and an installed compositor virtual-pointer client.
Does not mutate runtime settings, change configuration, or clean up other processes.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
PLUGIN = "nshkr.beam-deck"
BUDGETS = {"helper": {"rss_growth_mib": 32, "cpu_percent": 10},
           "shell": {"rss_growth_mib": 128, "cpu_percent": 15},
           "target": {"rss_growth_mib": 16, "cpu_percent": 5}}


def command(*args, timeout=8):
    return subprocess.run(args, capture_output=True, text=True, check=True, timeout=timeout).stdout.strip()


def status():
    return json.loads(command("omarchy-shell", PLUGIN, "status"))


def safe_status(value):
    result = {key: value.get(key) for key in ("panel_open", "historical_mode", "session_id", "at_ms",
              "workspace", "investigation_tab", "payload_bytes", "ui_jobs", "watch_count")}
    result["collection"] = {key: value.get("collection", {}).get(key) for key in
                            ("duration_ms", "poll_interval_ms", "deep_interval_ms", "deep", "status")}
    provider = value.get("provider", {})
    result["provider"] = {key: provider.get(key) for key in
                           ("panel_open", "historical_mode", "view_epoch", "active_probes", "pending_probes", "collection_error")}
    result["provider"]["jobs"] = {key: provider.get("jobs", {}).get(key) for key in
                                   ("active", "queued", "max_active", "max_queued", "oldest_queued_ms")}
    result["provider"]["lifecycle"] = [{"reason": row.get("reason"), "at_ms": row.get("at_ms")}
                                          for row in provider.get("lifecycle", [])[:32]]
    result["flight_recorder"] = {key: value.get("flight_recorder", {}).get(key) for key in
                                  ("frame_count", "oldest_frame_id", "newest_frame_id")}
    trial = value.get("budget_trial")
    result["budget_trial"] = {"status": trial.get("status")} if isinstance(trial, dict) else None
    return result


def proc_stat(pid):
    try:
        base = Path(f"/proc/{pid}")
        fields = (base / "stat").read_text().rsplit(")", 1)[1].split()
        children = set()
        for task in (base / "task").iterdir():
            try: children.update((task / "children").read_text().split())
            except OSError: pass
        return {"pid": pid, "ppid": int(fields[1]), "start_ticks": int(fields[19]),
                "cpu_ticks": int(fields[11]) + int(fields[12]), "rss_bytes": int(fields[21]) * os.sysconf("SC_PAGE_SIZE"),
                "fds": len(list((base / "fd").iterdir())), "tasks": len(list((base / "task").iterdir())), "children": len(children)}
    except (OSError, ValueError, IndexError): return None


def identities(target):
    layers = json.loads(command("hyprctl", "layers", "-j"))
    shells = {row["pid"] for monitor in layers.values() for rows in monitor["levels"].values()
              for row in rows if row.get("namespace") == "omarchy-bar"}
    assert len(shells) == 1, "ambiguous_shell_identity"
    shell = shells.pop()
    helpers = []
    for path in Path("/proc").iterdir():
        if not path.name.isdigit(): continue
        try:
            args = (path / "cmdline").read_bytes().split(b"\0")
            if not any(arg.startswith(b"beam_deck_") and arg.split(b"@", 1)[0][10:].isdigit() for arg in args): continue
            info = proc_stat(int(path.name))
            parent = info
            for _ in range(6):
                if not parent: break
                if parent["ppid"] == shell:
                    helpers.append(info); break
                parent = proc_stat(parent["ppid"])
        except OSError: continue
    assert len(helpers) == 1, "persistent_helper_count_changed"
    result = {"helper": helpers[0], "shell": proc_stat(shell), "target": proc_stat(target)}
    assert all(result.values()), "expected_process_missing"
    return result


def failure_context(last):
    evidence = {"at_ms": int(time.time() * 1000), "last_known": last}
    for name in ("helper", "shell", "target"):
        pid = (last.get(name) or {}).get("pid")
        evidence["current_" + name] = proc_stat(pid) if pid else None
    try: evidence["status"] = safe_status(status())
    except (OSError, ValueError, subprocess.SubprocessError): evidence["status"] = {"unavailable": True}
    return evidence


def check_live(value, session, now_ms):
    assert value.get("panel_open") is True, "panel_closed_during_uninterrupted_soak"
    assert value.get("session_id") == session, "helper_epoch_changed_during_soak"
    assert -5000 <= now_ms - value.get("at_ms", 0) <= 10000, "fresh_samples_lost"
    jobs = value.get("provider", {}).get("jobs", {})
    assert 0 <= jobs.get("active", -1) <= 2 and 0 <= jobs.get("queued", -1) <= 16, "job_budget_exceeded"


def source_fingerprint():
    files = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).split(b"\0")
    digest = hashlib.sha256()
    for name in files:
        if name:
            path = ROOT / os.fsdecode(name)
            digest.update(name); digest.update(path.read_bytes())
    return digest.hexdigest()


def assert_surface():
    assert status().get("panel_open") is True, "refusing_keys_without_beam_panel"
    layers = json.loads(command("hyprctl", "layers", "-j"))
    assert any(row.get("w", 0) > 700 and row.get("h", 0) > 400
               for monitor in layers.values() for row in monitor["levels"].get("3", [])), "native_panel_layer_missing"


def keys(*args):
    assert_surface()
    command("wtype", *args)


def wait_panel(opened, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = status()
        if value.get("panel_open") is opened and value.get("provider", {}).get("panel_open") is opened:
            if opened: assert_surface()
            return value
        time.sleep(.15)
    raise AssertionError("panel_transition_not_observed")


def write_private(path, data):
    path.write_text(json.dumps(data, indent=2))
    path.chmod(0o600)


def metrics(samples):
    result = {}
    for name, limits in BUDGETS.items():
        first, last = samples[0][name], samples[-1][name]
        seconds = samples[-1]["mono"] - samples[0]["mono"]
        cpu = (last["cpu_ticks"] - first["cpu_ticks"]) / os.sysconf("SC_CLK_TCK") / max(seconds, .01) * 100
        peak_growth = max(row[name]["rss_bytes"] for row in samples) - first["rss_bytes"]
        result[name] = {"cpu_percent_one_core": cpu, "rss_peak_growth_mib": peak_growth / 1048576,
                        "rss_end_mib": last["rss_bytes"] / 1048576,
                        "fd_growth": max(row[name]["fds"] for row in samples) - first["fds"],
                        "task_growth": max(row[name]["tasks"] for row in samples) - first["tasks"],
                        "child_growth": max(row[name]["children"] for row in samples) - first["children"]}
        assert cpu <= limits["cpu_percent"], name + "_cpu_budget_exceeded"
        assert peak_growth <= limits["rss_growth_mib"] * 1048576, name + "_rss_growth_budget_exceeded"
        assert result[name]["fd_growth"] <= 2, name + "_fd_growth_exceeded"
        assert result[name]["task_growth"] <= 4, name + "_task_growth_exceeded"
        assert result[name]["child_growth"] <= 0, name + "_child_growth_exceeded"
    return result


def run(args):
    os.umask(0o077)
    directory = args.evidence.resolve()
    assert not directory.is_relative_to(ROOT), "artifacts_must_be_outside_watched_tree"
    directory.mkdir(parents=True, exist_ok=False)
    report = {"kind": "acceptance" if args.cycles >= 50 and args.soak >= 600 else "smoke",
              "requested": {"cycles": args.cycles, "soak_seconds": args.soak, "closed_seconds": args.closed, "warmup_seconds": args.warmup},
              "cycles": [], "soak": [], "closed": [], "budgets": BUDGETS,
              "commit": command("git", "-C", str(ROOT), "rev-parse", "HEAD"), "result": "running"}
    last = {}
    try:
        initial = status()
        trial = initial.get("budget_trial") or {}
        assert trial.get("status") not in ("applying", "active", "reverting", "rollback_failed"), "operation_in_progress"
        assert not initial.get("provider", {}).get("active_probes"), "probe_in_progress"
        assert Path(f"/proc/{args.target_pid}/cmdline").read_bytes().find(b"bd_operator_acceptance") >= 0, "target_not_test_owned"
        fingerprint = source_fingerprint()
        original_identity = identities(args.target_pid)
        report["baseline_identity"] = original_identity
        command("omarchy-shell", "shell", "hide", PLUGIN)
        wait_panel(False)
        for i in range(args.cycles):
            route = ("pointer", "ipc", "bar_shortcut")[i % 3]
            if route == "pointer": command(str(args.pointer), "940", "12")
            elif route == "ipc": command("omarchy-shell", "shell", "summon", PLUGIN, "{}")
            else: command("wtype", "-M", "ctrl", "-M", "logo", "-k", "1", "-m", "logo", "-m", "ctrl")
            opened = wait_panel(True)
            # Real context transition each cycle, with focus returned to catcher on open.
            keys("-k", "i"); time.sleep(.1); keys("-k", "f"); time.sleep(.1)
            current = status()
            assert current.get("workspace") == "investigate" and current.get("investigation_tab") == "recorder", "native_navigation_failed"
            close = ("close_control", "escape", "outside", "bar_pointer")[i % 4]
            if close == "close_control": command(str(args.pointer), "1236", "57")
            elif close == "escape": keys("-k", "Escape")
            elif close == "outside": command(str(args.pointer), "650", "28")
            else: command(str(args.pointer), "940", "12")
            closed = wait_panel(False)
            assert closed["provider"]["active_probes"] == 0
            last = identities(args.target_pid)
            for name in original_identity:
                assert (last[name]["pid"], last[name]["start_ticks"]) == (original_identity[name]["pid"], original_identity[name]["start_ticks"]), "process_replaced_during_cycles"
            report["cycles"].append({"index": i+1, "route": route, "close": close, "open": safe_status(opened), "closed": safe_status(closed)})
            if (i+1) % 10 == 0: print(f"cycles: {i+1}/{args.cycles}", flush=True)
        # Warm the exact representative scene before setting growth baselines.
        command("omarchy-shell", "shell", "summon", PLUGIN, "{}")
        value = wait_panel(True)
        keys("-k", "i"); keys("-k", "f")
        warm = time.monotonic()
        while time.monotonic() - warm < args.warmup:
            check_live(status(), value["session_id"], int(time.time()*1000)); time.sleep(2)
        started = time.monotonic()
        session = value["session_id"]
        while True:
            value = status()
            check_live(value, session, int(time.time()*1000))
            last = identities(args.target_pid)
            for name in original_identity:
                assert (last[name]["pid"], last[name]["start_ticks"]) == (original_identity[name]["pid"], original_identity[name]["start_ticks"]), "process_replaced_during_soak"
            report["soak"].append({**last, "mono": time.monotonic(), "status": safe_status(value)})
            elapsed = time.monotonic() - started
            if elapsed >= args.soak: break
            if len(report["soak"]) % 6 == 1: print(f"soak: {elapsed:.0f}/{args.soak}s; payload={value['payload_bytes']}; acquisition={value['collection']['duration_ms']}ms", flush=True)
            # Supported pointer input on inert identity block, never reopen a lost panel.
            assert_surface(); command(str(args.pointer), "250", "56")
            time.sleep(min(5, args.soak-elapsed))
        assert source_fingerprint() == fingerprint, "watched_source_changed_during_run"
        report["soak_metrics"] = metrics(report["soak"])
        assert report["soak"][-1]["status"]["flight_recorder"]["newest_frame_id"] != report["soak"][0]["status"]["flight_recorder"]["newest_frame_id"], "recorder_did_not_progress"
        command("omarchy-shell", "shell", "hide", PLUGIN); wait_panel(False)
        time.sleep(5)
        started = time.monotonic()
        while True:
            last = identities(args.target_pid)
            current = status()
            assert current["panel_open"] is False
            assert current["provider"]["active_probes"] == 0 and current["provider"]["pending_probes"] == 0
            assert current["collection"]["deep"] is False
            report["closed"].append({**last, "mono": time.monotonic(), "status": safe_status(current)})
            if time.monotonic()-started >= args.closed: break
            time.sleep(5)
        report["closed_metrics"] = metrics(report["closed"])
        report["result"] = "passed"
        write_private(directory / "acceptance.json", report)
        print("native " + report["kind"] + ": passed", flush=True)
    except BaseException as error:
        # Preserve evidence before any dismissal/cleanup. Do not reopen and relabel a lost run.
        report["failure"] = {"kind": type(error).__name__, "reason": str(error)[:160] if isinstance(error, AssertionError) else "native_command_or_io_failure"}
        report["failure_context"] = failure_context(last)
        report["result"] = "failed"
        write_private(directory / "acceptance-failed.json", report)
        print("native acceptance: FAILED; evidence retained before cleanup", flush=True)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--pointer", type=Path, required=True)
    parser.add_argument("--target-pid", type=int, required=True)
    parser.add_argument("--cycles", type=int, default=50)
    parser.add_argument("--soak", type=int, default=600)
    parser.add_argument("--closed", type=int, default=60)
    parser.add_argument("--warmup", type=int, default=30)
    run(parser.parse_args())

if __name__ == "__main__": main()
