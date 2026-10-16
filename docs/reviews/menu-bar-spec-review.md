# Menu-bar app specification — independent review

Reviewed saved specification: [menu-bar-app-spec.md](../menu-bar-app-spec.md).
Date: 2026-10-10. Reviewer: package_review, independent of the specification author.
Rubric: the shared eight-criterion specification rubric. Approval requires mean score ≥95 and no unresolved blocking issues.

## Iteration 1

```text
SCORE: 95.25
CRITERIA:
  motivation: 99 — Цель и пользовательская польза сформулированы ясно.
  scope: 98 — Ограничения устройств, действий, зависимостей и запрещённых обходных путей явные.
  success_criteria: 97 — Разделены готовность development candidate, физическая приёмка и публичный выпуск.
  edge_cases: 86 — Не определены восстановление после частичного uninstall и завершение уже начатого синтетического нажатия при отмене/отключении.
  dependencies: 96 — Фреймворки, минимальная ОС, разрешения, взаимодействие автора и ограничения подписи указаны.
  implementation: 94 — Порядок исполним; аппаратный gate не подменён успешной компиляцией. Требуется уточнить два аварийных перехода.
  test_plan: 94 — Основные сценарии перечислены; добавить проверки сохранения recovery receipt после неудачного uninstall и удаления/отключения между key-down и key-up.
  open_questions: 98 — Гибридный маршрут, разрешения, миграция и self-Trash честно обозначены открытыми gates.
BLOCKING_ISSUES:
  - «Uninstall ... clear only an exactly owned rule, unregister the app's login item, remove only its preferences/support files, and quit» и «Never call partial removal complete» не задают поведение при ошибке очистки правила или unregister. Одного сообщения о частичном результате недостаточно: последующее удаление receipt/app может лишить пользователя восстановления. Уточнить: отключить сохранённое намерение и обработчики; при непроверенном сбросе собственного правила или неудачном unregister сохранять receipt и приложение, не запускать self-Trash, показывать повтор операции/конкретный остаток. Чужое правило, которое сознательно сохранено, отличать от ошибки собственного cleanup.
  - «posts the configured key-down/key-up ... once per press/release cycle» и «On read/post failure, stop chord input» не определяют судьбу уже отправленного key-down, если устройство удалено, профиль изменён, режим выключен или разрешение отозвано до key-up. Зафиксировать простой вариант: на первоначальном физическом down отправлять завершённую пару down/up, а release использовать только для повторного взведения; либо явно вести pressed-output state и освобождать его на всех переходах. Добавить соответствующие аварийные тесты и честный статус при невозможности освобождения.
APPROVED: false
```

Both findings were accepted. The revised specification uses a complete synchronous synthetic pair, specifies a release attempt and honest delivery status on capability loss, and retains recovery state/app after cleanup failures. Matching tests were added to the plan.

## Iteration 2

```text
SCORE: 97.5
CRITERIA:
  motivation: 99 — Цель и пользовательская польза сформулированы ясно.
  scope: 98 — Поддерживаемые действия, устройства и ограничения реализации явные; запрещённые обходные пути не скрыты.
  success_criteria: 98 — Готовность development candidate отделена от физических проверок на двух Mac и публичного выпуска.
  edge_cases: 97 — Оба блокера исправлены: завершённая синтетическая пара и честный статус доставки; сохранение receipt/app и запрет self-Trash при неудачном cleanup.
  dependencies: 96 — ОС, фреймворки, разрешения, взаимодействие автора и ограничения подписи указаны.
  implementation: 96 — Шаги исполнимы, аппаратная проверка отделена от компиляции, миграция и откат сохраняют владение настройками.
  test_plan: 97 — Добавлены аварийные проверки emitter и сохранения recovery-состояния; программные и физические результаты разделены.
  open_questions: 99 — Гибридный маршрут, реальные разрешения, персональная миграция и self-Trash явно остаются открытыми gates.
BLOCKING_ISSUES: []
APPROVED: true
```

No findings were rejected. This approves the specification, not completed implementation, hardware acceptance, migration, public signing or publication.
