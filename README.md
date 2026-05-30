# NetOps Installer

> Public bootstrap для приватного репозитория **NetOps Platform** — corporate network observability + alerting.

Этот репозиторий содержит **только один файл** — `install.sh`, который интерактивно запрашивает у оператора GitHub-учётные данные и затем скачивает реальный инсталлятор из приватной репы. **Никакие учётные данные не сохраняются на диске и не зашиты в код.**

---

## 🚀 Установка на новом сервере (Oracle Linux 8 / 9)

### Команда установки (одна, на свежей VM, как root):

```bash
curl -fsSL https://raw.githubusercontent.com/sulaymanovulugbek/netops-installer/main/install.sh -o /tmp/install.sh
sudo bash /tmp/install.sh
```

Bootstrap спросит:

```
  GitHub username:                           <— уточните у владельца продукта
  GitHub Personal Access Token (hidden):     <— уточните у владельца продукта
```

> 📞 **Логин и токен уточняйте у владельца продукта** — Ulugbek Sulaymanov · GitHub [@sulaymanovulugbek](https://github.com/sulaymanovulugbek).
> Заказчику **не нужно** ничего регистрировать или генерировать самостоятельно. Владелец выдаёт credentials под каждого заказчика с TTL (90 дней) и read-only scope на единственный репозиторий.

> **Важно**: bootstrap требует TTY. `curl ... | sudo bash` **не работает** — нужен 2-шаговый download + run как показано выше.

### Что произойдёт

1. Валидация credentials через GitHub API (~1 секунда)
2. Скачивание реального `install-oel.sh` из приватной репы
3. Pre-flight: OS / RAM / disk / `/opt` mount / network
4. Установка docker-ce + compose plugin
5. SELinux + firewalld
6. `git clone` приватного репозитория в `/opt/netops-platform`
7. Генерация `.env` (random JWT/Fernet/DB password)
8. Применение миграций БД
9. Systemd unit + автостарт
10. Healthcheck loop (до 5 мин)
11. Печать success banner с URL

**Время**: 5-7 минут на свежем OEL 9.

---

## 🔄 Обновление

```bash
sudo /opt/netops-platform/install/update-oel.sh
```

Update **тоже запрашивает GitHub credentials** — уточняйте у владельца продукта (если PAT ротировали — новый).

---

## ⏪ Rollback

Подробно: после установки см. `/opt/netops-platform/docs/release/ROLLBACK.md` (4 сценария + flowchart).

Краткие команды:

| Сценарий | Команда |
|---|---|
| Откат к предыдущему тегу | `cd /opt/netops-platform && git fetch --tags && git checkout vPREV && docker compose down && docker compose up -d` |
| Restore DB из daily backup | `docker compose exec -T db pg_restore -U netops -d netops < /var/backups/netops-platform/<date>.dump` |
| Полная переустановка | `sudo /opt/netops-platform/install/uninstall-oel.sh --purge` → потом повторный `sudo bash /tmp/install.sh` |

---

## 🗑 Деинсталляция

```bash
sudo /opt/netops-platform/install/uninstall-oel.sh           # сохранит data volumes
sudo /opt/netops-platform/install/uninstall-oel.sh --purge   # удалит docker volumes + /opt/netops-platform
```

---

## 🩹 Что внутри bootstrap'a (для security review)

| Шаг | Что делает | Где живут credentials |
|---|---|---|
| 1 | TTY check + интерактивный prompt | Только в shell process memory |
| 2 | `curl GET https://api.github.com/repos/...` с `Authorization: token` | HTTP header, не сохраняется |
| 3 | Скачивает `install-oel.sh` в `/tmp/install-oel-real.XXXX.sh` | File создаётся → `shred -u` через trap EXIT |
| 4 | `bash install-oel-real.sh` с `GITHUB_TOKEN=...` в env | Env переменная, видна `ps`, без disk persist |
| 5 | `git clone https://oauth2:TOKEN@github.com/...` | Token временно в URL |
| 6 | `git remote set-url origin https://github.com/...` (без token) | `.git/config` чистый |
| 7 | `trap cleanup EXIT INT TERM` стирает $GH_TOKEN из памяти | Memory shred |

**Проверка** после установки:
```bash
cat /opt/netops-platform/.git/config | grep url       # должен показать URL БЕЗ токена
find / -name '.credentials' 2>/dev/null               # пусто
```

---

## 🛠 Troubleshooting

| Симптом | Причина | Решение |
|---|---|---|
| `[FAIL] no TTY for interactive prompt` | Запустили через `curl ... \| sudo bash` | Сначала скачай в файл, потом запусти: `curl ... -o /tmp/install.sh && sudo bash /tmp/install.sh` |
| `[FAIL] GitHub returned HTTP 404` | Токен валидный, но нет доступа к репозиторию | Уточни у владельца: правильно ли scoped токен? |
| `[FAIL] GitHub returned HTTP 401` | Токен невалиден / истёк | Запроси новый PAT у владельца продукта |
| `[FAIL] cannot reach download.docker.com` | Outbound firewall блокирует docker hub | Открой outbound 443 + HTTP_PROXY если за корпоративной сетью |
| `[FAIL] RAM ... < 4 GiB minimum` | Слабая VM | Увеличь до 8 GiB минимум (рекомендуется 16) |
| Установка зависает на step 9 healthcheck | Контейнеры не стартуют | `docker compose -f /opt/netops-platform/deploy/docker-compose.yml logs --tail 100` |

---

## 📋 Compatibility

| Layer | Поддерживается |
|---|---|
| OS | Oracle Linux 8.x / 9.x · RHEL 8/9 · Rocky 8/9 · AlmaLinux 8/9 |
| Docker | docker-ce 24+ · compose-plugin 2.20+ |
| FortiOS | 7.2.12 (full) · 7.0+ (basic) |
| RouterOS | 7.x (full) |
| Dahua firmware | 2.800+ / 3.216+ (full) |
| Hikvision | basic via ISAPI |

---

## 📞 Поддержка

- **Владелец продукта**: Ulugbek Sulaymanov · GitHub [@sulaymanovulugbek](https://github.com/sulaymanovulugbek)
- **Issues** (требует доступ к private репе): <https://github.com/sulaymanovulugbek/netops-platform/issues>
- **Handbook** (после установки): открой `http://<server>:13000/handbook` в браузере — 39 глав на русском
- **Customer deployment guide**: см. `/opt/netops-platform/docs/release/CUSTOMER-DEPLOYMENT.md` (10 секций RU)

---

## 📄 License

Apache 2.0 — см. LICENSE в основной репе.
