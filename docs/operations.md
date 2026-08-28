# Операторская инструкция

## Область

Инструкция описывает сборку и установку `forgejo` из COPR
`nos1609/forgejo-pam`. Она не разрешает изменение боевого сервера сама по себе.

## Подготовка

1. Проверьте дистрибутив и архитектуру.
2. Зафиксируйте установленный NVR и состояние службы.
3. Сохраните согласованную резервную копию базы Forgejo и `app.ini`.
4. Подготовьте предыдущий RPM и точные команды восстановления.
5. Остановите запись в базу перед резервным копированием и обновлением.

Проверьте текущее состояние:

```bash
rpm -q forgejo
systemctl status forgejo --no-pager
```

## Сборка в COPR

Проект поддерживает два chroot:

- `epel-10-x86_64`;
- `fedora-45-x86_64`.

Запустите сборку сохранённого SCM package:

```bash
copr-cli build-package forgejo-pam \
  --name forgejo \
  --chroot epel-10-x86_64 \
  --chroot fedora-45-x86_64
```

Считайте сборку успешной только после статуса `succeeded` для каждого chroot,
`Child return code was: 0` и наличия ожидаемых RPM в result metadata.

## Подключение репозитория

```bash
sudo dnf copr enable nos1609/forgejo-pam
dnf --showduplicates list forgejo
```

Проверьте, что выбран NVR с суффиксом `pam1` и правильным dist tag. Затем
установите или обновите пакет отдельной согласованной командой.

## Проверка RPM до установки

```bash
rpm -qp --requires ./forgejo-*.rpm | grep -E 'libpam|pam'
rpm -qpl ./forgejo-*.rpm | grep -E '20-pam-caps|forgejo_chkpwd_fix|forgejo-init'
rpmkeys --checksig ./forgejo-*.rpm
```

Проверку подписи выполняйте с ключом конкретного COPR-проекта в отдельном RPM
keyring или после штатного подключения репозитория.

## Проверка после установки

```bash
forgejo --version
ldd /usr/bin/forgejo | grep libpam
systemctl cat forgejo
systemctl show forgejo -p AmbientCapabilities
getfacl -cp /etc/shadow | grep '^user:forgejo:r--'
semodule -l | grep '^forgejo_chkpwd_fix'
journalctl -u forgejo -b --no-pager
```

Отдельно проверьте PAM-вход, обычный вход, git-over-HTTP, git-over-SSH и Actions.
Не помещайте пароль, OTP, cookie, приватный ключ и содержимое `app.ini` в журнал
приёмки.

## Откат

1. Остановите службу Forgejo.
2. Установите подготовленный предыдущий RPM.
3. Восстановите совместимые базу данных и `app.ini` из одной резервной копии.
4. Выполните `systemctl daemon-reload`.
5. Запустите службу и повторите проверки версии, журнала и основных протоколов.

Не считайте `dnf downgrade` полным откатом после миграции базы. Не удаляйте ACL
вручную, пока не установлено, что он принадлежит этому пакету.
