# Clean Revit

PowerShell GUI-утилита для очистки пользовательских данных Autodesk Revit.

Скрипт помогает быстро удалить временные файлы, кэш, журналы, резервные данные и другие накопившиеся файлы Revit через удобный графический интерфейс.

## 🚀 Быстрый запуск

Запустить напрямую из GitHub:

```powershell
irm https://raw.githubusercontent.com/Viend1211/Clean-Revit/main/Clean-Revit-GUI.ps1 | iex
```

или

```powershell
Invoke-RestMethod https://raw.githubusercontent.com/Viend1211/Clean-Revit/main/Clean-Revit-GUI.ps1 | Invoke-Expression
```

## Скачать и запустить

```powershell
$Script = "$env:TEMP\Clean-Revit-GUI.ps1"

Invoke-WebRequest `
    -Uri "https://raw.githubusercontent.com/Viend1211/Clean-Revit/main/Clean-Revit-GUI.ps1" `
    -OutFile $Script

powershell.exe -ExecutionPolicy Bypass -File $Script
```

## Однострочный запуск

```powershell
$F="$env:TEMP\Clean-Revit-GUI.ps1";iwr "https://raw.githubusercontent.com/Viend1211/Clean-Revit/main/Clean-Revit-GUI.ps1" -OutFile $F;powershell -ExecutionPolicy Bypass -File $F
```

## Возможности

* Очистка временных файлов Revit
* Очистка локального кэша
* Удаление журналов (Journals)
* Очистка пользовательских данных
* Удаление ненужных файлов для освобождения места
* Графический интерфейс (GUI)

## Требования

* Windows 10 / 11
* PowerShell 5.1 или выше
* Autodesk Revit (любая поддерживаемая версия)

## Запуск локальной копии

После скачивания репозитория:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Clean-Revit-GUI.ps1
```

## Примечание

Перед очисткой рекомендуется закрыть все запущенные экземпляры Autodesk Revit.

## Автор

Viend1211

## Что умеет

- Находит установленные и оставшиеся версии Revit.
- Позволяет выбрать конкретную версию, например `2022`, `2024`, `2025`.
- Показывает список найденных следов перед удалением.
- Удаляет только следы выбранной версии.
- Показывает процент выполнения.
- Пишет отчет и лог.
- Обновляет Autodesk Licensing Service через локальный `AdskLicensing-installer`.
- Работает через русский графический интерфейс.

## Что чистит

Для выбранной версии Revit утилита ищет и удаляет:

- папки Revit в `Program Files`;
- папки Revit в `ProgramData`;
- пользовательские данные в `AppData`;
- addins/extensions выбранной версии;
- записи удаления в реестре Windows;
- записи Autodesk `ODIS`;
- записи Autodesk `UPI2`;
- кэши установщика Autodesk;
- записи Windows Installer, где найдено `Revit` и выбранный год.

Перед удалением весь список показывается в окне программы.

## Обновление AdskLicensing

Кнопка **Обновить лицензию**:

- ищет рядом с программой файлы `AdskLicensing-installer *.exe`;
- выбирает самый новый установщик;
- останавливает службу Autodesk Licensing;
- удаляет старый Autodesk Licensing;
- устанавливает новый;
- запускает службу обратно;
- пишет результат в отчет.

## Как пользоваться

1. Распакуйте архив.
2. Запустите `RevitCleaner.exe`.
3. Подтвердите запуск от администратора.
4. Выберите версию Revit, например `2024`.
5. Нажмите **Поиск**.
6. Проверьте найденный список.
7. Нажмите **Удалить**.
8. При необходимости нажмите **Обновить лицензию**.
9. Перезагрузите Windows.
10. Установите Revit заново.

Если `RevitCleaner.exe` не запускается, используйте резервный запуск:

```bat
Run-Clean-Revit-GUI.bat
```

## Комплект архива

В архиве должны лежать рядом:

```text
RevitCleaner.exe
Clean-Revit-GUI.ps1
Run-Clean-Revit-GUI.bat
AdskLicensing-installer 13.0.0.8122.exe
AdskLicensing-installer 13.1.0.8534.exe
AdskLicensing-installer 14.0.0.10160.exe
AdskLicensing-installer 14.2.0.10911.exe
README_RU.txt
```

`Clean-Revit-GUI.ps1` должен лежать рядом с `RevitCleaner.exe`, потому что EXE запускает этот скрипт от имени администратора.

## Поддержка версий

Утилита не привязана только к `2022` или `2024`.

Она поддерживает формат версий `20xx`, например:

- Revit 2020
- Revit 2021
- Revit 2022
- Revit 2023
- Revit 2024
- Revit 2025
- Revit 2026

## Важно

- Запускайте утилиту от администратора.
- Закройте Revit и Autodesk Access перед очисткой.
- После очистки перезагрузите Windows.
- Удаление необратимое. Сначала смотрите список в окне программы.
- Утилита не удаляет все продукты Autodesk целиком, только найденные следы выбранной версии Revit.

## Лицензирование Autodesk

Утилита работает только с официальными компонентами Autodesk Licensing.

Сторонние активаторы, обход лицензий и нелегальные способы активации не поддерживаются и не входят в комплект.

Используйте официальный вход Autodesk, named user или сетевую лицензию.

## Для чего это нужно

Иногда установщик Revit видит старые записи:

- в реестре Windows;
- в Windows Installer;
- в Autodesk ODIS;
- в Autodesk UPI2;
- в кэшах установки;
- в пользовательских папках.

Из-за этого повторная установка может завершаться ошибкой, хотя Revit уже удален через стандартный деинсталлятор.

Revit Cleaner помогает убрать такие остатки для выбранной версии.

## Рекомендованный порядок при ошибке установки

1. Удалить Revit стандартным способом, если он виден в Windows.
2. Запустить Revit Cleaner.
3. Выбрать нужную версию.
4. Нажать **Поиск**.
5. Нажать **Удалить**.
6. Нажать **Обновить лицензию**.
7. Перезагрузить Windows.
8. Запустить установщик Revit заново.

## Статус

Проект сделан как практичный инструмент для переустановки Revit на Windows.

Основной сценарий: быстро очистить выбранную версию Revit и подготовить систему к новой установке.

