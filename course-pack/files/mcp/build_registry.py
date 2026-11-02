#!/usr/bin/env python3
"""Собирает реестр из шапок markdown и фиксированных строк задач, проектов и KPI."""
import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "09_Учебная_система"
SKIP = {"10_Материалы_для_преподавателя", "11_Пакеты_по_дням", "12_Помощники", "mcp"}

TASK_FIELDS = [
    "task_id", "case_id", "project_id", "title", "owner", "due",
    "sed_status", "actual_status", "updated", "classification",
]
PROJECT_FIELDS = [
    "project_id", "name", "owner", "reported_pct", "reported_status",
    "reported_as_of", "actual_status", "actual_as_of", "budget_plan_mln",
    "budget_fact_mln", "case_id",
]
KPI_FIELDS = [
    "kpi_id", "name", "period", "unit", "plan", "value_sales",
    "value_finance", "value_other", "source", "notes",
]


def frontmatter(path: Path) -> dict:
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---\n"):
        return {}
    body = text.split("---\n", 2)[1]
    meta = {}
    for line in body.splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        meta[key.strip()] = value.strip().strip('"')
    return meta


def write(name, fields, rows):
    with (DATA / name).open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def documents():
    rows = []
    for path in sorted(ROOT.rglob("*.md")):
        if any(part in SKIP for part in path.relative_to(ROOT).parts):
            continue
        meta = frontmatter(path)
        if "document_id" not in meta:
            continue
        rows.append({
            "document_id": meta["document_id"],
            "case_id": meta.get("case_id", ""),
            "path": path.relative_to(ROOT).as_posix(),
            "title": meta.get("title", ""),
            "owner": meta.get("owner", ""),
            "created": meta.get("created", ""),
            "valid_until": meta.get("valid_until", ""),
            "as_of": meta.get("as_of", ""),
            "version": meta.get("version", ""),
            "approval_status": meta.get("approval_status", ""),
            "classification": meta.get("classification", ""),
            "source_system": meta.get("source_system", ""),
        })
    ids = [row["document_id"] for row in rows]
    if len(ids) != len(set(ids)):
        raise SystemExit("duplicate document_id")
    return rows


def main():
    docs = documents()
    write("documents.csv", list(docs[0]), docs)
    write("tasks.csv", TASK_FIELDS, [
        dict(zip(TASK_FIELDS, row)) for row in [
            ["T-184", "CASE-K12-001", "", "Снизить DSO до 42 дней", "И. Орлов", "2026-06-30", "исполнено", "не_достигнуто", "2026-07-02", "внутренний"],
            ["T-K12-01", "CASE-K12-001", "PRJ-SUP2", "Закрыть дефицит PO-778", "Е. Лебедева", "2026-07-15", "в_работе", "срок_сорван_поставщиком", "2026-07-04", "внутренний"],
            ["T-K12-02", "CASE-K12-001", "PRJ-ERP", "Провести брак 40 шт К-12", "Н. Козлов", "2026-07-15", "открыто", "не_проведён", "2026-07-03", "внутренний"],
            ["T-ERP-01", "CASE-ERP-001", "PRJ-ERP", "Снять замечания склада по обучению", "С. Морозов", "2026-06-30", "исполнено", "жалобы_открыты", "2026-07-05", "внутренний"],
            ["T-ERP-02", "CASE-ERP-001", "PRJ-ERP", "Закрыть период июня", "Н. Козлов", "2026-07-05", "в_работе", "нельзя_закрыть", "2026-07-01", "внутренний"],
            ["T-ERP-03", "CASE-ERP-001", "PRJ-ERP", "Восстановить синхронизацию закупок", "С. Морозов", "2026-07-10", "открыто", "таймаут", "2026-07-05", "внутренний"],
            ["T-TEAM-01", "CASE-TEAM-001", "", "Оформить передачу клиентов Сидорова", "Р. Новиков", "2026-07-20", "не_создано", "не_начато", "2026-07-16", "конфиденциально"],
            ["T-TEAM-02", "CASE-TEAM-001", "", "Закрыть вакансию после Кравцова", "Р. Новиков", "2026-07-31", "в_работе", "нет_оффера", "2026-07-16", "внутренний"],
            ["T-SVC-01", "CASE-TEAM-001", "PRJ-SVC", "Реакция по SRV-214 и SRV-221", "К. Васильева", "2026-07-08", "открыто", "sla_нарушен", "2026-07-10", "внутренний"],
        ]
    ])
    write("projects.csv", PROJECT_FIELDS, [
        dict(zip(PROJECT_FIELDS, row)) for row in [
            ["PRJ-ERP", "Внедрение ERP", "С. Морозов", "85", "зелёный", "2026-07-05", "период_июня_не_закрыт", "2026-07-05", "18", "16.4", "CASE-ERP-001"],
            ["PRJ-SUP2", "Второй поставщик К-12", "Е. Лебедева", "10", "красный", "2026-07-04", "договор_не_подписан", "2026-07-04", "0", "0", "CASE-K12-001"],
            ["PRJ-SVC", "Портал заявок сервиса", "К. Васильева", "40", "жёлтый", "2026-07-09", "пилот_не_запущен", "2026-07-09", "3.0", "1.1", "CASE-TEAM-001"],
        ]
    ])
    write("kpi.csv", KPI_FIELDS, [
        dict(zip(KPI_FIELDS, row)) for row in [
            ["REV-2026-06", "Выручка", "2026-06", "млн руб.", "42.0", "40.5", "39.8", "", "CRM и 1С", "разные периметры"],
            ["MRG-2026-06", "Маржа", "2026-06", "процент", "14", "15", "12", "", "отчёты июня", "общей методики нет"],
            ["DSO-2026-06", "Дебиторка", "2026-06", "дни", "42", "44", "48", "", "СЭД и отчёты", "поручение исполнено, цель не достигнута"],
            ["K12-MAIN", "Остаток К-12 основной склад", "2026-06-30", "шт", "", "", "", "ERP 420; Excel 380", "склад", "буфер линии 0"],
            ["SHIP-2026-06", "Отгрузки", "2026-06", "шт", "", "87", "83", "устно около 120; выпуск 92", "CRM ERP производство", "разные контуры"],
            ["OTIF-2026-06", "OTIF", "2026-06", "процент", "", "", "", "71", "логистика", "числовая цель OTIF не задана"],
            ["ERP-PCT", "Готовность ERP в отчёте PMO", "2026-07-05", "процент", "", "", "", "85", "отчёт PMO", "зелёный статус не закрывает период"],
            ["SVC-REV", "Выручка сервиса", "2026-06", "млн руб.", "4.0", "", "3.6", "", "план-факт", "не измеряет SLA"],
        ]
    ])
    print(f"documents {len(docs)}")


if __name__ == "__main__":
    main()
