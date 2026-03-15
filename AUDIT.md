# Hook System Audit Prompt

Copy-paste this into a new Claude Code session to run a full audit of the hook system.

```
Полный аудит системы хуков. Цель: найти баги, edge cases, inconsistencies.

## Что сделать

### 1. Прочитай ВСЕ файлы

Глобальные хуки (оригиналы — правь ТОЛЬКО тут):
- `C:/Users/Dima/Documents/GitHub/claude-code-config/global/hooks/block-dangerous-git.sh`
- `C:/Users/Dima/Documents/GitHub/claude-code-config/global/hooks/block-protected-files.sh`
- `C:/Users/Dima/Documents/GitHub/claude-code-config/global/hooks/auto-lint-python.sh`
- `C:/Users/Dima/Documents/GitHub/claude-code-config/global/hooks/auto-lint-typescript.sh`
- `C:/Users/Dima/Documents/GitHub/claude-code-config/global/hooks/pre-commit-review.sh`
- `C:/Users/Dima/Documents/GitHub/claude-code-config/global/hooks/ripple-check.sh`
- `C:/Users/Dima/Documents/GitHub/claude-code-config/global/hooks/test-hooks.sh`

Проектные хуки investments-calculator (проектные override глобальных):
- `C:/Users/Dima/Documents/GitHub/investments-calculator/.claude/hooks/pre-commit-review.sh`
- `C:/Users/Dima/Documents/GitHub/investments-calculator/.claude/hooks/auto-lint-typescript.sh`
- `C:/Users/Dima/Documents/GitHub/investments-calculator/.claude/hooks/check-css-variables.sh`
- `C:/Users/Dima/Documents/GitHub/investments-calculator/.claude/hooks/test-hooks.sh`

Проектные хуки Timesheet:
- `C:/Users/Dima/Documents/GitHub/Timesheet/.claude/hooks/pre-commit-review.sh`
- `C:/Users/Dima/Documents/GitHub/Timesheet/.claude/hooks/auto-lint-typescript.sh`

Проектные хуки ClipboardHistory:
- `C:/Users/Dima/Documents/GitHub/ClipboardHistory/.claude/hooks/pre-commit-review.sh`

settings.json (все три):
- `C:/Users/Dima/Documents/GitHub/claude-code-config/global/settings.json` (= ~/.claude/settings.json через симлинк)
- `C:/Users/Dima/Documents/GitHub/investments-calculator/.claude/settings.json`
- `C:/Users/Dima/Documents/GitHub/Timesheet/.claude/settings.json` (если есть)
- `C:/Users/Dima/Documents/GitHub/ClipboardHistory/.claude/settings.json` (если есть)

CLAUDE.md:
- `C:/Users/Dima/Documents/GitHub/claude-code-config/global/CLAUDE.md` §9 Global Hooks

Прочитай секцию "Last Audit" внизу этого файла — это контекст прошлого аудита.

### 2. Запусти тесты
```bash
# Глобальные тесты (35 tests)
bash ~/.claude/hooks/test-hooks.sh

# Проектные тесты investments-calculator (106 tests)
cd /c/Users/Dima/Documents/GitHub/investments-calculator && bash .claude/hooks/test-hooks.sh
```

### 3. Test coverage
- Для КАЖДОГО regex/pattern в хуках — есть ли тест? Если нет — добавь.
- Новые тесты для глобальных хуков → в global/hooks/test-hooks.sh
- Новые тесты для проектных хуков → в .claude/hooks/test-hooks.sh того проекта

### 4. Consistency check
- JSON extraction pattern одинаковый во ВСЕХ hook файлах?
- Symlinks: `ls -la ~/.claude/hooks/` — все файлы симлинки на claude-code-config/global/hooks/?

### 5. Double-fire prevention
Архитектура: глобальные и проектные хуки fire на одно событие. Предотвращение:
- **pre-commit-review.sh (global)**: скипает если `.claude/hooks/pre-commit-review.sh` существует в проекте
- **auto-lint-typescript.sh (global)**: скипает если `.claude/hooks/auto-lint-typescript.sh` существует в проекте
- **auto-lint-python.sh (global)**: НЕ имеет double-fire prevention (ни один проект не override)
- **ripple-check.sh (global)**: НЕ имеет double-fire prevention (ни один проект не override)
- **block-dangerous-git.sh, block-protected-files.sh**: НЕ имеет (ни один проект не override)

Проверь:
- investments-calculator: global pre-commit/auto-lint-ts ДОЛЖНЫ скипаться (есть проектные)
- Timesheet: глобальный pre-commit/auto-lint-ts ДОЛЖНЫ скипаться (есть проектные)?
- ClipboardHistory: глобальный pre-commit ДОЛЖЕН скипаться (есть проектный)?
- Проекты БЕЗ своих хуков: глобальные ДОЛЖНЫ работать
- Нет ли проекта который получает double-fire? Проверь реально.

### 6. Для КАЖДОГО хука
- **3 false positives**: легитимные команды которые ложно блокируются — промоделируй regex
- **3 false negatives**: опасные команды которые проходят — промоделируй regex
- **Edge cases**: кавычки в JSON, chained commands (&&, ;, |), Windows paths

### 7. Ripple check специфика
- Тест с файлами содержащими regex-спецсимволы в имени (app.test.tsx, module+utils.ts)
- Тест что grep -Fv корректно фильтрует basename (а не regex)
- Тест что timeout 3 работает (симулировать медленный grep сложно — как минимум убедись что таймаут не ломает exit 0)
- Тест что MAX_WARNINGS=5 реально ограничивает вывод

### 8. WHY-комментарии
- Каждый regex имеет WHY?
- Нет WHAT-комментариев (объясняющих как работает bash)?
- Не раздуто? (1 WHY на decision, не 1 на строку)

### 9. Пробелы
- Что в CLAUDE.md декларативное но не enforced хуками? Стоит ли enforce?

## Формат ответа

```
## ТЕСТЫ
## TEST COVERAGE (regex без тестов)
## CONSISTENCY
## DOUBLE-FIRE
## БАГИ [файл:строка → проблема → фикс]
## FALSE POSITIVES / NEGATIVES [таблица]
## КОММЕНТАРИИ
## ПРОБЕЛЫ И ROI [таблица]
## КОНКРЕТНЫЕ ПРАВКИ [файл → было → стало]
```

## Правила
- Будь критичен — ищи баги, не хвали
- Конкретные правки с кодом, не "можно улучшить"
- Применяй ВСЕ фиксы сам, не спрашивай
- WHY к новому коду: 1 WHY на decision
- Запусти тесты после правок
- Обнови CLAUDE.md §9 Hook Behavior секцию если поведение хуков изменилось (в обоих: global CLAUDE.md и investments-calculator CLAUDE.md)
- НЕ добавляй новые хуки без явного запроса
- ВАЖНО: файлы в ~/.claude/hooks/ это СИМЛИНКИ на claude-code-config/global/hooks/. Правь оригиналы в claude-code-config/global/hooks/, не симлинки.
- Проектные хуки (investments-calculator/.claude/hooks/) — это ОТДЕЛЬНЫЕ файлы, не симлинки. Они override глобальные. Правь их напрямую.
- После всех правок:
  1. `cd ~/Documents/GitHub/claude-code-config && git add -A && git commit -m "audit fixes" && git push`
  2. Если правил проектные хуки: коммит в том проекте тоже
- **Перезапиши секцию Last Audit** внизу этого файла своими находками (не дописывай — заменяй).
```

---

## Last Audit

**Date:** 2026-03-15 (3rd pass) | **Global tests:** 42/42 PASS | **Project tests (inv-calc):** 112/112 PASS

**Architecture:**
- 6 global hooks (block-dangerous-git, block-protected-files, pre-commit-review, auto-lint-python, auto-lint-typescript, ripple-check)
- pre-commit-review: Phase 1 (linters+tests) + Phase 2 (diff analysis). Both fully automated, NO marker bypass.
- Phase 2 checks: `any` types, empty catch/except, TODO/FIXME/HACK, console.log, commit size >500 lines, missing migrations, new files without tests
- investments-calculator overrides: pre-commit-review.sh, auto-lint-typescript.sh
- Timesheet overrides: pre-commit-review.sh, auto-lint-typescript.sh
- ClipboardHistory overrides: pre-commit-review.sh only
- Double-fire prevention via `[ -f ".claude/hooks/<name>.sh" ] && exit 0` in global hooks
- Timesheet/ClipboardHistory .claude/ dirs are untracked (local only)

**Found & fixed (this session):**
1. **Phase 2 replaced**: old advisory checklist (AI rubber-stamped `touch marker`) → automated diff analysis (no bypass)
2. **grep BRE bug**: `^\+\+\+` in BRE treated `\+` as quantifier, filtering ALL diff lines with `+` → fixed to `^+++`
3. **CLAUDE.md §4 enhanced**: added Read-Before-Edit Rule, Change Size Rule, Uncertainty Disclosure Rule, Test Failure Recovery Protocol
4. Phase 2 empty "Auto-checks passed:" display — fixed (2nd pass)
5. Timesheet/ClipboardHistory §12→§9 references — fixed (2nd pass)
6. +7 new global tests (35→42), +6 new project tests (106→112)

**Previous audit fixes still valid:** grep -Fv in ripple-check, uppercase .env, checkout HEAD ., restore --source patterns

**Known false positives (block-dangerous-git bypass marker):** `git restore --staged .`, `git checkout --ours .`, `git stash drop stash@{0}`, `git clean -fX`
**Known false negatives (by design):** variable expansion, nested scripts, split rm flags, git -C flag, `git push origin :main` (delete branch), uppercase `.ENV` on Windows
