# NetOps Installer

> Public bootstrap для приватного репозитория **NetOps Platform** — corporate network observability + alerting platform.

Этот репозиторий содержит **только один файл** — `install.sh`, который интерактивно запрашивает GitHub-учётные данные у оператора (логин + Personal Access Token) и затем скачивает реальный инсталлятор из приватной репы. **Никакие учётные данные не сохраняются на диске и не зашиты в код этого репозитория.**

---

## 🚀 Установка на новом сервере (Oracle Linux 8 / 9)

### Шаг 1 — оператор генерирует PAT для заказчика

1. Перейди: <https://github.com/settings/personal-access-tokens/new>
2. **Token name**: `netops-customer-XYZ` (имя заказчика)
3. **Resource owner**: твой GitHub user
4. **Expiration**: 90 days (потом нужна ротация)
5. **Repository access** → выбери «Only selected repositories» → отметь `sulaymanovulugbek/netops-platform`
6. **Permissions** → Repository permissions:
   - **Contents**: Read-only
   - **Metadata**: Read-only (auто-required)
7. **Generate token** → скопируй (`github_pat_...`) — больше его не увидишь
8. Передай заказчику:
   - Этот токен
   - Твой GitHub-логин (`sulaymanovulugbek`) ИЛИ создай для них отдельного read-only collaborator

### Шаг 2 — заказчик запускает на свежей OEL 8/9 VM (как root)

```bash
curl -fsSL https://raw.githubusercontent.com/sulaymanovulugbek/netops-installer/main/install.sh -o /tmp/install.sh
sudo bash /tmp/install.sh
```

> **Важно**: bootstrap требует TTY (интерактивный prompt). Поэтому `curl ... | sudo bash` **не сработает** — нужен 2-step download + run.

Bootstrap спросит:
```
  GitHub username: <операторский username>
  GitHub Personal Access Token (hidden): ****
```

После валидации (~1 секунда) пойдёт реальная установка:
1. Скачивание `install-oel.sh` из private репы
2. Pre-flight checks (OS / RAM / disk / `/opt` mount / network)
3. Установка docker-ce + compose plugin
4. SELinux + firewalld
5. `git clone` private репы в `/opt/netops-platform`
6. Генерация `.env` (random JWT/Fernet/DB password)
7. Применение 36 миграций
8. Systemd unit + автостарт
9. Healthcheck loop (до 5 мин)
10. Печать success banner с URL + admin/admin

**Время:** ~5-7 минут на свежем OEL 9.

---

## 🔄 Обновление установленной платформы

```bash
sudo /opt/netops-platform/install/update-oel.sh
```

Update тоже **запрашивает GitHub credentials** (никакого кэша). После prompt — `pg_dump backup` → `git fetch` → новые миграции → recreate containers → healthcheck. Если healthcheck падает >5 мин → авто-rollback инструкции.

---

## ⏪ Rollback

См. подробно: [`/opt/netops-platform/docs/release/ROLLBACK.md`](https://github.com/sulaymanovulugbek/netops-platform/blob/release/v1.0/docs/release/ROLLBACK.md) (4 сценария + flowchart).

Краткие команды:

| Сценарий | Команда |
|---|---|
| Откат к предыдущему тегу | `cd /opt/netops-platform && git fetch --tags && git checkout vPREV && docker compose down && docker compose up -d` |
| Restore DB из daily backup | `docker compose exec -T db pg_restore -U netops -d netops < /var/backups/netops-platform/<date>.dump` |
| Полная переустановка | `sudo /opt/netops-platform/install/uninstall-oel.sh --purge && sudo bash /tmp/install.sh` |

---

## 🗑 Деинсталляция

```bash
sudo /opt/netops-platform/install/uninstall-oel.sh           # сохранит volumes
sudo /opt/netops-platform/install/uninstall-oel.sh --purge   # удалит docker volumes + /opt/netops-platform
```

---

## 🩹 Что внутри bootstrap'a (для security review)

| Шаг | Что делает | Где идут credentials |
|---|---|---|
| 1 | TTY check + prompt | Только в memory shell process |
| 2 | `curl GET https://api.github.com/repos/...` с `Authorization: token` | HTTP header, не сохраняется |
| 3 | Скачивает `install-oel.sh` в `/tmp/install-oel-real.XXXX.sh` | File создаётся, потом `shred -u` в trap EXIT |
| 4 | `bash install-oel-real.sh` с `GITHUB_TOKEN=...` в env | Env переменная, видна `ps`, но без disk persist |
| 5 | `git clone https://oauth2:TOKEN@github.com/...` | Token временно в URL, далее remote URL переписывается без token |
| 6 | `git remote set-url origin https://github.com/...` (без token) | `.git/config` чистый — token удалён |
| 7 | `trap cleanup EXIT INT TERM` стирает $GH_TOKEN из памяти | Memory shred |

**Проверка**: после установки `cat /opt/netops-platform/.git/config | grep url` покажет URL **без** токена. `find / -name '.credentials' 2>/dev/null` ничего не найдёт.

---

## 🛠 Troubleshooting

| Симптом | Причина | Решение |
|---|---|---|
| `[FAIL] no TTY for interactive prompt` | Запустил через `curl ... \| sudo bash` | Скачай файл сначала, потом запусти отдельно: `curl ... -o /tmp/install.sh && sudo bash /tmp/install.sh` |
| `[FAIL] GitHub returned HTTP 404` | Токен валидный, но нет доступа к этой репе | Проверь что PAT scoped на `sulaymanovulugbek/netops-platform` |
| `[FAIL] GitHub returned HTTP 401` | Токен невалиден | Перегенерируй PAT (возможно expired) |
| `[FAIL] cannot reach download.docker.com` | Outbound firewall блокирует docker hub | Открой outbound 443 на сервере + proxy если за корпорат-сетью |
| `[FAIL] RAM ... < 4 GiB minimum` | Слишком слабая VM | Увеличь до 8 GiB как минимум (рекомендуется 16) |
| Установка зависает на step 9 healthcheck | Контейнеры не стартуют | `docker compose -f /opt/netops-platform/deploy/docker-compose.yml logs --tail 100` |

---

## 📋 Compatibility

| Layer | Versions |
|---|---|
| OS | Oracle Linux 8.x / 9.x · RHEL 8/9 · Rocky 8/9 · AlmaLinux 8/9 |
| Docker | docker-ce 24+ · compose-plugin 2.20+ |
| FortiOS | 7.2.12 (full) · 7.0+ (basic) |
| RouterOS | 7.x (full) |
| Dahua firmware | 2.800+ / 3.216+ (full) |
| Hikvision | basic support via ISAPI |

---

## 📞 Поддержка

- Issues: [sulaymanovulugbek/netops-platform/issues](https://github.com/sulaymanovulugbek/netops-platform/issues) (требуется доступ к private репе)
- Handbook (после установки): открой `http://server:13000/handbook` в браузере
- Customer deployment guide: [`docs/release/CUSTOMER-DEPLOYMENT.md`](https://github.com/sulaymanovulugbek/netops-platform/blob/release/v1.0/docs/release/CUSTOMER-DEPLOYMENT.md) (10 секций, RU)

---

## 📄 License

Apache 2.0 — см. [`LICENSE`](https://github.com/sulaymanovulugbek/netops-platform/blob/main/LICENSE) в основной репе.
