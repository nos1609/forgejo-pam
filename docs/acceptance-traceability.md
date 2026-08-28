# Трассировка приёмки

Таблица связывает требование с проверяемым результатом. Старый успешный прогон
не подтверждает новый commit или новый chroot.

| Требование | Проверка | Текущий результат |
| --- | --- | --- |
| Публичный источник | Анонимный `git ls-remote` для GitHub `main` и `rawhide` | Обе ветки опубликованы |
| Точная основа Fedora | `git ls-remote` для Fedora `f45` и `git rev-parse` | `ced1aa24b245770d46e72e14d18b323aba3dbf3f` |
| Проверка source archive | Source build и RPM `%prep` | COPR source stage `10915732` успешен |
| Чистая сборка EPEL 10 | COPR `epel-10-x86_64` | Build `10915732` — `succeeded` |
| Чистая сборка Fedora 45 | COPR `fedora-45-x86_64` | Build `10915756` — `succeeded` |
| PAM включён | `forgejo --version`, `go version -m`, RPM requires | Tag `pam` и `libpam.so.0` подтверждены для `10915732` |
| Привилегированная дельта входит в RPM | `rpm -qpl`, systemd и SELinux payload | Подтверждено для `10915732` |
| RPM подписан | `rpmkeys --checksig` с отдельным keyring COPR | `digests signatures OK` для `10915732` |
| GitHub workflow безопасен | CodeQL `actions` с `security-extended` | Ожидает первый GitHub run |
| Автоматическая рецензия | CodeRabbit review на PR | Ожидает первый PR и доступ GitHub App |
| Работающий сервер | PAM, HTTP, SSH, Actions и журнал после установки | Не выполнялось в этом репозитории |

## Критерий выпуска

Для публикации package commit нужны успешные сборки всех заявленных chroot,
успешный GitHub CodeQL check, закрытые существенные замечания CodeRabbit и
совпадающие refs Forgejo/GitHub. Установка на работающий сервер остаётся
отдельным решением с резервной копией и откатом.
