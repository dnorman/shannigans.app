"""Exercise the Sutra lifecycle without touching another checkout or registry."""

import hashlib
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import tempfile
import time
import unittest
from urllib.request import urlopen


RUNNER = Path(__file__).resolve().parents[1] / "dev.sh"


class DevRunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="shannigans-dev-test-")
        self.root = (Path(self.temp.name) / "website with spaces").resolve()
        self.root.mkdir()
        shutil.copy2(RUNNER, self.root / "dev.sh")
        (self.root / "dist").mkdir()
        (self.root / "dist/index.html").write_text("<h1>Runner fixture</h1>")
        self.registry = Path(self.temp.name) / "registry"
        self.registry.mkdir()
        self.sentinel = self.registry / "other-project.status"
        self.sentinel.write_text("ready\n")
        key = hashlib.sha256(str(self.root).encode()).hexdigest()[:16]
        self.meta = self.registry / key
        self.status = self.registry / f"{key}.web.status"
        self.env = {**os.environ, "DEV_RUNNER_REGISTRY": str(self.registry)}
        self.env.pop("PORT", None)

    def tearDown(self):
        try:
            self.run_dev("--stop")
            self.assertEqual(self.sentinel.read_text(), "ready\n")
            self.assertEqual(list(self.registry.iterdir()), [self.sentinel])
        finally:
            self.temp.cleanup()

    def run_dev(self, *args, check=True, port=None):
        env = self.env if port is None else {**self.env, "PORT": str(port)}
        result = subprocess.run(
            ["/bin/bash", str(self.root / "dev.sh"), *args],
            cwd=self.root, env=env, text=True, capture_output=True, timeout=25,
        )
        if check:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def metadata(self):
        return dict(line.split("=", 1) for line in self.meta.read_text().splitlines())

    def wait_for(self, condition):
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            if condition():
                return
            time.sleep(0.05)
        self.fail("Timed out waiting for runner state")

    def port_open(self, port):
        with socket.socket() as probe:
            probe.settimeout(0.2)
            return probe.connect_ex(("127.0.0.1", port)) == 0

    def test_start_idempotence_sticky_port_and_stop(self):
        self.run_dev()
        first = self.metadata()
        pid, port = int(first["PID"]), int(first["WEB_PORT"])
        self.assertEqual(first["DIR"], str(self.root))
        self.assertEqual(os.getpgid(pid), pid)
        self.assertGreater(int(first["STARTED"]), 0)
        self.assertEqual(self.status.read_text(), "ready\n")
        with urlopen(f"http://127.0.0.1:{port}/", timeout=3) as response:
            self.assertIn(b"Runner fixture", response.read())
        self.run_dev()
        self.assertEqual(self.metadata(), first)
        self.assertIn(f"http://127.0.0.1:{port}/", self.run_dev("--status").stdout)
        self.run_dev("--stop")
        self.assertFalse(self.meta.exists())
        self.assertFalse(self.status.exists())
        self.assertFalse(self.port_open(port))
        self.run_dev()
        self.assertEqual(int(self.metadata()["WEB_PORT"]), port)
        self.assertNotEqual(int(self.metadata()["PID"]), pid)
        self.run_dev("--restart")
        self.assertEqual(int(self.metadata()["WEB_PORT"]), port)

    def test_sutra_sigterm_reaps_server_and_registry(self):
        self.run_dev()
        data = self.metadata()
        os.kill(int(data["PID"]), signal.SIGTERM)
        self.wait_for(lambda: not self.meta.exists() and not self.status.exists())
        self.wait_for(lambda: not self.port_open(int(data["WEB_PORT"])))
        self.assertNotEqual(self.run_dev("--status", check=False).returncode, 0)

    def test_child_crash_is_reported(self):
        self.run_dev()
        pid = int(self.metadata()["PID"])
        processes = subprocess.check_output(
            ["ps", "-A", "-o", "pid=,ppid=,command="], text=True,
        )
        children = []
        for line in processes.splitlines():
            child, parent, command = line.strip().split(None, 2)
            if int(parent) == pid and " -m http.server " in command and str(self.root) in command:
                children.append(int(child))
        self.assertEqual(len(children), 1)
        os.kill(children[0], signal.SIGTERM)
        self.wait_for(lambda: self.status.read_text().startswith("failed: web exited"))
        self.assertIn("failed:", self.run_dev("--status").stdout)

    def test_stale_supervisor_recovers_owned_group(self):
        self.run_dev()
        first = self.metadata()
        os.kill(int(first["PID"]), signal.SIGKILL)
        self.wait_for(lambda: self.run_dev("--status", check=False).returncode != 0)
        self.run_dev()
        self.assertNotEqual(self.metadata()["PID"], first["PID"])
        self.assertEqual(self.metadata()["WEB_PORT"], first["WEB_PORT"])
        self.assertEqual(self.status.read_text(), "ready\n")

    def test_explicit_occupied_port_is_not_replaced(self):
        with socket.socket() as occupied:
            occupied.bind(("127.0.0.1", 0))
            occupied.listen()
            port = occupied.getsockname()[1]
            result = self.run_dev(port=port, check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("occupied", result.stderr)
            self.assertFalse(self.meta.exists())

    def test_invalid_ports_fail_without_registering(self):
        for port in ["invalid", "0", "80", "65536"]:
            with self.subTest(port=port):
                self.assertNotEqual(self.run_dev(port=port, check=False).returncode, 0)
                self.assertFalse(self.meta.exists())


if __name__ == "__main__":
    unittest.main()
