# Трассировка приёмки

Таблица связывает требование с проверяемым результатом. Старый успешный прогон
не подтверждает новый commit или новый chroot.

| Требование | Проверка | Текущий результат |
| --- | --- | --- |
| Публичный источник и совпадение refs | `git ls-remote` для `main` и `rawhide` в Forgejo и GitHub, сравнение OID попарно | 23 октября 2026 года: `main` Forgejo = `main` GitHub = `764bcd14cb85b03a61064b108c5efabdbbbc30ae`; `rawhide` Forgejo = `rawhide` GitHub = тот же OID |
| Точная основа Fedora | `git ls-remote` для Fedora `f45` и `git rev-parse` | `7e49254f963a7c488c654af213fee4e3e6b2c815`, Forgejo 15.0.10 |
| Проверка source archive | Source build и RPM `%prep` | COPR source stage `11196643` успешен; локальный `%prep`: подпись Forgejo `Good signature`, patch без fuzz |
| Чистая сборка EPEL 10 | COPR `epel-10-x86_64` | Build `11196643` — `succeeded` |
| Чистая сборка Fedora 45 | COPR `fedora-45-x86_64` | Build `11196643` — `succeeded` |
| PAM включён, EPEL 10 | `go version -m`, RPM requires | `11196643`, `forgejo-15.0.10-1.pam1.el10.x86_64.rpm`: tag `pam`, `libpam.so.0` |
| PAM включён, Fedora 45 | `go version -m`, RPM requires | `11196643`, `forgejo-15.0.10-1.pam1.fc45.x86_64.rpm`: tag `pam`, `libpam.so.0` |
| Привилегированная дельта, EPEL 10 | `rpm -qpl`: drop-in capabilities, SELinux-модуль, `forgejo-init` | `11196643`, RPM `el10`: все три файла есть |
| Привилегированная дельта, Fedora 45 | То же | `11196643`, RPM `fc45`: все три файла есть |
| RPM подписан, EPEL 10 | `rpmkeys --checksig` с отдельным keyring COPR | `11196643`, RPM `el10`: `digests signatures OK` |
| RPM подписан, Fedora 45 | То же | `11196643`, RPM `fc45`: `digests signatures OK` |
| GitHub workflow безопасен | CodeQL `actions` с `security-extended` | PR #1: `Analyze GitHub Actions` — `pass`, 28 августа 2026 года |
| Автоматическая рецензия | Опубликованный review CodeRabbit по последнему commit PR; статус `CodeRabbit: pass` без review не считается | 23 октября 2026 года: PR #1 — review `CHANGES_REQUESTED` от 28 августа, повторные ревью пропущены из-за исчерпанного бесплатного лимита OSS; PR #2 — одно замечание, исправляется отдельным PR |
| Работающий сервер | PAM, HTTP, SSH, Actions и журнал после установки | 23 октября 2026 года, `15.0.10-1.pam1` из COPR: HTTP, git-over-HTTP, Actions и журнал без ошибок; вход в браузере подтверждён владельцем; git-over-SSH не проверен |
| ACL `/etc/shadow` переживает правку учётных записей | Контрольное снятие ACL при установленных path и timer units, см. `operations.md` | 23 октября 2026 года: ACL восстановлен через 3,2 секунды на одном хосте |

## Критерий выпуска

Для публикации package commit нужны успешные сборки всех заявленных chroot,
успешный GitHub CodeQL check, закрытые существенные замечания CodeRabbit и
совпадающие refs Forgejo/GitHub. Установка на работающий сервер остаётся
отдельным решением с резервной копией и откатом.

С 23 октября 2026 года критерий для `main` проверяет GitHub ruleset
`protect-main`; порядок работы — в [`operations.md`](operations.md#порядок-изменений).
Перенос 15.0.10 (`764bcd1`) опубликован до введения ruleset без PR; его
ретроспективное ревью — PR #2.
