# Podkop — патч «Интерфейс секции»

Добавляет в LuCI Podkop новое поле **«Интерфейс секции»** прямо в форму секции.  
При выборе интерфейса его подсеть автоматически добавляется в **Полностью маршрутизированные IP-адреса** — весь трафик с этой подсети идёт через данную секцию.

**Поддерживается:** Podkop v0.7.17+, OpenWrt 23.x / 24.x

---

## Что делает патч

Без патча единственный способ направить весь трафик конкретной подсети через секцию — вручную вписывать IP/подсеть в поле «Полностью маршрутизированные IP-адреса».  
Проблема: IP роутера или VLAN может меняться. Патч автоматизирует это.

**После патча:**
- В каждой секции (тип Proxy или VPN) появляется выпадающий список **«Интерфейс секции»**
- Доступные значения: `br-lan`, `vlan2`, `vlan3` (или ввести своё)
- При старте/рестарте Podkop читает UCI опцию `section_interface`, получает подсеть через `ip addr show <iface>`, и добавляет её в маршрутизацию

**Пример лога после настройки:**
```
podkop: [info] section MPROXY: adding subnet 192.168.2.0/24 from interface vlan2 to fully routed
```

---

## Бэкап (обязательно перед установкой)

Скрипт `install.sh` делает бэкап автоматически в `/etc/podkop-patch-backup/`.  
Если хочешь сделать бэкап вручную перед запуском:

```sh
# Подключиться к роутеру по SSH
ssh root@192.168.1.1

# Создать папку для бэкапов
mkdir -p /etc/podkop-patch-backup

# Сохранить оригиналы
cp /usr/bin/podkop /etc/podkop-patch-backup/podkop.orig
cp /www/luci-static/resources/view/podkop/section.js /etc/podkop-patch-backup/section.js.orig

# Проверить что бэкапы на месте
ls -la /etc/podkop-patch-backup/
```

### Восстановление из бэкапа (если что-то пошло не так)

```sh
cp /etc/podkop-patch-backup/podkop.orig     /usr/bin/podkop
cp /etc/podkop-patch-backup/section.js.orig /www/luci-static/resources/view/podkop/section.js
chmod +x /usr/bin/podkop
/etc/init.d/podkop restart
```

---

## Установка

### Способ 1 — автоматический (рекомендуется)

Подключиться по SSH к роутеру и выполнить:

```sh
cd /tmp
wget -q https://raw.githubusercontent.com/AxelNerv/podkop-section-interface/main/install.sh
sh install.sh
```

Скрипт сам:
1. Проверит что Podkop установлен
2. Создаст бэкапы оригинальных файлов
3. Скачает и применит патч
4. Проверит синтаксис bash-скрипта перед заменой

После установки — в браузере нажать **Ctrl+Shift+R** для сброса кэша LuCI.

---

### Способ 2 — вручную (если нет интернета на роутере)

```sh
# 1. Скачай section.js из этого репозитория на компьютер

# 2. Скопируй на роутер (например через SCP или WinSCP)
scp section.js root@192.168.1.1:/www/luci-static/resources/view/podkop/section.js

# 3. Для патча podkop — скопируй install.sh на роутер и запусти
scp install.sh root@192.168.1.1:/tmp/install.sh
ssh root@192.168.1.1 "sh /tmp/install.sh"
```

---

## Как пользоваться

1. Открыть LuCI: `http://192.168.1.1` → **Службы → Podkop**
2. Вкладка **Секции**
3. Выбрать нужную секцию (например, MPROXY)
4. Найти поле **«Интерфейс секции»**
5. Выбрать интерфейс из списка или ввести своё название:
   - `br-lan` — основная LAN подсеть (например 192.168.1.0/24)
   - `vlan2` — VLAN 2 (например гостевая сеть)
   - `vlan3` — VLAN 3
   - Любое другое имя интерфейса (br-guest, eth0.2 и т.д.)
6. Нажать **Сохранить и применить**
7. Перезапустить Podkop: **Службы → Podkop → кнопка Restart** (или через SSH: `/etc/init.d/podkop restart`)

> **Поле видно только** для секций с типом подключения **Proxy** или **VPN**.  
> Для Block и Exclusion оно скрыто.

---

## Удаление патча

```sh
ssh root@192.168.1.1
cd /tmp
wget -q https://raw.githubusercontent.com/AxelNerv/podkop-section-interface/main/uninstall.sh
sh uninstall.sh
```

После удаления: **Ctrl+Shift+R** в браузере, рестарт Podkop.

---

## Файлы в репозитории

| Файл | Описание |
|------|----------|
| `install.sh` | Скрипт установки (делает бэкап + применяет патч) |
| `uninstall.sh` | Скрипт удаления (восстанавливает оригиналы) |
| `section.js` | Патченный LuCI-файл формы секции |
| `section.diff` | Diff для ревью изменений в section.js |

---

## Изменённые файлы

| Файл на роутере | Что изменено |
|----------------|--------------|
| `/www/luci-static/resources/view/podkop/section.js` | Добавлено поле `section_interface` (form.Value) с depends на proxy/vpn |
| `/usr/bin/podkop` | Функция `include_source_ips_in_routing_handler()` расширена: читает UCI `section_interface`, получает подсеть через `ip addr show`, добавляет в маршрутизацию |

---

## Совместимость

| Версия Podkop | Статус |
|--------------|--------|
| v0.7.17 | ✅ Протестировано |
| v0.7.19 | ✅ Протестировано |
| v0.7.x (другие) | ⚠️ Должно работать, не тестировалось |

Если Podkop обновится и функция `include_source_ips_in_routing_handler` изменится — запусти `uninstall.sh`, обнови Podkop, затем снова `install.sh`.
