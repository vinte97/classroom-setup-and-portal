# Курс «ИИ для руководителей v2» — установка и портал

Комплект для группы 10–15 человек. Участник дважды щёлкает запуск, получает папку `Документы/AI-Managers-v2` и открывает статический портал. Регистрации, базы и сборки на компьютере участника нет.

Инструкция участника: [STUDENT.md](STUDENT.md). Что не проверялось на живых машинах: [LIMITATIONS.md](LIMITATIONS.md).

## Режимы

- **BASIC** — учебные файлы и страница WorkAI.
- **ADVANCED** — то же плюс Git и Python 3.12, если их ещё нет. Уже стоящие версии скрипт не заменяет.

Windows: `Setup-Course.cmd`. Mac: правый щелчок по `Setup-Course.command` → «Открыть».

Для тишины в терминале:

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-windows.ps1 -Mode BASIC -Yes
```

```bash
./install-macos.sh --mode basic --yes
```

`--dry-run` печатает план и ничего не меняет. Итог: **ГОТОВО**, **ЧАСТИЧНО** или **ТРЕБУЕТСЯ ПОМОЩЬ**.

## WorkAI

Тихой установки и идентификатора winget в документации WorkAI нет. Скрипт открывает [страницу загрузки](https://workai.su/download) или локальный `.dmg` / `.exe` из `offline/workai`, если ведущий положил его туда сам. Мастер проходит человек. Скрипт не отключает UAC, SmartScreen, Gatekeeper и интеллектуальное управление приложениями.

Если Windows 11 блокирует установщик интеллектуальным управлением приложений, см. [официальную справку](https://workai.su/docs/get-started/install-windows). Выключение этой функции необратимо без переустановки Windows, поэтому скрипт его не делает.

Git на Windows ставится через winget, идентификатор `Git.Git`. Python — `Python.Python.3.12`, в профиль пользователя. На Mac, если есть Homebrew, формулы `git` и `python@3.12`. Homebrew скрипт сам не устанавливает. Запасные страницы: [Git](https://git-scm.com/download/win), [Python](https://www.python.org/downloads/windows/).

## Учебные файлы

Пакет версии 1.0.0 собирается из соседней папки `company/v2` без материалов ведущего (`10_Материалы_для_преподавателя`).

```bash
python3 tools/build_assets.py
python3 -m unittest discover -s tests -v
```

Повторный запуск копирует только новые и нетронутые файлы. Файл, который участник изменил, остаётся. Контрольные суммы: `course-pack/SHA256SUMS` и `course-pack/ZIP.SHA256`.

Без сети скрипт берёт `course-pack/files`. Если этой папки нет, ищет zip с той же суммой в `offline/`, `course-pack/` или `docs/files/`. Адрес в `course-pack/download.url` используется только как запасной, и скачанный файл сверяется с SHA-256. В журнал не пишутся значения после `token`, `password`, `secret`, `api_key`, `bearer` и `authorization`.

## Портал

Страницы лежат в `docs/`. Тексты промптов — в `prompts-src/*.json`, на сайт попадают отдельными `docs/prompts/*.js`, не внутрь HTML. Кнопка WorkAI открывает `https://workai.su/link/prompt?text=` через `encodeURIComponent`. Если ссылка `workai://share/prompt?text=` длиннее 8000 символов, остаётся копирование. Лимит описан в [документации ссылок WorkAI](https://workai.su/docs/configuration/deeplinks).

Локально: открыть `docs/index.html` или поднять любой статический сервер из `docs/`. Ссылки относительные, поэтому GitHub Pages из папки `/docs` не требует отдельного базового пути.

Публикация: в репозитории Settings → Pages → Deploy from a branch → папка `/docs`. После этого впишите адрес в `config/sources.json` в поле `portal_url`. Пока оно пустое, скрипт проверяет только локальный `docs/index.html`.

## День 3 и MCP

На портале и в `pack-extra/День_3_MCP.md` только общий порядок. Адрес SeverProm MCP Lab и ключ участника ведущий выдаёт отдельно. В репозиторий их не класть.
