"""End-to-end helper protocol checks against a fake MTP device, without USB writes."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class HelperProtocolTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.directory = Path(cls.temp.name)
        cls.helper = cls.directory / "helper"
        prefixes = list((Path.home() / 'Library/Caches/mac-switch-mtp').glob('deps-*/include/libmtp.h'))
        prefix = os.environ.get('SWITCH_MTP_DEPS_PREFIX')
        if not prefix:
            prefix = str(prefixes[0].parents[1]) if prefixes else subprocess.check_output(["brew", "--prefix"], text=True).strip()
        subprocess.run(["clang", "-Wall", "-Wextra", "-Werror", "-I" + prefix + "/include",
                        str(ROOT / "Sources/mtp_helper.c"), str(ROOT / "tests/fake_mtp.c"),
                        "-o", str(cls.helper)], check=True)
        cls.file = cls.directory / '中文 空格 [试用] "引号".NSP'
        cls.file.write_bytes(b"fixture data")
        cls.big = cls.directory / "large.xci"
        with cls.big.open("wb") as file:
            file.truncate(5 * 1024**3 + 123)
        cls.empty = cls.directory / "empty.nsp"
        cls.empty.touch()

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def run_helper(self, commands, mode="ok"):
        run = subprocess.run([str(self.helper)], input="\n".join(commands + ["quit"]) + "\n",
                             capture_output=True, text=True, timeout=5,
                             env={**os.environ, "FAKE_MTP": mode})
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn("unsolicited library stdout", run.stderr)
        return [json.loads(line) for line in run.stdout.splitlines()]

    def test_only_sd_install_is_exposed(self):
        events = self.run_helper(["connect"])
        self.assertEqual(events[1]["storages"], [{"id": 327681, "name": "5: SD Card install", "free": 100000000000}])

    def test_unicode_path_and_json_escaping(self):
        events = self.run_helper(["connect", f"send\t327681\t{self.file}"])
        self.assertEqual(events[-1]["event"], "sent")
        self.assertEqual(next(e["message"] for e in events if e["event"] == "sending"), self.file.name)

    def test_greater_than_4gb_metadata_and_progress(self):
        events = self.run_helper(["connect", f"send\t327681\t{self.big}"])
        self.assertEqual(events[-1]["event"], "sent")
        self.assertEqual([e for e in events if e["event"] == "progress"][-1]["sent"], self.big.stat().st_size)

    def test_rejects_sd_filesystem_nand_and_unknown_storage(self):
        for target in [65537, 393217, 99, "-1", "327681bad", "4294967296"]:
            with self.subTest(target=target):
                events = self.run_helper(["connect", f"send\t{target}\t{self.file}"])
                self.assertEqual(events[-1]["event"], "error")
                self.assertFalse(any(e["event"] == "sending" for e in events))

    def test_rejects_missing_empty_directory_and_unsupported_files(self):
        for file in [self.empty, self.directory / "absent.nsp", self.directory, self.directory / "bad.txt"]:
            with self.subTest(file=file):
                events = self.run_helper(["connect", f"send\t327681\t{file}"])
                self.assertEqual(events[-1]["event"], "error")

    def test_detection_and_open_errors(self):
        for mode in ["none", "foreign", "multiple", "openfail", "nostorage", "storagefail"]:
            with self.subTest(mode=mode):
                events = self.run_helper(["connect"], mode)
                self.assertEqual(events[-1]["event"], "error")

    def test_transfer_failure_closes_session(self):
        events = self.run_helper(["connect", f"send\t327681\t{self.file}", f"send\t327681\t{self.file}"], "sendfail")
        self.assertEqual(events[-1]["event"], "error")
        self.assertEqual(sum(e["event"] == "sending" for e in events), 1)
        self.assertTrue(any(e["event"] == "log" and '"错误"\n详情' in e["message"] for e in events))

    def test_cancel_callback_and_reconnect(self):
        events = self.run_helper(["connect", f"send\t327681\t{self.file}", "connect"], "cancel")
        self.assertTrue(any(e["event"] == "cancelled" for e in events))
        self.assertEqual(events[-1]["event"], "connected")

    def test_disconnect_prevents_transfer(self):
        events = self.run_helper(["connect", "disconnect", f"send\t327681\t{self.file}"])
        self.assertEqual(events[-1]["event"], "error")
        self.assertFalse(any(e["event"] == "sending" for e in events))

    def test_two_files_share_one_session(self):
        events = self.run_helper(["connect", f"send\t327681\t{self.file}", f"send\t327681\t{self.big}"])
        self.assertEqual(sum(e["event"] == "sent" for e in events), 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
