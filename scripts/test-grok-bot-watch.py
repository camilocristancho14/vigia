#!/usr/bin/env python3
"""Unit tests for scripts/grok-bot-watch: attribution, name reading,
idle/working transitions and dedupe-relevant caching. Pure logic only --
builds a fake /proc root and a fake agents directory, no real process
scanning, no network, no box-specific paths. Safe to run on Linux or macOS
(e.g. from .github/workflows/test.yml).

    python3 scripts/test-grok-bot-watch.py
"""

import importlib.util
import json
import os
import stat
import sys
import tempfile
import time
import unittest
from importlib.machinery import SourceFileLoader

HERE = os.path.dirname(os.path.abspath(__file__))


def _load_watch_module():
    path = os.path.join(HERE, "grok-bot-watch")
    loader = SourceFileLoader("grok_bot_watch", path)
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


watch = _load_watch_module()


def write(path, content=b""):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    mode = "wb" if isinstance(content, bytes) else "w"
    with open(path, mode) as f:
        f.write(content)


def make_profile(agents_dir, agent_id, name):
    write(os.path.join(agents_dir, agent_id, "profile.json"),
          json.dumps({"name": name}))


def make_proc_pid(proc_root, pid, ppid, conv_id=None, extra_env=None):
    """Fakes /proc/<pid>/{stat,environ} well enough for our parsers."""
    write(os.path.join(proc_root, str(pid), "stat"),
          f"{pid} (bash) S {ppid} {pid} {pid} 0 -1 0\n".encode())
    tokens = []
    if extra_env:
        tokens.extend(extra_env)
    if conv_id is not None:
        tokens.append(f"CURSOR_CONVERSATION_ID={conv_id}".encode())
    write(os.path.join(proc_root, str(pid), "environ"), b"\0".join(tokens) + b"\0")


class AgentNamesTests(unittest.TestCase):
    def test_reads_name_and_skips_non_dirs(self):
        with tempfile.TemporaryDirectory() as d:
            make_profile(d, "agent-1", "Dobby")
            make_profile(d, "agent-2", "Alfred")
            write(os.path.join(d, "active-agent.json"), '{"activeAgentId":"agent-1"}')
            write(os.path.join(d, "audit-outbox.json"), "[]")

            names = watch.AgentNames(d)
            names.refresh()
            self.assertEqual(names.name_for("agent-1"), "Dobby")
            self.assertEqual(names.name_for("agent-2"), "Alfred")
            self.assertIsNone(names.name_for("active-agent.json"))
            self.assertEqual(names.ids(), {"agent-1", "agent-2"})

    def test_rereads_on_change_and_drops_removed_agents(self):
        with tempfile.TemporaryDirectory() as d:
            make_profile(d, "agent-1", "Dobby")
            names = watch.AgentNames(d)
            names.refresh()
            self.assertEqual(names.name_for("agent-1"), "Dobby")

            # mtime must visibly change for the re-read to trigger
            time.sleep(0.01)
            make_profile(d, "agent-1", "Dobby Renamed")
            os.utime(os.path.join(d, "agent-1", "profile.json"), None)
            names.refresh()
            self.assertEqual(names.name_for("agent-1"), "Dobby Renamed")

            import shutil
            shutil.rmtree(os.path.join(d, "agent-1"))
            names.refresh()
            self.assertIsNone(names.name_for("agent-1"))


class LiveConversationTests(unittest.TestCase):
    def test_idle_dispatcher_alone_is_not_active(self):
        with tempfile.TemporaryDirectory() as proc:
            make_proc_pid(proc, 100, 1, conv_id="sand-subagent-aaa")
            live = watch.live_active_conversations(proc, exclude_pids=set())
            self.assertEqual(live, set())

    def test_command_running_makes_conversation_active(self):
        with tempfile.TemporaryDirectory() as proc:
            make_proc_pid(proc, 100, 1, conv_id="sand-subagent-aaa")
            make_proc_pid(proc, 101, 100, conv_id="sand-subagent-aaa")
            live = watch.live_active_conversations(proc, exclude_pids=set())
            self.assertEqual(live, {"sand-subagent-aaa"})

    def test_self_process_tree_is_excluded(self):
        with tempfile.TemporaryDirectory() as proc:
            # watcher (200) spawns a curl child (201) that happens to share
            # the watcher's own stale conversation id -- must not count.
            make_proc_pid(proc, 200, 1, conv_id="sand-subagent-self")
            make_proc_pid(proc, 201, 200, conv_id="sand-subagent-self")
            self_tree = watch.own_process_tree(proc, 200)
            self.assertEqual(self_tree, {200, 201})
            live = watch.live_active_conversations(proc, exclude_pids=self_tree)
            self.assertEqual(live, set())

    def test_anchored_match_ignores_embedded_substring_in_other_var(self):
        """Regression test: a sandbox-restore variable can carry a shell
        snippet as its *value* that itself contains the literal substring
        "CURSOR_CONVERSATION_ID=" (observed in the wild, alongside leaked
        secrets). The anchored match must not pick that up as a real
        conversation id for this process."""
        with tempfile.TemporaryDirectory() as proc:
            decoy = (b"__CURSOR_SANDBOX_ENV_RESTORE=builtin export "
                     b"CURSOR_CONVERSATION_ID='not-the-real-one'; "
                     b"builtin export GH_TOKEN='should-never-be-read'")
            make_proc_pid(proc, 300, 1, extra_env=[decoy])
            make_proc_pid(proc, 301, 300, conv_id="real-conv-id")
            mapping = watch.conversation_pids(proc, exclude_pids=set())
            self.assertNotIn("not-the-real-one", mapping)
            self.assertIn("real-conv-id", mapping)
            self.assertEqual(mapping["real-conv-id"], {301})


class RecencyTests(unittest.TestCase):
    def test_recent_window(self):
        with tempfile.TemporaryDirectory() as d:
            agents_dir = os.path.join(d, "agents")
            transcripts_dir = os.path.join(d, "agent-transcripts")
            write(os.path.join(agents_dir, "agent-1", "store.db"), b"x")
            write(os.path.join(agents_dir, "agent-2", "store.db"), b"x")
            now = time.time()
            os.utime(os.path.join(agents_dir, "agent-1", "store.db"), (now, now - 5))
            os.utime(os.path.join(agents_dir, "agent-2", "store.db"), (now, now - 120))

            recent = watch.recent_agent_ids(agents_dir, transcripts_dir,
                                             {"agent-1", "agent-2"}, window=60, now=now)
            self.assertEqual(recent, {"agent-1"})


class AttributorTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.agents_dir = os.path.join(self.tmp.name, "agents")
        self.transcripts_dir = os.path.join(self.tmp.name, "agent-transcripts")
        self.active_agent_file = os.path.join(self.agents_dir, "active-agent.json")
        make_profile(self.agents_dir, "agent-dobby", "Dobby")
        make_profile(self.agents_dir, "agent-alfred", "Alfred")
        self.names = watch.AgentNames(self.agents_dir)
        self.names.refresh()

    def _attributor(self, recheck=60):
        return watch.Attributor(self.names, self.agents_dir, self.transcripts_dir,
                                 self.active_agent_file, transcript_recheck_seconds=recheck)

    def test_direct_agent_id_match(self):
        a = self._attributor()
        self.assertEqual(a.resolve("agent-dobby", recent_ids=set(), now=0), "Dobby")

    def test_transcript_mentions_conversation_id(self):
        write(os.path.join(self.transcripts_dir, "agent-alfred", "agent-alfred.jsonl"),
              '{"role":"user","note":"spawned sand-subagent-xyz for this"}\n')
        a = self._attributor()
        self.assertEqual(a.resolve("sand-subagent-xyz", recent_ids=set(), now=0), "Alfred")

    def test_falls_back_to_most_recently_modified_agent(self):
        now = time.time()
        write(os.path.join(self.agents_dir, "agent-dobby", "store.db"), b"x")
        write(os.path.join(self.agents_dir, "agent-alfred", "store.db"), b"x")
        os.utime(os.path.join(self.agents_dir, "agent-dobby", "store.db"), (now, now))
        os.utime(os.path.join(self.agents_dir, "agent-alfred", "store.db"), (now, now - 30))

        a = self._attributor()
        name = a.resolve("sand-subagent-unknown", recent_ids={"agent-dobby", "agent-alfred"}, now=now)
        self.assertEqual(name, "Dobby")

    def test_falls_back_to_active_agent_file(self):
        write(self.active_agent_file, json.dumps({"activeAgentId": "agent-alfred"}))
        a = self._attributor()
        name = a.resolve("sand-subagent-unknown", recent_ids=set(), now=0)
        self.assertEqual(name, "Alfred")

    def test_falls_back_to_generic_name(self):
        a = self._attributor()
        name = a.resolve("sand-subagent-unknown", recent_ids=set(), now=0)
        self.assertEqual(name, watch.GENERIC_NAME)

    def test_real_resolution_is_cached_even_if_signal_disappears(self):
        write(self.active_agent_file, json.dumps({"activeAgentId": "agent-alfred"}))
        a = self._attributor()
        first = a.resolve("sand-subagent-unknown", recent_ids=set(), now=0)
        self.assertEqual(first, "Alfred")

        write(self.active_agent_file, json.dumps({"activeAgentId": "agent-dobby"}))
        second = a.resolve("sand-subagent-unknown", recent_ids=set(), now=1)
        self.assertEqual(second, "Alfred")

    def test_generic_fallback_is_not_cached(self):
        a = self._attributor()
        first = a.resolve("sand-subagent-unknown", recent_ids=set(), now=0)
        self.assertEqual(first, watch.GENERIC_NAME)

        write(self.active_agent_file, json.dumps({"activeAgentId": "agent-dobby"}))
        second = a.resolve("sand-subagent-unknown", recent_ids=set(), now=100)
        self.assertEqual(second, "Dobby")


class TickTests(unittest.TestCase):
    def test_idle_to_working_fires_once(self):
        states = {}
        calls = []
        hook = lambda event, agent: calls.append((event, agent))

        watch.tick(states, {"Dobby"}, now=0, hook=hook, quiet_seconds=20)
        watch.tick(states, {"Dobby"}, now=1, hook=hook, quiet_seconds=20)
        watch.tick(states, {"Dobby"}, now=2, hook=hook, quiet_seconds=20)

        self.assertEqual(calls, [("UserPromptSubmit", "Dobby")])
        self.assertEqual(states["Dobby"].status, "working")

    def test_working_to_idle_waits_for_quiet_period(self):
        states = {}
        calls = []
        hook = lambda event, agent: calls.append((event, agent))

        watch.tick(states, {"Dobby"}, now=0, hook=hook, quiet_seconds=20)
        watch.tick(states, set(), now=5, hook=hook, quiet_seconds=20)   # too soon
        self.assertEqual(calls, [("UserPromptSubmit", "Dobby")])

        watch.tick(states, set(), now=25, hook=hook, quiet_seconds=20)  # quiet long enough
        self.assertEqual(calls, [("UserPromptSubmit", "Dobby"), ("Stop", "Dobby")])
        self.assertEqual(states["Dobby"].status, "idle")

    def test_multiple_bots_are_independent(self):
        states = {}
        calls = []
        hook = lambda event, agent: calls.append((event, agent))

        watch.tick(states, {"Dobby", "Alfred"}, now=0, hook=hook, quiet_seconds=20)
        self.assertEqual(set(calls), {("UserPromptSubmit", "Dobby"), ("UserPromptSubmit", "Alfred")})

        calls.clear()
        watch.tick(states, {"Alfred"}, now=25, hook=hook, quiet_seconds=20)
        self.assertEqual(calls, [("Stop", "Dobby")])
        self.assertEqual(states["Dobby"].status, "idle")
        self.assertEqual(states["Alfred"].status, "working")

    def test_flicker_within_quiet_period_cancels_stop(self):
        states = {}
        calls = []
        hook = lambda event, agent: calls.append((event, agent))

        watch.tick(states, {"Dobby"}, now=0, hook=hook, quiet_seconds=20)
        watch.tick(states, set(), now=10, hook=hook, quiet_seconds=20)
        watch.tick(states, {"Dobby"}, now=15, hook=hook, quiet_seconds=20)  # back before quiet elapses
        watch.tick(states, set(), now=20, hook=hook, quiet_seconds=20)      # only 5s quiet so far
        self.assertEqual(calls, [("UserPromptSubmit", "Dobby")])
        self.assertEqual(states["Dobby"].status, "working")


if __name__ == "__main__":
    unittest.main()
