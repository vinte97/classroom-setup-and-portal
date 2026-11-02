#!/usr/bin/env python3
"""Собрать учебный пакет, контрольные суммы и JS портала из prompts-src."""

import hashlib
import json
import shutil
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COURSE = ROOT.parent / "company" / "v2"
ALLOW = [
    "00_Компания",
    "01_Производство_и_логистика",
    "02_Продажи_и_клиенты",
    "03_Финансы",
    "04_HR_и_персонал",
    "05_Проекты_и_IT",
    "06_Сервис",
    "07_Совещания_и_поручения",
    "08_Сквозные_кейсы",
    "09_Учебная_система",
    "11_Пакеты_по_дням",
    "12_Помощники",
    "mcp",
]
SKIP_NAMES = {".DS_Store", ".gitignore"}


def sha256(path):
    digest = hashlib.sha256()
    digest.update(path.read_bytes())
    return digest.hexdigest()


def iter_files(folder):
    for path in sorted(folder.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(folder)
        if any(part == "__pycache__" or part.startswith(".") for part in rel.parts):
            continue
        if path.name in SKIP_NAMES:
            continue
        yield path


def js_literal(value):
    raw = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    return (
        raw.replace("<", "\\u003c")
        .replace("\u2028", "\\u2028")
        .replace("\u2029", "\\u2029")
    )


def copy_pack(dest):
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)
    if not COURSE.is_dir():
        raise SystemExit("Нет папки company/v2 рядом с проектом: %s" % COURSE)
    for name in ALLOW:
        src = COURSE / name
        if not src.exists():
            raise SystemExit("В company/v2 нет %s" % name)
        target = dest / name
        if src.is_dir():
            shutil.copytree(
                src,
                target,
                ignore=shutil.ignore_patterns("__pycache__", ".DS_Store", ".gitignore"),
            )
        else:
            shutil.copy2(src, target)
    extra = ROOT / "pack-extra"
    for path in extra.iterdir():
        if path.is_file():
            shutil.copy2(path, dest / path.name)
    student = ROOT / "STUDENT.md"
    if student.is_file():
        shutil.copy2(student, dest / "ИНСТРУКЦИЯ_УЧАСТНИКА.md")


def write_sums(files_dir):
    rows = []
    for path in iter_files(files_dir):
        rel = path.relative_to(files_dir).as_posix()
        rows.append((sha256(path), rel))
    rows.sort(key=lambda item: item[1])
    text = "".join("%s  %s\n" % (digest, rel) for digest, rel in rows)
    sums = ROOT / "course-pack" / "SHA256SUMS"
    sums.write_bytes(text.encode("utf-8"))
    return rows


def write_zip(files_dir, zip_name, rows):
    targets = [
        ROOT / "course-pack" / zip_name,
        ROOT / "docs" / "files" / zip_name,
    ]
    for target in targets:
        target.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for _digest, rel in rows:
                info = zipfile.ZipInfo(rel)
                info.flag_bits |= 0x800
                info.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(info, (files_dir / rel).read_bytes())
    digest = sha256(targets[0])
    if sha256(targets[1]) != digest:
        raise SystemExit("Копии zip разошлись")
    (ROOT / "course-pack" / "ZIP.SHA256").write_bytes(
        ("%s  %s\n" % (digest, zip_name)).encode("utf-8")
    )
    return digest


def write_prompts():
    out = ROOT / "docs" / "prompts"
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    ids = []
    for path in sorted((ROOT / "prompts-src").glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        ids.append(data["id"])
        script = (
            "window.COURSE_PROMPTS = window.COURSE_PROMPTS || [];\n"
            "window.COURSE_PROMPTS.push(%s);\n" % js_literal(data)
        )
        (out / ("%s.js" % data["id"])).write_bytes(script.encode("utf-8"))
    return ids


def main():
    sources = json.loads((ROOT / "config" / "sources.json").read_text(encoding="utf-8"))
    version = sources["pack_version"]
    zip_name = "AI-Managers-v2-%s.zip" % version
    files_dir = ROOT / "course-pack" / "files"
    copy_pack(files_dir)
    rows = write_sums(files_dir)
    digest = write_zip(files_dir, zip_name, rows)
    manifest = {
        "name": "AI-Managers-v2",
        "version": version,
        "zip_name": zip_name,
        "zip_sha256": digest,
        "file_count": len(rows),
    }
    (ROOT / "course-pack" / "manifest.json").write_bytes(
        (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    )
    (ROOT / "docs" / "files").mkdir(parents=True, exist_ok=True)
    (ROOT / "docs" / "files" / "checksum.js").write_bytes(
        ("window.COURSE_PACK = %s;\n" % js_literal(manifest)).encode("utf-8")
    )
    write_prompts()
    print("files %s zip %s" % (len(rows), digest))


if __name__ == "__main__":
    main()
