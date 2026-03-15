# Audit Prompt

Copy-paste this into a new Claude Code session to run a full audit of the hook system.

```
Полный аудит системы хуков. Цель: найти баги, edge cases, inconsistencies.

## Что сделать

### 1. Прочитай ВСЕ файлы
Глобальные хуки (симлинки на ~/Documents/GitHub/claude-code-config/global/):
- `C:/Users/Dima/.claude/hooks/block-dangerous-git.sh`
- `C:/Users/Dima/.claude/hooks/block-protected-files.sh`
- `C:/Users/Dima/.claude/hooks/auto-lint-python.sh`

Проектные хуки investments-calculator:
- `.claude/hooks/pre-commit-review.sh`
- `.claude/hooks/auto-lint-typescript.sh`
- `.claude/hooks/check-css-variables.sh`
- `.claude/hooks/test-hooks.sh`

Проектные хуки Timesheet:
- `C:/Users/Dima/Documents/GitHub/Timesheet/.claude/hooks/pre-commit-review.sh`
- `C:/Users/Dima/Documents/GitHub/Timesheet/.claude/hooks/auto-lint-typescript.sh`

Проектные хуки ClipboardHistory:
- `C:/Users/Dima/Documents/GitHub/ClipboardHistory/.claude/hooks/pre-commit-review.sh`

settings.json (оба):
- `C:/Users/Dima/.claude/settings.json`
- `.claude/settings.json`

### 2. Запусти тесты
cd /c/Users/Dima/Documents/GitHub/investments-calculator && bash .claude/hooks/test-hooks.sh

### 3. Consistency check
- Глобальные хуки (symlink targets в `claude-code-config/global/hooks/`) ИДЕНТИЧНЫ проектным копиям в investments-calculator `.claude/hooks/` для block-dangerous-git, block-protected-files, auto-lint-python? `diff` каждую пару.
- JSON extraction pattern одинаковый во ВСЕХ hook файлах?
- settings.json: глобальные хуки НЕ дублируются в проектных settings? (double-fire)
- Timesheet и ClipboardHistory хуки используют тот же JSON extraction?

### 4. Для КАЖДОГО хука
- **3 false positives**: легитимные команды которые ложно блокируются — промоделируй regex
- **3 false negatives**: опасные команды которые проходят — промоделируй regex
- **Edge cases**: кавычки в JSON, chained commands (&&, ;, |), Windows paths

### 5. WHY-комментарии
- Каждый regex имеет WHY?
- Нет WHAT-комментариев (объясняющих как работает bash)?
- Не раздуто? (1 WHY на decision, не 1 на строку)

### 6. Пробелы
- Что в CLAUDE.md декларативное но не enforced хуками? Стоит ли enforce?

## Формат ответа

## ТЕСТЫ
## CONSISTENCY
## БАГИ [файл:строка → проблема → фикс]
## FALSE POSITIVES / NEGATIVES [таблица]
## КОММЕНТАРИИ
## ПРОБЕЛЫ И ROI [таблица]
## КОНКРЕТНЫЕ ПРАВКИ [файл → было → стало]

## Правила
- Будь критичен — ищи баги, не хвали
- Конкретные правки с кодом, не "можно улучшить"
- Применяй ВСЕ фиксы сам, не спрашивай
- WHY к новому коду: 1 WHY на decision
- Запусти тесты после правок
- НЕ трогай project CLAUDE.md, НЕ добавляй новые хуки
- ВАЖНО: файлы в ~/.claude/hooks/ это СИМЛИНКИ на claude-code-config/global/hooks/. Правь оригиналы в claude-code-config/global/hooks/, не симлинки. Проектные копии в investments-calculator/.claude/hooks/ тоже обнови (должны быть идентичны глобальным для трёх общих хуков).
- После всех правок: cd ~/Documents/GitHub/claude-code-config && git add -A && git commit -m "audit fixes" && git push
```
