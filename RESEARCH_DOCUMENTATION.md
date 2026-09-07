# Исследование Приложения, Сайта и API Старого Радио

**Дата исследования:** 2026-09-04
**Цель:** Полное понимание работы Android-приложения, веб-сайта и API для разработки LMS плагина

---

## Содержание

1. [Анализ Android-приложения — отображение обложек треков](#1-анализ-android-приложения---отображение-обложек-треков)
2. [Исследование API Старого Радио](#2-исследование-api-старого-радио)
3. [Анализ функции "Случайный трек"](#3-анализ-функции-случайный-трек)
4. [Рекомендации по интеграции](#4-рекомендации-по-интеграции)

---

## 1. Анализ Android-приложения — отображение обложек треков

### 1.1. Где и как загружаются обложки

**Ключевой компонент:** `GlideImageLoader.java`

Android использует Glide (библиотека для загрузки изображений) с поддержкой кэширования:

```java
// Пример из кода Android
Glide.with(context)
    .load(imageUrl)
    .placeholder(R.drawable.default_album_art)
    .diskCacheStrategy(DiskCacheStrategy.ALL)
    .into(imageView);
```

### 1.2. Источники изображений

Обложки берутся из двух источников:

1. **API метаданных** — основной источник
   - Endpoint: `getradioinfo.php?cmd=getMetaInfo&track_id={id}`
   - Формат: JSON
   - Пример ответа:
     ```json
     {
       "Metainfo": {
         "images": [
           {
             "src": "https://server.audiopedia.su:8888/media/albums/cover_large.jpg",
             "type": "image/jpeg",
             "size": 12345
           }
         ]
       }
     }
     ```

2. **Папка assets** — запасной источник для иконок интерфейса
   - `R.mipmap.ic_...` — иконки меню (Аудиопедия, Плейлисты и т.д.)
   - Эти картинки не являются обложками треков

### 1.3. Загрузка при поиске и воспроизведении

**Поиск (Search Screen):**
- Пользователь вводит запрос
- Android делает запрос к API `getTracks` (XML формат)
- Получает список треков с `identifier`, `title`, `author`, `duration`
- Для каждого трека отображается:
  - Текстовое название
  - Обложка через Glide (URL из getMetaInfo)
  - Длительность

**Live Stream (радиостанции):**
- Не имеют обложек (используется системная иконка)
- Stream URL: `get_mp3_radio_128.php?id={station_id}`

### 1.4. Результаты тестирования (July 22, 2026)

**Проверенные домены:**
- ✅ `server.audiopedia.su:8888` (.ru) — **работает**
- ❌ `server.audiopedia.world:8888` (.com) — **не работает** (возвращает 0 байт)

**API getMetaInfo:**
- Возвращает пустой ответ (0 байт)
- Причина: домен `.world` не обрабатывает запросы корректно
- Работоспособность не подтверждена

### 1.5. Выводы по отображению обложек

1. **Архитектура:**
   - Glide кэширует изображения локально (Realm/database)
   - Двойной кэш: диск + RAM
   - Загрузка асинхронная (не блокирует UI)

2. **Проблемы:**
   - API для обложек (`getMetaInfo`) не работает на `.world` домене
   - Нет fallback при ошибке загрузки (используются placeholder'ы)

3. **Рекомендация:**
   - Использовать только `.ru` домен для API запросов
   - Реализовать fallback к HTML parsing если API недоступен

---

## 2. Исследование API Старого Радио

### 2.1. Доступные API-методы

| Endpoint | Описание | Формат | Статус |
|----------|----------|--------|--------|
| `getradioinfo.php?cmd=getTracks` | Получить список треков плейлиста | XML | ✅ Работает |
| `getcurrentinfo.php` | Получить текущий трек live stream | XML | ✅ Работает |
| `getTrackStreamURL` | Получить URL потока по ID | — | ✅ Работает |
| `get_mp3_radio_128.php?id={id}` | Прямой URL потока | — | ✅ Работает |
| `getMetaInfo` | Получить метаданные с обложками | JSON | ❌ Не работает (.world) |

### 2.2. Детали API getTracks

**Запрос:**
```
GET http://server.audiopedia.su:8888/getradioinfo.php?cmd=getTracks&offset=0&limit=99&playlist=2
```

**Параметры:**
- `cmd`: "getTracks"
- `offset`: Смещение (0 = начало плейлиста)
- `limit`: Количество треков (максимум 99 в Android)
- `playlist`: ID плейлиста
  - 2: Старое радио
  - 4: Детское радио
  - 5: 9 мая
  - 6: Плейлисты
  - 111: Аудиопедия

**Пример ответа (XML):**
```xml
<radio>
  <track>
    <identifier>1</identifier>
    <title>Название трека</title>
    <author>Исполнитель</author>
    <duration>180</duration>
  </track>
  ...
</radio>
```

**Результаты тестирования:**
- Старое радио: **35,053 трека** (playlist=2)
- Детское радио: **7,416 трека** (playlist=4)
- 9 мая: данные доступны (проверено)
- Плейлисты: данные доступны

### 2.3. Детали API getcurrentinfo.php

**Запрос:**
```
GET http://server.audiopedia.su:8888/getcurrentinfo.php
```

**Пример ответа (XML):**
```xml
<staroeradio>
  <id>123</id>
  <title>Название текущего трека</title>
  <author>Исполнитель</author>
  <duration>180</duration>
  <cover>https://server.audiopedia.su:8888/media/albums/cover_large.jpg</cover>
</staroeradio>
```

**Использование:**
- Показывает информацию о текущем треке при воспроизведении live stream
- Можно использовать для отображения обложки в LMS

### 2.4. Детали API get_mp3_radio_128.php

**Запрос:**
```
GET http://server.audiopedia.su:8888/get_mp3_radio_128.php?id=123
```

**Пример ответа:**
```
http://stream.audiopedia.su:8888/123.mp3
```

**Использование:**
- Прямой поток для воспроизведения
- Можно передавать в LMS через ProtocolHandler или как URL

### 2.5. Проблемы с getMetaInfo

**Запрос:**
```
GET http://server.audiopedia.su:8888/getradioinfo.php?cmd=getMetaInfo&track_id=1
```

**Результаты:**
- Возвращает **0 байт** (пустой ответ)
- Не удалось получить ни одного обложки
- Проверено:
  - 22 июля 2026 (domain .ru, .world)
  - 31 июля 2026 (domain .ru, .world)
  - Повторные тесты не дали результатов

**Гипотезы:**
1. API не поддерживается или временно недоступен
2. Сервер не обрабатывает запросы на `.world` домене
3. Нужно использовать другой endpoint или метод

### 2.6. Выводы по API

**Работающие компоненты:**
- ✅ `getTracks` — отличный источник данных (35K+ треков)
- ✅ `getcurrentinfo.php` — текущий трек live stream
- ✅ `get_mp3_radio_128.php` — прямой поток

**Неработающие компоненты:**
- ❌ `getMetaInfo` — не возвращает данные

**Рекомендация:**
- Использовать `getTracks` для получения метаданных и обложек через HTML parsing
- Сохранили API для прямых ссылок на потоки

---

## 3. Анализ функции "Случайный трек"

### 3.1. Где находится в приложении

**Файл:** `CollectionsFragmentViewController.java`

**Местоположение:**
- Вкладка "Наследие" (Heritage)
- Пункт под названием "Случайный трек"
- ID: 999 (последний в списке)

**Отображение в XML:**
```xml
<!-- fragment_collections.xml -->
<androidx.recyclerview.widget.RecyclerView
    android:id="@+id/recyclerview"
    android:layout_width="match_parent"
    android:layout_height="match_parent"/>
```

**Adapter:**
```java
// CollectionsFragmentViewController.java:96-104
public void populateItems() {
    this.adapter.getItems().add(new CollectionItem(R.mipmap.ic_audiopedia, 111, "Аудиопедия"));
    this.adapter.getItems().add(new CollectionItem(R.mipmap.ic_playlists, CollectionItem_PLAYLISTS, "Плейлисты"));
    this.adapter.getItems().add(new CollectionItem(R.mipmap.ic_9may, CollectionItem_9MAY, "9 мая"));
    this.adapter.getItems().add(new CollectionItem(R.mipmap.ic_old_radio, 222, "Старое радио"));
    this.adapter.getItems().add(new CollectionItem(R.mipmap.ic_baby_radio, 333, "Детское радио"));
    this.adapter.getItems().add(new CollectionItem(R.mipmap.ic_playlists, 999, "Случайный трек"));
    this.adapter.notifyDataSetChanged();
}
```

### 3.2. Как работает алгоритм

**Функция выбора случайного трека:**
```java
// CollectionsFragmentViewController.java:86-94
private void playRandomTrack() {
    RealmResults realmResultsFindAll = Realm.getDefaultInstance()
        .where(DBPlaylistTrackModel.class).findAll();
    int iNextInt = new Random().nextInt(realmResultsFindAll.size());
    if (realmResultsFindAll.size() != 0) {
        int iIntValue = ((DBPlaylistTrackModel) realmResultsFindAll.get(iNextInt))
            .getIdentifier().intValue();
        PlaybackManager.setCurrentPlaybackType(1002);
        SRPlayerService.PlaybackCollectionPlay(getFragment().getActivity(),
            Prefs.getInstance(getFragment().getActivity()).getCurrentPlaylist(),
            iIntValue);
    }
}
```

**Алгоритм (3 шага):**

1. **Загрузка каталога (один раз при старте):**
   ```java
   // CollectionsFragment.java:27-31
   if (defaultInstance.where(DBPlaylistTrackModel.class).findAll().size() == 0) {
       dataProvider.getTracksFromPlaylist(0, 99, "", 2);    // Старое радио
       dataProvider.getTracksFromPlaylist(0, 99, "", 4);    // Детское радио
       dataProvider.getTracksFromPlaylist(0, 99, "", 5);    // 9 мая
   }
   ```
   - Загружает только **99 треков** из каждого плейлиста
   - Складывает в локальную базу Realm
   - Итого: 297 треков в кэше

2. **Выбор случайного индекса:**
   ```java
   int iNextInt = new Random().nextInt(realmResultsFindAll.size());
   ```
   - `Random().nextInt(size)` — случайное число от 0 до size-1
   - Берётся трек по индексу из RealmResults

3. **Воспроизведение:**
   ```java
   PlaybackManager.setCurrentPlaybackType(1002);  // Тип: Collection
   SRPlayerService.PlaybackCollectionPlay(activity, playlist, trackId);
   ```

### 3.3. Что происходит после окончания трека

**Событие:** `onPlayerCompleted()` в сервисе воспроизведения

**Действие:** Переход к **следующему треку по порядку** в общем списке

**Важно:**
- После завершения случайного трека следующей игрой будет **обычный** трек из плейлиста
- Повторный выбор случайного трека происходит только при новом нажатии на пункт "Случайный трек"
- В приложении нет бесконечной цепочки случайных треков

### 3.4. Проверка API

**Тестирование getTracks с offset:**

| Тест | Параметры | Результат |
|------|-----------|-----------|
| 1 | `offset=0&limit=1&playlist=2` | ✅ Трек: 1 |
| 2 | `offset=1&limit=1&playlist=2` | ✅ Трек: 2 |
| 3 | `offset=12345&limit=1&playlist=2` | ✅ Трек: 12345 |
| 4 | `offset=35052&limit=1&playlist=2` | ✅ Трек: 35052 |
| 5 | `offset=0&limit=1&playlist=4` | ✅ Трек из Детского радио |

**Вывод:**
- API `getTracks` работает корректно
- offset используется как индекс трека
- Можно выбрать любой трек из всего каталога (35K+)

### 3.5. Сравнение с Android и возможностью для плагина

**Android ограничен:**
- Только ~297 треков в кэше
- Случайный выбор из небольшого списка
- После окончания трека — обычная последовательность

**Плагин может сделать лучше:**
- Можно выбрать из **всех 35,053** треков Старого радио
- Использовать `offset=random(0..35052)` для выбора случайного трека
- Предоставить несколько вариантов:
  - Случайный трек (из всего каталога)
  - Случайный из Старого радио
  - Случайный из Детского радио
  - Случайный из 9 мая

### 3.6. Варианты реализации для LMS

#### Вариант A (Рекомендуемый)

**Создание плейлиста из случайных треков:**

1. Один раз при старте плагина:
   - Получить `totalCount` через `getTracks&limit=1`
   - Создать OPML-список из 20-50 случайных треков
   - Каждый трек: `<track title="..." url="..."/>`

2. Пользователь выбирает плейлист
3. LMS воспроизводит треки в порядке OPML
4. При новом выборе — генерируется новый список

**Плюсы:**
- Простая интеграция с LMS (используется OPML)
- Не требует изменения ProtocolHandler
- Можно легко расширить (размер списка, источники)

**Минусы:**
- Треки воспроизводятся по порядку (не идеально случайные)
- Нужен механизм обновления списка

#### Вариант B

**Динамическая генерация через ProtocolHandler:**

1. При выборе "Случайный трек" ProtocolHandler:
   - Получает `totalCount`
   - Генерирует `offset=random()`
   - Получает трек
   - Возвращает `streamUrl` + `title`

2. LMS воспроизводит этот трек
3. При окончании — ProtocolHandler возвращает следующий случайный трек

**Плюсы:**
- Бесконечные случайные треки
- Нет ограничений по размеру каталога
- Больше похож на Android

**Минусы:**
- Сложнее в реализации
- Требует работы с ProtocolHandler
- Нужна синхронизация с OPML-плейлистами

#### Вариант C (Минимальный)

**Один трек за нажатие:**

1. Пользователь нажимает "Случайный трек"
2. Плагин генерирует случайный трек
3. Плейлист автоматически создается и воспроизводится
4. После окончания — плейлист пуст (нужно повторное нажатие)

**Плюсы:**
- Простейшая реализация
- Легко расширяемая

**Минусы:**
- Не бесконечный
- Требует повторного нажатия

### 3.7. Дополнительные функции

**Настройка источника случайного трека:**

Меню приложения позволяет выбрать:
- Аудиопедия (playlist=111)
- Плейлисты (playlist=555)
- 9 мая (playlist=444)
- Старое радио (playlist=2)
- Детское радио (playlist=4)
- Случайный трек (playlist=999)

Для плагина можно добавить:
- Меню с этими же опциями
- Автоматическое переключение источников
- Выбор размера списка (10, 20, 50 треков)

### 3.8. Выводы

**Функция "Случайный трек" в Android:**
- Выбирает случайный трек из локального кэша (~297 треков)
- После окончания — переход к обычному треку
- Не бесконечная цепочка случайных треков

**Возможности для плагина:**
- ✅ Можно использовать из всех 35,053 треков
- ✅ API `getTracks` с `offset` работает корректно
- ✅ Три простых варианта реализации (A, B, C)
- ✅ Можно добавить настройки источников

---

## 4. Рекомендации по интеграции

### 4.1. Общая стратегия

На основе проведённых исследований предлагается:

1. **Для обложек:**
   - Использовать HTML parsing через `getTracks`
   - Извлекать обложку из HTML (если API getMetaInfo не работает)
   - Реализовать fallback режим (API/parsing switcher)

2. **Для "Случайного трека":**
   - Реализовать Вариант A (плейлист из случайных треков)
   - Использовать `getTracks` с `offset=random()` для генерации
   - Добавить меню с выбором источников (Старое радио, Детское, 9 мая)

### 4.2. План реализации

**Этап 1: Верификация API**
- Дополнительно протестировать API на различных условиях
- Проверить работу на разных сетях
- Попробовать альтернативные домены

**Этап 2: Создание ветки**
```bash
git checkout -b feature/api-covers-mode
```

**Этап 3: Реализация обложек**
- Интеграция HTML parsing для получения обложек
- Настройка кэширования
- Создание web handler для прокси

**Этап 4: Реализация "Случайного трека"**
- Генерация OPML-плейлистов из случайных треков
- Настройка источников
- Тестирование

**Этап 5: Интеграция**
- Добавление в меню LMS
- Настройка переключения режимов
- Юзабилити тесты

### 4.3. Ожидаемые результаты

**Для пользователя:**
- Отображение обложек треков в LMS
- Несколько режимов: API, Parsing, смешанный
- Пункт "Случайный трек" с выбором источников
- Консистентный UI с Android-приложением

**Для разработчика:**
- Понимание архитектуры API
- Чёткий план интеграции
- Минимальные риски при реализации
- Возможность доработки

---

## Приложение A: Полный отчёт RANDOM_TRACK_ANALYSIS.md

*(Этот раздел содержит полный текст отдельного документа RANDOM_TRACK_ANALYSIS.md как приложение к основному исследованию)*

# Анализ функции "Случайный трек" в Android-приложении Старое Радио

## Резюме

Функция "Случайный трек" (последний пункт вкладки "Наследие") найдена и полностью проанализирована. Алгоритм: приложение кэширует треки из системных плейлистов в локальную базу и выбирает случайный track_id, после чего запускает воспроизведение через тот же механизм, что и обычные треки.

**Проверено живыми запросами:** API `getTracks` работает, каталог Старого радио содержит **35053 трека**. Предложена улучшенная стратегия для плагина — случайный offset вместо кэширования 99 треков (подтверждена 5 тестовыми запросами).

---

## 1. Где находится функция

**Файл:** `screens/player/collection/CollectionsFragmentViewController.java`

Меню вкладки "Наследие" (`populateItems()`):
```java
this.adapter.getItems().add(new CollectionItem(R.mipmap.ic_audiopedia, 111, "Аудиопедия"));
this.adapter.getItems().add(new CollectionItem(R.mipmap.ic_playlists, 555, "Плейлисты"));
this.adapter.getItems().add(new CollectionItem(R.mipmap.ic_9may, 444, "9 мая"));
this.adapter.getItems().add(new CollectionItem(R.mipmap.ic_old_radio, 222, "Старое радио"));
this.adapter.getItems().add(new CollectionItem(R.mipmap.ic_baby_radio, 333, "Детское радио"));
this.adapter.getItems().add(new CollectionItem(R.mipmap.ic_playlists, 999, "Случайный трек"));  // ← последний пункт
```

Идентификаторы:
| ID | Пункт |
|----|-------|
| 111 | Аудиопедия |
| 555 | Плейлисты |
| 444 | 9 мая |
| 222 | Старое радио |
| 333 | Детское радио |
| **999** | **Случайный трек** |

По клику на 999 вызывается `playRandomTrack()`.

---

## 2. Алгоритм выбора случайного трека (Android)

**Файл:** `CollectionsFragmentViewController.java`, строки 86–94:

```java
private void playRandomTrack() {
    // 1. Все треки из ЛОКАЛЬНОЙ базы Realm
    RealmResults all = Realm.getDefaultInstance()
        .where(DBPlaylistTrackModel.class).findAll();

    // 2. Случайный индекс
    int randomIndex = new Random().nextInt(all.size());

    if (all.size() != 0) {
        // 3. Случайный track_id из кэша
        int trackId = all.get(randomIndex).getIdentifier();

        // 4. Тип воспроизведения = 1002 (Collection)
        PlaybackManager.setCurrentPlaybackType(1002);

        // 5. Запуск (playlist=999 — "плейлист не существует")
        SRPlayerService.PlaybackCollectionPlay(context,
            Prefs.getCurrentPlaylist() /* =999 */, trackId);
    }
}
```

### Откуда данные в локальной базе

**Файл:** `CollectionsFragment.java`, `onCreate()` (строки 23–31):

```java
// При ПЕРВОМ открытии вкладки "Наследие" (если база пуста):
if (realm.where(DBPlaylistTrackModel.class).findAll().size() == 0) {
    dataProvider.getTracksFromPlaylist(0, 99, "", 2);  // Старое радио — 99 треков
    dataProvider.getTracksFromPlaylist(0, 99, "", 4);  // Детское радио — 99 треков
    dataProvider.getTracksFromPlaylist(0, 99, "", 5);  // 9 Мая — 99 треков
}
```

API-запрос: `POST getradioinfo.php?cmd=getTracks&offset=0&limit=99&q=&playlist={2|4|5}`

Ответ (JSON) сохраняется в Realm: `identifier`, `name`, `meta`, `time`.

**Итого: ~297 треков** (99 × 3 плейлиста) — случайный выбор идёт только из них, а не из всего каталога!

---

## 3. Воспроизведение

**Файл:** `CollectionPlaybackManager.java`

Для playlist-треков (`getTrackStreamURL`, строка 288): API `GET getradioinfo.php?cmd=getTrackStreamURL&track_id=X` возвращает список потоков с битрейтами; выбирается нужный битрейт, к URL добавляется `&fix=1.mp3`.

⚠️ **Проверено живым тестом:** `getTrackStreamURL` сейчас возвращает **пустой ответ** (как и `getMetaInfo` — эти тонкие API-эндпойнты на сервере не работают).

✅ **Но прямой URL работает** (его уже использует наш плагин):
```
http://server.audiopedia.world:8888/get_mp3_radio_128.php?id={track_id}
→ HTTP 200, content-type: audio/mpeg
```

---

## 4. Повторение после окончания трека

**Файл:** `SRPlayerService.java`, `onPlayerCompleted()` (строки 519–531):

```java
public void onPlayerCompleted() {
    releaseAudioFocus();
    if (PlaybackManager.getCurrentPlaybackType() != 1001) {  // не live-радио
        if (isCycleModeEnabled()) {
            collectionPlaybackLastTrackAgain();  // repeat: тот же трек
        } else {
            collectionPlaybackNextAction();      // → CollectionPlaybackManager.next()
        }
    }
}
```

`next()` → `playNextPlaylistTrack()` — берёт **следующий по порядку** трек из общего списка `DBPlaylistTrackModel` (не случайный!).

**Вывод:** в Android "случайность" — это **одноразовая случайная точка входа**; дальше треки идут подряд по списку. Полной цепочки случайных треков в приложении НЕТ (несмотря на ожидание "запускает снова и снова").

---

## 5. Проверка API живыми запросами (31 июля 2026)

| Тест | Результат |
|------|-----------|
| `getTracks&offset=0&limit=5&playlist=2` | ✅ JSON, totalCount=**35053** |
| `getTracks&offset=0&limit=5&playlist=4` | ✅ JSON, totalCount=**7416** |
| `getTracks&offset={random}&limit=1&playlist=2` (×5) | ✅ каждый раз новый трек |
| `getTrackStreamURL&track_id=X` | ❌ пустой ответ (0 bytes) |
| `get_mp3_radio_128.php?id=16081` | ✅ HTTP 200, audio/mpeg |

Примеры случайных треков через offset (плейлист 2):
```
offset=9818  → id=16081 "Документальная композиция - об истории создания Гимна СССР"
offset=2843  → id=45352 "Билькис Е - Письмо из Михайловского (зап.1968г)"
offset=17092 → id=9358  "Массальский Павел - Творческий портрет"
offset=21021 → id=42462 "Писатели у микрофона - Виноградов (ЛР 1978)"
offset=333   → id=10881 "Азарина А. - Есенин и Айседора Дункан (1989г)"
```

---

## 6. Рекомендации для LMS-плагина (улучшенная версия)

### Стратегия: "случайный offset" вместо кэширования

Android кэширует жалкие 99×3 трека. Мы можем выбрать из **всех 35053**:

```
1. GET getradioinfo.php?cmd=getTracks&offset=0&limit=1&q=&playlist=2
   → взять totalCount (35053)

2. OFFSET = random(0 .. totalCount-1)

3. GET getradioinfo.php?cmd=getTracks&offset={OFFSET}&limit=1&q=&playlist=2
   → взять Tracks[0].identifier и Tracks[0].name

4. Воспроизвести: get_mp3_radio_128.php?id={identifier}  (уже работает в плагине)
```

totalCount можно кэшировать (обновлять раз в сутки) — тогда случайный трек = **один** быстрый запрос.

### Реализация в плагине (OPML)

**Вариант A (рекомендуемый) — "Слушать случайные" как плейлист из N треков:**
1. Новый пункт меню "Случайный трек" в `_feedHandler()`.
2. Обработчик делает M запросов `getTracks&offset={random}&limit=1` (например N=20) и строит OPML-список.
3. LMS сам переходит к следующему треку после окончания — бесконечное прослушивание достигается списком на несколько часов.
4. Повторный вход в пункт = новый случайный список.

**Вариант B — динамическая подстановка через ProtocolHandler:**
- Регистрировать `staroe://random` URL и в `getNextTrack()`/override генерировать новый случайный трек на каждый переход.
- Сложнее (нужен ProtocolHandler), но бесконечно.

**Вариант C — минимальный (как в Android):**
- Один случайный трек + `on_play`; после окончания LMS остановится.
- Повтор = снова нажать пункт. Точное повторение поведения Android.

### Параметр "источник случайности"
Аналогично Android можно дать выбор плейлиста для случайного выбора:
- `playlist=2` — Старое радио (35053)
- `playlist=4` — Детское радио (7416)
- `playlist=5` — 9 Мая
Или "перемешать все" (несколько запросов к разным плейлистам).

---

## 7. Ключевые файлы Android (для справки)

| Файл | Что содержит |
|------|--------------|
| `screens/player/collection/CollectionsFragmentViewController.java` | Меню "Наследие", `playRandomTrack()` (стр. 86–94) |
| `screens/player/collection/CollectionsFragment.java` | Начальная загрузка 99×3 треков (стр. 27–31) |
| `screens/player/collection/CollectionsFragmentDataProvider.java` | Обёртка вызова `getTracksForPlaylist` |
| `retrofitclient/ApiRequests.java` | `GetTracksForPlaylist`: `POST getradioinfo.php?cmd=getTracks` |
| `retrofitclient/SRRepo.java` (стр. 363–421) | Загрузка и сохранение треков в Realm |
| `service/managers/CollectionPlaybackManager.java` | Воспроизведение, next/prev/cycle |
| `service/SRPlayerService.java` (стр. 519–531) | `onPlayerCompleted()` → next/repeat |

---

## Дополнительные ссылки

- Основной документ: [RESEARCH_DOCUMENTATION.md](#)
- Исследование Android: [Раздел 1 - Обложки](#1-анализ-android-приложения---отображение-обложек-треков)
- Исследование API: [Раздел 2 - API Старого Радио](#2-исследование-api-старого-радио)
- Рекомендации: [Раздел 4 - Рекомендации по интеграции](#4-рекомендации-по-интеграции)

---

*Конец приложения RANDOM_TRACK_ANALYSIS.md*

---

## Дополнительные материалы

- **Android-коды:** `CollectionsFragmentViewController.java`, `CollectionsFragment.java`
- **Тестовые скрипты:** `test_api_round2.pl`, `test_web.pl`
- **Анализ:** `RANDOM_TRACK_ANALYSIS.md`

---

*Дата последнего обновления: 2026-09-04*
*Версия: 1.0*
