#!/usr/bin/env python3
"""Проверки комплекта. Не заменяют прогон на чистой Windows и на Intel Mac."""

import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NODE = os.environ.get("NODE", "node")


def sha256(path):
    digest = hashlib.sha256()
    digest.update(path.read_bytes())
    return digest.hexdigest()


class PlanTests(unittest.TestCase):
    def test_python_and_bash_agree(self):
        import importlib.util

        spec = importlib.util.spec_from_file_location("plan_file", ROOT / "lib" / "plan_file.py")
        plan = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(plan)
        cases = [
            ("", "abc", "", "COPY"),
            ("abc", "abc", "abc", "UNCHANGED"),
            ("old", "new", "old", "UPDATE"),
            ("user", "new", "old", "KEEP"),
            ("user", "new", "", "KEEP"),
        ]
        script = (ROOT / "lib" / "course_sync.sh").read_text(encoding="utf-8")
        for current, expected, previous, want in cases:
            self.assertEqual(plan.plan_action(current, expected, previous), want)
            got = subprocess.check_output(
                ["bash", "-c", script + '\nplan_action "$1" "$2" "$3"\n', "bash", current, expected, previous],
                text=True,
            ).strip()
            self.assertEqual(got, want)

    def test_bash_self_check(self):
        subprocess.check_call(["bash", str(ROOT / "install-macos.sh"), "--self-check"], cwd=ROOT)

    def test_status_table(self):
        import importlib.util

        spec = importlib.util.spec_from_file_location("plan_file", ROOT / "lib" / "plan_file.py")
        plan = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(plan)
        self.assertEqual(plan.decide_status(True, True, True, True, True, True, "BASIC", False, False), "ГОТОВО")
        self.assertEqual(plan.decide_status(True, True, True, True, True, False, "BASIC", False, False), "ЧАСТИЧНО")
        self.assertEqual(plan.decide_status(True, False, True, True, True, True, "BASIC", True, True), "ТРЕБУЕТСЯ ПОМОЩЬ")


class PackTests(unittest.TestCase):
    def test_hashes_and_zip(self):
        files = ROOT / "course-pack" / "files"
        sums = (ROOT / "course-pack" / "SHA256SUMS").read_text(encoding="utf-8").splitlines()
        seen = []
        for line in sums:
            digest, rel = line[:64], line[66:]
            seen.append(rel)
            self.assertEqual(sha256(files / rel), digest)
            self.assertNotIn("10_Материалы", rel)
            self.assertNotIn("Намеренные_ошибки", rel)
        self.assertIn("НАЧАЛО.md", seen)
        self.assertIn("День_3_MCP.md", seen)
        self.assertTrue(any("День_1" in rel for rel in seen))
        manifest = json.loads((ROOT / "course-pack" / "manifest.json").read_text(encoding="utf-8"))
        zip_path = ROOT / "docs" / "files" / manifest["zip_name"]
        self.assertEqual(sha256(zip_path), manifest["zip_sha256"])
        self.assertEqual(sha256(ROOT / "course-pack" / manifest["zip_name"]), manifest["zip_sha256"])
        with zipfile.ZipFile(zip_path) as archive:
            names = set(archive.namelist())
        self.assertIn("11_Пакеты_по_дням/День_1/Задание.md", names)
        self.assertTrue(all(not name.startswith("10_") for name in names))

    def test_no_secrets_or_private_addresses(self):
        secret = re.compile(
            r"(?i)(api[_-]?key|token|password|secret|bearer)\s*[:=]\s*['\"]?[A-Za-z0-9_\-]{12,}"
        )
        private = re.compile(r"\b(?:192\.168|10|172\.(?:1[6-9]|2\d|3[01]))\.\d{1,3}\.\d{1,3}\b")
        roots = [
            ROOT / "docs",
            ROOT / "prompts-src",
            ROOT / "pack-extra",
            ROOT / "config",
            ROOT / "course-pack" / "files",
        ]
        roots += list(ROOT.glob("*.md"))
        roots += list((ROOT / "lib").glob("*"))
        text_paths = []
        for item in roots:
            if item.is_file():
                text_paths.append(item)
            elif item.is_dir():
                text_paths.extend(path for path in item.rglob("*") if path.is_file() and path.suffix != ".zip")
        for path in text_paths:
            text = path.read_text(encoding="utf-8", errors="replace")
            self.assertIsNone(secret.search(text), path)
            self.assertIsNone(private.search(text), path)

    def test_scripts_do_not_disable_os_protection(self):
        mac = (ROOT / "install-macos.sh").read_text(encoding="utf-8")
        win = (ROOT / "install-windows.ps1").read_text(encoding="utf-8")
        cmd = (ROOT / "Setup-Course.cmd").read_text(encoding="utf-8")
        for banned in ("sudo", "spctl", "xattr", "csrutil", "curl | bash", "curl|bash"):
            self.assertNotIn(banned, mac)
        for banned in ("Set-MpPreference", "EnableLUA", "Invoke-Expression", "iex ", "DisableRealtimeMonitoring"):
            self.assertNotIn(banned, win)
        self.assertIn("-ExecutionPolicy Bypass -File", cmd)
        self.assertNotIn("Unrestricted", cmd)


class SyncTests(unittest.TestCase):
    def test_cyrillic_keep_and_update(self):
        tmp = Path(tempfile.mkdtemp(prefix="course-sync-", dir=str(ROOT / ".test-tmp")))
        src = tmp / "src" / "День_1"
        dest = tmp / "dest"
        src.mkdir(parents=True)
        (src / "Заметка.md").write_text("исходный текст\n", encoding="utf-8")
        digest = sha256(src / "Заметка.md")
        sums = tmp / "SHA256SUMS"
        sums.write_text("%s  %s\n" % (digest, "День_1/Заметка.md"), encoding="utf-8")
        state = dest / ".course-setup.state"
        script = r'''
. "$ROOT/lib/course_sync.sh"
mkdir -p "$DEST"
printf 'pack_version=test\n' > "$STATE"
sync_tree "$SRC" "$DEST" "$SUMS" "$STATE"
printf 'pack_version=test\n' > "$STATE"
sync_tree "$SRC" "$DEST" "$SUMS" "$STATE"
printf '\nправка участника\n' >> "$DEST/День_1/Заметка.md"
sync_tree "$SRC" "$DEST" "$SUMS" "$STATE"
'''
        env = os.environ.copy()
        env.update({
            "ROOT": str(ROOT),
            "SRC": str(tmp / "src"),
            "DEST": str(dest),
            "SUMS": str(sums),
            "STATE": str(state),
        })
        subprocess.check_call(["bash", "-c", script], env=env)
        text = (dest / "День_1" / "Заметка.md").read_text(encoding="utf-8")
        self.assertIn("исходный текст", text)
        self.assertIn("правка участника", text)
        shutil.rmtree(tmp)

    def test_corrupt_tree_rejected(self):
        tmp = Path(tempfile.mkdtemp(prefix="course-bad-", dir=str(ROOT / ".test-tmp")))
        (tmp / "a.txt").write_text("один\n", encoding="utf-8")
        sums = tmp / "SHA256SUMS"
        sums.write_text("%s  %s\n" % ("0" * 64, "a.txt"), encoding="utf-8")
        script = '. "$ROOT/lib/course_sync.sh"\nverify_tree "$SRC" "$SUMS"\n'
        env = os.environ.copy()
        env.update({"ROOT": str(ROOT), "SRC": str(tmp), "SUMS": str(sums)})
        result = subprocess.run(["bash", "-c", script], env=env)
        self.assertNotEqual(result.returncode, 0)
        shutil.rmtree(tmp)


class InstallerTests(unittest.TestCase):
    def test_dry_run_does_not_create_folder(self):
        dest = Path(tempfile.mkdtemp(prefix="course-dry-", dir=str(ROOT / ".test-tmp")))
        shutil.rmtree(dest)
        env = os.environ.copy()
        env.update({"COURSE_SETUP_TEST": "1", "COURSE_HOME": str(dest)})
        result = subprocess.run(
            ["bash", str(ROOT / "install-macos.sh"), "--dry-run", "--mode", "basic"],
            cwd=ROOT,
            env=env,
            text=True,
            capture_output=True,
            timeout=60,
        )
        self.assertIn("dry-run", result.stdout)
        self.assertFalse(dest.exists(), result.stdout)
        self.assertIn(result.returncode, (0, 2), result.stdout + result.stderr)

    def test_repeat_keeps_user_file(self):
        dest = Path(tempfile.mkdtemp(prefix="course-apply-", dir=str(ROOT / ".test-tmp")))
        env = os.environ.copy()
        env.update({"COURSE_SETUP_TEST": "1", "COURSE_HOME": str(dest)})
        first = subprocess.run(
            ["bash", str(ROOT / "install-macos.sh"), "--yes", "--mode", "BASIC"],
            cwd=ROOT,
            env=env,
            text=True,
            capture_output=True,
            timeout=90,
        )
        self.assertIn(first.returncode, (0, 2), first.stdout + first.stderr)
        start = dest / "НАЧАЛО.md"
        self.assertTrue(start.is_file())
        start.write_text(start.read_text(encoding="utf-8") + "\nправка участника\n", encoding="utf-8")
        second = subprocess.run(
            ["bash", str(ROOT / "install-macos.sh"), "--yes", "--mode", "BASIC"],
            cwd=ROOT,
            env=env,
            text=True,
            capture_output=True,
            timeout=90,
        )
        self.assertIn(second.returncode, (0, 2), second.stdout + second.stderr)
        self.assertIn("правка участника", start.read_text(encoding="utf-8"))
        self.assertNotIn("supersecret", second.stdout)
        log = second.stdout + second.stderr
        self.assertNotRegex(log, r"token=supersecret")
        shutil.rmtree(dest)


class PortalTests(unittest.TestCase):
    def test_deeplink_matches_node_and_sources(self):
        sources = json.loads((ROOT / "config" / "sources.json").read_text(encoding="utf-8"))
        portal = (ROOT / "docs" / "js" / "portal.js").read_text(encoding="utf-8")
        self.assertIn(sources["workai_web_prompt"], portal)
        self.assertIn(sources["workai_client_prompt"], portal)
        self.assertIn(sources["deeplink_max_chars"], portal)
        self.assertNotIn("innerHTML", portal)
        node = r'''
const portal = require(process.argv[1]);
const short = portal.workaiHref("Привет & мир");
if (!short.startsWith("https://workai.su/link/prompt?text=")) process.exit(2);
if (!short.includes(encodeURIComponent("Привет & мир"))) process.exit(3);
const long = "я".repeat(1400);
if (portal.workaiHref(long) !== null) process.exit(4);
const fit = "я".repeat(1200);
if (!portal.workaiHref(fit)) process.exit(5);
'''
        subprocess.check_call([NODE, "-e", node, str(ROOT / "docs" / "js" / "portal.js")])

    def test_prompts_are_not_inlined_in_html(self):
        html = "\n".join(path.read_text(encoding="utf-8") for path in (ROOT / "docs").glob("*.html"))
        ids = []
        for path in sorted((ROOT / "prompts-src").glob("*.json")):
            data = json.loads(path.read_text(encoding="utf-8"))
            ids.append(data["id"])
            self.assertNotIn(data["text"], html)
            self.assertIn('src="prompts/%s.js"' % data["id"], html)
            script = (ROOT / "docs" / "prompts" / ("%s.js" % data["id"])).read_text(encoding="utf-8")
            self.assertIn(json.dumps(data["title"], ensure_ascii=False), script)
        self.assertGreaterEqual(len(ids), 8)

    def test_pages_exist(self):
        for name in (
            "index.html", "prepare.html", "day1.html", "day2.html", "day3.html", "day4.html",
            "prompts.html", "download.html", "faq.html", "workai.html", ".nojekyll",
        ):
            self.assertTrue((ROOT / "docs" / name).is_file(), name)
        day3 = (ROOT / "docs" / "day3.html").read_text(encoding="utf-8")
        self.assertNotIn("token=", day3.lower())
        self.assertIn("SeverProm MCP Lab", day3)


class Launchers(unittest.TestCase):
    def test_command_is_executable_and_cmd_has_crlf(self):
        command = ROOT / "Setup-Course.command"
        mode = command.stat().st_mode
        self.assertTrue(mode & stat.S_IXUSR)
        cmd = (ROOT / "Setup-Course.cmd").read_bytes()
        self.assertIn(b"\r\n", cmd)
        ps1 = (ROOT / "install-windows.ps1").read_bytes()
        self.assertTrue(ps1.startswith(b"\xef\xbb\xbf"))


if __name__ == "__main__":
    unittest.main()
