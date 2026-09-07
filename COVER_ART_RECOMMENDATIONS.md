# Рекомендации по добавлению обложек в LMS плагин Staroe

## Краткое резюме исследования Android-приложения

### Эндпойнты и API

1. **Для получения метаданных с обложками**:
   ```
   GET http://server.audiopedia.su:8888/getradioinfo.php?cmd=getMetaInfo&track_id=<track_id>
   ```
   
   **Ответ (JSON)**:
   ```json
   {
     "Metainfo": {
       "images": [
         "http://example.com/image1.jpg",
         "http://example.com/image2.jpg"
       ],
       "text": "Описание трека"
     }
   }
   ```

2. **Для live stream (текущий трек)**:
   ```
   GET http://server.audiopedia.su:8888/getcurrentinfo.php
   ```
   
   **Ответ (XML)**:
   ```xml
   <data>
     <staroeradio>
       <id>12345</id>
       <name>Название трека</name>
       <file>stream_url.mp3</file>
     </staroeradio>
   </data>
   ```

3. **Базовый URL для world-версии**:
   ```
   http://server.audiopedia.world:8888/getradioinfo.php?cmd=getMetaInfo&track_id=<track_id>
   ```

### Параметры и источники данных

| Сценарий | Параметр | Источник |
|----------|----------|----------|
| Live stream | `track_id` | Из `/getcurrentinfo.php` (XML -> `<staroeradio><id>`) |
| Поиск треков | `track_id` | Из HTML парсинга (URL pattern: `/audio/(\d+)`) |
| Аудиопедия | `track_id` | Из списка треков рубрики |

---

## Рекомендации по реализации в плагине

### 1. Добавление поддержки API (как альтернатива парсингу)

#### 1.1. Создать модуль для работы с API

Создать файл `Plugins/Staroe/ApiClient.pm`:

```perl
package Plugins::Staroe::ApiClient;

use strict;
use warnings;
use Slim::Networking::SimpleAsyncHTTP;
use JSON::XS::VersionOneAndTwo;
use URI::Escape qw(uri_escape_utf8);

my $log = Slim::Utils::Log->addLogCategory({
    'category'     => 'plugin.staroe.api',
    'defaultLevel' => 'DEBUG',
    'description'  => 'Staroe API Client',
});

sub new {
    my ($class, $prefs) = @_;
    my $self = {
        prefs => $prefs,
    };
    return bless $self, $class;
}

sub getBaseUrl {
    my $self = shift;
    my $site = $self->{prefs}->get('siteSelector') || 'staroeradio.ru';
    
    # Определяем сервер на основе домена
    if ($site eq 'staroeradio.com' || $site =~ /\.world/) {
        return 'http://server.audiopedia.world:8888';
    }
    return 'http://server.audiopedia.su:8888';
}

# Получение метаданных с обложками по track_id
sub getTrackMetadata {
    my ($self, $track_id, $callback) = @_;
    
    my $base_url = $self->getBaseUrl();
    my $url = "$base_url/getradioinfo.php?cmd=getMetaInfo&track_id=" . uri_escape_utf8($track_id);
    
    $log->debug("Fetching track metadata: $url");
    
    Slim::Networking::SimpleAsyncHTTP->new(
        sub {
            my $http = shift;
            my $content = $http->content;
            my $json = eval { from_json($content) };
            
            if ($@) {
                $log->error("Failed to parse JSON response: $@");
                return $callback->(undef);
            }
            
            $callback->($json);
        },
        sub {
            $log->error("Failed to fetch track metadata for track_id=$track_id");
            $callback->(undef);
        },
        {
            timeout => 15,
            cache   => 1,
            expires => '1h',
        }
    )->get($url);
}

# Получение информации о текущем треке для live stream
sub getCurrentTrackInfo {
    my ($self, $callback) = @_;
    
    my $base_url = $self->getBaseUrl();
    my $url = "$base_url/getcurrentinfo.php";
    
    $log->debug("Fetching current track info: $url");
    
    Slim::Networking::SimpleAsyncHTTP->new(
        sub {
            my $http = shift;
            my $content = $http->content;
            
            # Парсим XML для получения track_id
            my $track_id;
            if ($content =~ /<staroeradio>\s*<id>(\d+)<\/id>/s) {
                $track_id = $1;
            }
            
            $callback->({
                track_id => $track_id,
                raw_xml => $content,
            });
        },
        sub {
            $log->error("Failed to fetch current track info");
            $callback->(undef);
        },
        {
            timeout => 15,
            cache   => 0,  # Не кэшируем для live stream
            expires => '0s',
        }
    )->get($url);
}

1;
```

#### 1.2. Интеграция в Plugin.pm

Добавить в начало `Plugin.pm`:

```perl
use Plugins::Staroe::ApiClient;

# В sub initPlugin после инициализации prefs
my $apiClient = Plugins::Staroe::ApiClient->new($prefs);
```

### 2. Обработка live stream с обложками

#### 2.1. Модификация `_parseChannel` для поддержки динамических обложек

```perl
sub _parseChannel {
    my ($channel) = @_;

    return {
        name => _getFirstLineText($channel, 0),
        description => $channel->{'description'},
        
        line1 => _getFirstLineText($channel, 1),
        line2 => _getSecondLineText($channel),
        type =>'audio',
        url => _getStream($channel),
        image => $channel->{'image'},  # Статическая обложка канала
        
        # Добавляем callback для динамического обновления обложки
        on_play => sub {
            my $client = shift or return;
            
            # Получаем текущий track_id через API
            $apiClient->getCurrentTrackInfo(sub {
                my $info = shift or return;
                my $track_id = $info->{track_id} or return;
                
                # Получаем метаданные с обложками
                $apiClient->getTrackMetadata($track_id, sub {
                    my $metadata = shift or return;
                    
                    # Обновляем обложку
                    if ($metadata->{Metainfo} && $metadata->{Metainfo}->{images}) {
                        my @images = @{$metadata->{Metainfo}->{images}};
                        if (@images) {
                            my $first_image = $images[0];
                            
                            # Обновляем метаданные трека
                            my $song = $client->playingSong() or return;
                            $song->pluginData($metadata->{Metainfo});
                            
                            # Уведомляем об обновлении метаданных
                            Slim::Control::Request::notifyFromArray($client, ['newmetadata']);
                        }
                    }
                });
            });
        },
    };
}
```

### 3. Обработка треков из поиска с обложками

#### 3.1. Модификация `_parseSearchResults` для API-режима

Добавить переключатель режима (API/parsing) в `_searchHandler`:

```perl
sub _searchHandler {
    my ( $client, $cb, $args) = @_;
    my $query = $args->{search};

    my $use_api = $prefs->get('useApiMode') || 'parsing';
    
    # Transliteration если включено
    my $translit = $prefs->get('translitSearch');
    if ($translit eq 'enable') {
        $query = _transliterate($query);
    }
    
    if (length($query) < MIN_SEARCH_LENGTH) {
        return $cb->([]);
    }

    if ($use_api eq 'api') {
        _searchViaApi($query, $cb);
    } else {
        _searchViaParsing($query, $cb);
    }
}
```

#### 3.2. Реализация поиска через API

```perl
sub _searchViaApi {
    my ($query, $cb) = @_;
    
    my $base_url = $apiClient->getBaseUrl();
    my $timestamp = time();
    my $url = "$base_url/search?q=" . uri_escape_utf8($query) . "&_=$timestamp";
    
    # Для API-режима можно использовать тот же эндпойнт поиска,
    # но парсить JSON вместо HTML, если API возвращает JSON
    
    Slim::Networking::SimpleAsyncHTTP->new(
        sub {
            my $http = shift;
            my $html = $http->content;
            
            # Извлекаем track_id из результатов
            my @results = _parseSearchResultsApiMode($html);
            $cb->(\@results);
        },
        sub {
            $log->error("API search failed");
            $cb->([]);
        },
        {
            timeout => HTTP_TIMEOUT,
            cache   => HTTP_CACHE,
            expires => HTTP_EXPIRES,
        }
    )->get($url);
}

sub _parseSearchResultsApiMode {
    my ($html) = @_;
    my @results;
    
    # Парсим HTML для извлечения track_id
    my $p = HTML::TokeParser->new(\$html);
    unless ($p) {
        $log->error("Failed to create TokeParser");
        return ();
    }
    
    while (my $token = $p->get_tag('a')) {
        my $href = $token->[1]{href};
        next unless defined $href;
        
        # Извлекаем track_id
        next unless $href =~ m{/(?:audio|radio)/(\d+)}i;
        my $track_id = $1;
        
        # Находим название трека
        my $title;
        while (my $inner_token = $p->get_token) {
            last if $inner_token->[0] eq 'E' && $inner_token->[1] eq 'a';
            
            if ($inner_token->[0] eq 'S' && $inner_token->[1] eq 'div') {
                my $class = $inner_token->[2]{class} || '';
                next unless $class eq 'mp3name';
                
                $title = '';
                while (my $text_token = $p->get_token) {
                    last if $text_token->[0] eq 'E' && $text_token->[1] eq 'div';
                    $title .= $text_token->[1] if $text_token->[0] eq 'T';
                }
                last;
            }
        }
        
        next unless $title;
        
        # Очистка title
        $title =~ s/^\s*<b>.*?<\/b>\s*//;
        $title =~ s/\s*$$.*?$$//g;
        $title =~ s/^\s+|\s+$//g;
        $title = decode('UTF-8', $title);
        
        my $selected_site = $prefs->get('siteSelector') || 'staroeradio.ru';
        my $is_world = ($selected_site eq 'staroeradio.com');
        my $base_url = $is_world 
            ? 'http://server.audiopedia.world:8888/get_mp3_radio_128.php?id='
            : 'http://server.audiopedia.su:8888/get_mp3_radio_128.php?id=';
        
        my $stream_url = $base_url . $track_id;
        
        push @results, {
            name        => $title,
            title       => $title,
            artist      => 'Старое радио',
            play        => $stream_url,
            url         => $stream_url,
            type        => 'audio',
            duration    => 0,
            
            # В API-режиме устанавливаем коллбек для загрузки обложки
            on_play => sub {
                my $client = shift or return;
                
                $apiClient->getTrackMetadata($track_id, sub {
                    my $metadata = shift or return;
                    
                    # Устанавливаем первую обложку как иконку трека
                    if ($metadata->{Metainfo} && $metadata->{Metainfo}->{images}) {
                        my @images = @{$metadata->{Metainfo}->{images}};
                        if (@images) {
                            my $first_image = $images[0];
                            
                            # Обновляем метаданные трека
                            my $song = $client->playingSong() or return;
                            $song->cover($first_image);
                            $song->title($title);
                            $song->artist('Старое радио');
                            $song->pluginData($metadata->{Metainfo});
                            
                            # Уведомляем об обновлении
                            $client->currentSong()->title($title);
                            $client->currentSong()->artist('Старое радио');
                            Slim::Control::Request::notifyFromArray($client, ['newmetadata']);
                        }
                    }
                });
            },
        };
    }
    
    return @results;
}
```

### 4. Добавление настроек переключения режимов

Добавить в настройки (`Plugins/Staroe/Settings.pm`):

```perl
sub pageSettings {
    my ($class, $client, $prefs) = @_;
    
    return {
        'useApiMode' => {
            'type' => 'select',
            'label' => 'PLUGIN_STAROE_USE_API_MODE',
            'choices' => [
                ['parsing', 'PLUGIN_STAROE_MODE_PARSING'],
                ['api', 'PLUGIN_STAROE_MODE_API'],
            ],
            'initial' => 'parsing',
            'onChange' => sub {},
            'options' => {},
        },
    };
}
```

Добавить в `strings.txt`:

```
PLUGIN_STAROE_USE_API_MODE	Режим работы
PLUGIN_STAROE_MODE_PARSING	Парсинг HTML
PLUGIN_STAROE_MODE_API		Использовать API
```

---

## План внедрения

### Этап 1: Базовая инфраструктура
1. Создать `Plugins/Staroe/ApiClient.pm`
2. Добавить переключатель режима в настройки
3. Добавить инициализацию `$apiClient` в `Plugin.pm`

### Этап 2: Live stream обложки
1. Реализовать callback `on_play` для каналов
2. Добавить получение текущего track_id
3. Добавить загрузку метаданных с обложками
4. Тестирование на live stream

### Этап 3: Обложки для треков из поиска
1. Реализовать `_searchViaApi`
2. Реализовать `_parseSearchResultsApiMode`
3. Добавить callback `on_play` для результатов поиска
4. Тестирование поиска

### Этап 4: Оптимизация
1. Добавить кэширование метаданных
2. Добавить fallback-режим при ошибках API
3. Логирование и отладка

---

## Преимущества использования API

1. **Структурированные данные** - JSON вместо хрупкого HTML парсинга
2. **Надежность** - меньше зависит от изменений в верстке сайта
3. **Производительность** - меньше данных для передачи
4. **Поддержка обложек** - готовые URL изображений
5. **Будущая совместимость** - API более стабильный интерфейс

## Минусы API

1. **Дополнительная зависимость** - еще один HTTP запрос
2. **Возможные задержки** - загрузка обложек занимает время
3. **Кэширование** - нужно аккуратно настраивать

---

## Важные замечания

1. **Обратная совместимость**: Оставить режим парсинга как дефолтный для плавного перехода

2. **Обработка ошибок**: При отказе API автоматически падать обратно на парсинг

3. **Кэширование**: 
   - Для live stream: не кэшировать (каждый раз новый трек)
   - Для поиска: кэшировать на 1 час
   - Для метаданных: кэшировать на 24 часа

4. **Логирование**: Детальное логирование для отладки в категории `plugin.staroe.api`

5. **Тестирование**: Проверить работу на обоих доменах (`.ru` и `.com`)
