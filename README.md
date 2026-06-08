# Podkop — патч «Интерфейс секции»

Добавляет в LuCI Podkop новое поле **«Интерфейс секции»** прямо в форму каждой секции.  
При выборе интерфейса его подсеть автоматически добавляется в маршрутизацию — весь трафик с этой подсети идёт через данную секцию без ручного ввода IP.

**Поддерживается:** Podkop v0.7.17+, OpenWrt 23.x / 24.x

---

## Что делает патч

Без патча единственный способ направить весь трафик конкретной подсети через секцию — вручную вписывать IP/подсеть в поле «Полностью маршрутизированные IP-адреса». Патч автоматизирует это через выбор имени интерфейса.

**После установки патча:**
- В каждой секции типа **Proxy** или **VPN** появляется поле **«Интерфейс секции»**
- Доступные значения: `br-lan`, `vlan2`, `vlan3` или любое своё
- При старте Podkop читает UCI опцию `section_interface`, определяет подсеть через `ip addr show <iface>`, и добавляет её в маршрутизацию

**Пример лога после настройки:**
```
podkop: [info] section MPROXY: adding subnet 192.168.2.0/24 from interface vlan2 to fully routed
```

**Если поле оставить пустым** — ничего не меняется, секция работает как обычно.

**Какой интерфейс выбрать:**
| Интерфейс | Что это |
|-----------|---------|
| `br-lan` | Основная LAN — весь кабельный трафик (ПК, телевизоры и т.д.) |
| `vlan2` | Отдельный VLAN, например для гостевой сети или второго сегмента |
| `vlan3` | Ещё один VLAN |
| любое имя | Любой интерфейс роутера — можно ввести вручную |

---

## Бэкап

Скрипт `install.sh` делает бэкап автоматически в `/etc/podkop-patch-backup/`.

**Ручной бэкап** (если хочешь подстраховаться перед запуском):

```sh
ssh root@192.168.1.1

mkdir -p /etc/podkop-patch-backup
cp /usr/bin/podkop                                    /etc/podkop-patch-backup/podkop.orig
cp /www/luci-static/resources/view/podkop/section.js  /etc/podkop-patch-backup/section.js.orig

ls -la /etc/podkop-patch-backup/
```

**Восстановление вручную** (если что-то пошло не так):

```sh
cp /etc/podkop-patch-backup/podkop.orig     /usr/bin/podkop
cp /etc/podkop-patch-backup/section.js.orig /www/luci-static/resources/view/podkop/section.js
chmod +x /usr/bin/podkop
/etc/init.d/podkop restart
```

---

## Установка

Подключиться по SSH к роутеру и выполнить одну команду:

```sh
wget -q https://raw.githubusercontent.com/AxelNerv/podkop-section-interface/main/install.sh -O /tmp/install.sh && sh /tmp/install.sh
```

Скрипт автоматически:
1. Проверит что Podkop установлен
2. Создаст бэкапы оригинальных файлов
3. Скачает и применит патч
4. Проверит синтаксис bash перед заменой

После установки нажать **Ctrl+Shift+R** в браузере (сброс кэша LuCI).

---

## Использование

1. Открыть LuCI: `http://192.168.1.1` → **Службы → Podkop**
2. Вкладка **Секции**
3. Выбрать нужную секцию
4. Найти поле **«Интерфейс секции»**
5. Выбрать интерфейс из списка или ввести своё название
6. **Сохранить и применить**
7. Перезапустить Podkop: `/etc/init.d/podkop restart`

> Поле отображается только для секций с типом подключения **Proxy** или **VPN**.

---

## Удаление

```sh
wget -q https://raw.githubusercontent.com/AxelNerv/podkop-section-interface/main/uninstall.sh -O /tmp/uninstall.sh && sh /tmp/uninstall.sh
```

После удаления: **Ctrl+Shift+R** в браузере, рестарт Podkop.

---

## Файлы в репозитории

| Файл | Описание |
|------|----------|
| `install.sh` | Установка: бэкап + применение патча |
| `uninstall.sh` | Удаление: восстановление оригиналов |
| `section.js` | Патченный LuCI-файл формы секции |
| `section.diff` | Diff для ревью изменений в section.js |

---

## Изменённые файлы на роутере

| Файл | Что изменено |
|------|-------------|
| `/www/luci-static/resources/view/podkop/section.js` | Добавлено поле `Интерфейс секции` |
| `/usr/bin/podkop` | Функция `include_source_ips_in_routing_handler()` читает `section_interface` и добавляет подсеть в маршрутизацию |

---

## Совместимость

| Версия Podkop | Статус |
|--------------|--------|
| v0.7.17 | ✅ Протестировано |
| v0.7.19 | ✅ Протестировано |
| v0.7.x другие | ⚠️ Должно работать |

> Если Podkop обновился и перестало работать — запусти `uninstall.sh`, обнови Podkop, затем снова `install.sh`.
