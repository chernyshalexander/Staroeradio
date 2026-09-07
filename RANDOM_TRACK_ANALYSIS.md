# Анализ функции "Случайный трек" в Android-приложении Старое Радио

## Резюме

Функция "Случайный трек" (последний пункт вкладки "Наследие") найдена и полностью
проанализирована. Алгоритм: приложение кэширует треки из системных плейлистов в
локальную базу и выбирает случайный track_id, после чего запускает воспроизведение
через тот же механизм, что и обычные треки.

**Проверено живыми запросами:** API `getTracks` работает, каталог Старого радио
содержит **35053 трека**. Предложена улучшенная стратегия для плагина — случайный
offset вместо кэширования 99 треков (подтверждена 5 тестовыми запросами).

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

**Итого: ~297 треков** (99 × 3 плейлиста) — случайный выбор идёт только из них,
а не из всего каталога!

---

## 3. Воспроизведение

**Файл:** `CollectionPlaybackManager.java`

Для playlist-треков (`getTrackStreamURL`, строка 288): API
`GET getradioinfo.php?cmd=getTrackStreamURL&track_id=X` возвращает список потоков
с битрейтами; выбирается нужный битрейт, к URL добавляется `&fix=1.mp3`.

⚠️ **Проверено живым тестом:** `getTrackStreamURL` сейчас возвращает **пустой
ответ** (как и `getMetaInfo` — эти тонкие API-эндпойнты на сервере не работают).

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

`next()` → `playNextPlaylistTrack()` — берёт **следующий по порядку** трек из
общего списка `DBPlaylistTrackModel` (не случайный!).

**Вывод:** в Android "случайность" — это **одноразовая случайная точка входа**;
дальше треки идут подряд по списку. Полной цепочки случайных треков в приложении
НЕТ (несмотря на ожидание "запускает снова и снова").

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

totalCount можно кэшировать (обновлять раз в сутки) — тогда случайный трек =
**один** быстрый запрос.

### Реализация в плагине (OPML)

**Вариант A (рекомендуемый) — "Слушать случайные" как плейлист из N треков:**
1. Новый пункт меню "Случайный трек" в `_feedHandler()`.
2. Обработчик делает M запросов `getTracks&offset={random}&limit=1`
   (например N=20) и строит OPML-список.
3. LMS сам переходит к следующему треку после окончания — бесконечное
   прослушивание достигается списком на несколько часов.
4. Повторный вход в пункт = новый случайный список.

**Вариант B — динамическая подстановка через ProtocolHandler:**
- Регистрировать `staroe://random` URL и в `getNextTrack()`/override
  генерировать новый случайный трек на каждый переход.
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
