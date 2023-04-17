# Linux-things

Всякие мелочи для linux.

## [remove-r.sh](remove-r.sh)

Удаляет возврат каретки из файлов. Если аргумент - каталог, то имена файлов в нём проверяются на соответствие масок для исходников и всего похожего на них (с моей точки зрения, конечно).

## [dir-mon.pl](dir-mon.pl)

Мониторит каталоги и отслеживает время неактивности. При его достижении запускает то, что сказано. Самый простой пример запуска:

```bash
$ ./dir-mon.pl -p "$HOME/luks-disk" -e "$HOME/bin/umount-luks-disk.sh" -t 600
# При отсутствии активности в течении 10 минут размонтировать LUKS-диск и удалить
# его из /dev/mapper. Средствами mount, automount, systemd-mount etc такое полноценно 
# не получится, ради чего, собственно, эта утилита и писалась (но может использоваться 
# для чего угодно).
```

Подробности по ключам `-?`, `-h`, `-help`.

## [xfce4-genmon](xfce4-genmon/)

Скрипты для [xfce4-genmon-plugin](https://docs.xfce.org/panel-plugins/xfce4-genmon-plugin/start).

![](demo/genmon.png) 

### [genmon-mem.sh](xfce4-genmon/genmon-mem.sh)

Мониторит память. В тултипе показывает информацию. Если памяти занято больше порога, иконка и прочее зелёное краснеют. При клике по иконке запускает [xfce4-taskmanager](https://docs.xfce.org/apps/xfce4-taskmanager/start) или что прикажут.

![](demo/genmon-mem.png) 

### [genmon-cpu.sh](xfce4-genmon/genmon-cpu.sh)

Мониторит процессоры. В тултипе показывает всякое. Если температура кого-то из них больше порога, иконка и прочее зелёное краснеют. При клике по иконке запускает [xfce4-taskmanager](https://docs.xfce.org/apps/xfce4-taskmanager/start) или что прикажут.

![](demo/genmon-cpu.gif) 

### [genmon-disks.sh](xfce4-genmon/genmon-disks.sh)

Мониторит разделы. В тултипе показывает всего/занято/свободно и температуру носителя. Если температура больше порога, иконка и прочее зелёное краснеют. При клике по иконке запускает `sudo` [gnome-disks](https://wiki.gnome.org/Apps/Disks) или что прикажут:

![](demo/genmon-disks.png) 

### [genmon-imap.pl](xfce4-genmon/genmon-imap.pl)

Мониторит ящики в IMAP. Подробности по ключу `-h` или `--help`.

Все аккаунты в одном конфиге:

![](demo/genmon-imap.png) 

Отдельные конфиги:

![](demo/genmon-imap-all.png) 
