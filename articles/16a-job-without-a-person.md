# Задание без человека: почему ночной опрос получил бы `401`

> «От системы к делу» · статья 16а · читать минут 25
>
> **Для кого.** Ты прочитал статьи 0–16, и у тебя есть песочница
> `game-day` после статьи 16. Особенно пригодятся кука и заголовок
> `Authorization` (статьи 4–5), ночной обход, который переживает сбой
> (статья 15), и заглушки Mockito (статьи 4–5).
>
> **Что будет.** Почему вызов, который работает из карточки менеджера,
> ночью из `@Scheduled` получил бы `401` — и почему этого не видели ни
> стенд, ни тесты. Как устроить два HTTP-клиента, чтобы ключ нельзя было
> ни забыть, ни отправить не тем, и как читать `401` и `404` чужой
> системы. Как тестом доказать, что ключ уходит.
>
> **Откуда статья.** Раздел «Буткемп / Лаборатория» — о том, как пишут
> код команды Hammerhall: буткемп работает в открытых репозиториях,
> лаборатория — в закрытых. Серия «От системы к делу» — следующий шаг
> после «От Spring к системе»: как правила дела — сроки, деньги,
> обещания людям — живут в коде. Примеры — учебные: их можно повторить
> у себя.

---

## Зачем разбирать этот баг

Вспомни правило из статьи 15: не удался сам запрос — работать не с чем,
запись в лог и `return`. Правило верное. Но тот же `return` сработает
и тогда, когда система клуба не лежит, а просто не пускает.

Так бывает. Три задания учебной CRM ходят в систему клуба без пропуска:
ночной обход продлений и обход предложений из статьи 15, опрос броней
из статьи 16. На боевом ни одно из них не сделало бы ничего полезного.
А стенд показывает, что всё работает, тесты зелёные, приложение
не падает.

Хуже того, об этом знали. Автор первого задания оставил в коде пометку:
«здесь нет куки; двойник на стенде пропуск не проверяет и этого
не покажет».

Статья разбирает этот баг: как он устроен, почему его не видно и как
сделать, чтобы он не вернулся. Куски учебной CRM — для чтения,
выброшенное в них помечено `// …`. Свой код статьи — упрощённая модель
клиента системы клуба `ClubClient` в пакете `example.crm` и тест
`ClubClientTest`, который ходит по настоящему HTTP. В модели ответ —
строка JSON: разбирать его здесь не нужно, а учебная CRM по-прежнему
получает списки. В коротких примерах нет строк `import` — полные файлы
в конце статьи.

---

## Часть 1. Два способа войти

### Система клуба спрашивает: кто ты

CRM сама не знает, кто менеджер, а кто нет. Людей, пароли и права хранит
система клуба, и менеджер входит именно в неё. Поэтому каждый запрос CRM
к системе клуба должен сказать, кто спрашивает. Не сказал — система
клуба отвечает `401`: «не знаю, кто ты».

Сказать это можно двумя способами. Какой подходит, зависит от того, кто
запустил код в CRM.

### RestClient: как CRM ходит в систему клуба

**`RestClient`** — HTTP-клиент из Spring: собирает запрос, отправляет
его и читает ответ.

* **Зачем.** Руками пришлось бы открыть соединение, записать заголовки,
  прочитать байты ответа и разобрать код. `RestClient` делает это одной
  цепочкой вызовов.
* **Откуда.** Класс из `spring-web`. Его приносит веб-стартер
  из статьи 4, ставить ничего не нужно.
* **Как устроен.** Клиент собирают строителем (статья 7):
  `RestClient.builder()…build()`. Запрос — тоже цепочка: `get()` — метод,
  `.uri(…)` — путь, `{id}` в нём заменяет аргумент, `.header(…)` —
  заголовок, `.retrieve()` и `.body(String.class)` — отправить и прочитать
  тело ответа строкой. На ответ `4xx` цепочка бросает исключение:
  на `401` — `HttpClientErrorException.Unauthorized`, на `404` —
  `HttpClientErrorException.NotFound`.

### Запрос менеджера: кука

Менеджер открыл карточку лида. Его браузер прислал в CRM куку `SESSION`
— ту самую строку из статьи 4, по которой узнают, кто спрашивает. CRM
передаёт её системе клуба как есть:

```java
    public String visits(String sessionCookie, UUID personId) {
        return http.get()
                .uri("/club/people/{id}/visits", personId)
                .header(HttpHeaders.COOKIE, "SESSION=" + sessionCookie)
                .retrieve()
                .body(String.class);
    }
```

`http` — клиент менеджера. Система клуба видит человека с правами
менеджера, пускает его и записывает действие на него. Кука — параметр
метода: без неё метод менеджера не позвать.

### Задание по расписанию: человека нет

Обход продлений ты видел в статье 15: Spring сам будит его в 02:00
по Москве.

```java
// учебная служба обхода продлений — сокращено
    @Scheduled(cron = "${club.sales.renewals.poll-cron:0 0 2 * * *}",
            zone = "${club.sales.renewals.poll-zone:Europe/Moscow}")
    public void pollEndingMemberships() {
        // …
            ending = club.endingWithin(props.getPollWindowDays());       // спросить систему клуба
```

Никто ничего не нажимал. Нет браузера, нет запроса — значит, нет
и куки. Метод зовёт планировщик Spring в своём потоке. Такому вызову
нужен другой пропуск.

### Пропуск без человека: служебный ключ

Для этого в системе клуба заводят **служебную запись** — учётную запись
без человека, со своим **служебным ключом**. Ключ — длинная случайная
строка, её знают только CRM и система клуба. Едет он в заголовке
`Authorization`, который ты видел в статье 5:

```
Authorization: Bearer <служебный ключ>
```

В статье 5 после `Authorization` шло слово `Basic`, а за ним — имя
и пароль. **Bearer** значит «предъявитель»: кто принёс ключ, тот
и проходит. Так это слово определяет стандарт RFC 6750. Откуда оно
взялось — в выпуске 2 «Историй слов»,
[«Ключ Bearer: „обещаю заплатить предъявителю“»](https://hammerhall.io/ledger/words/2-bearer).

Раз ключ пускает любого, кто его принёс, права у служебной записи
узкие: только читать. Утёкший ключ покажет чужие посещения, но
не отметит оплату и не запишет человека в группу.

| | запрос менеджера | задание по расписанию |
|---|---|---|
| кто запускает | человек в браузере | планировщик Spring, по cron |
| заголовок в систему клуба | `Cookie: SESSION=…` | `Authorization: Bearer <ключ>` |
| права в системе клуба | менеджера | служебной записи: только читать |
| от чьего имени действие | менеджера | самой CRM |

Смешивать их нельзя в обе стороны. Запрос менеджера с ключом ушёл бы
от имени CRM: система клуба не узнает, кто смотрел, и не проверит права
менеджера. А у ночного задания куки просто нет: взять её неоткуда.
Сохранить куку какого-нибудь менеджера тоже нельзя. Она живёт, пока
длится его сеанс (статья 5), а действия задания записались бы
на человека, который их не делал.

---

## Часть 2. Как сломалось и почему никто не видел

### Один клиент на всех

До исправления у учебной CRM был один клиент системы клуба:

```java
// учебный клиент системы клуба до исправления — сокращено
    public ClubClient(RestClient.Builder builder, ClubSystemProperties props) {
        this.http = builder
                .baseUrl(props.getBaseUrl())
                .build();
    }

    public List<EndingMembership> endingWithin(int days) {
        EndingMembership[] rows = http.get()
                .uri("/club/memberships/ending?within-days={days}", days)
                .retrieve()
                .body(EndingMembership[].class);
        return rows == null ? List.of() : List.of(rows);
    }
```

У клиента нет заголовков, которые он сам кладёт в каждый запрос. Методы
менеджера кладут куку сами, каждый в своём вызове. А метод задания
не кладёт ничего: ни куки, ни ключа. Запрос уходит **анонимным** — без
всякого пропуска. Так же устроены ещё два метода заданий: посещения
человека для обхода предложений и брони для опроса броней.

### Ночь на боевом

Вот что случалось бы каждую ночь:

1. В 02:00 планировщик запускает `pollEndingMemberships()`.
2. `endingWithin(14)` уходит в систему клуба без пропуска.
3. Система клуба отвечает `401`.
4. Срабатывает тот самый `catch` из статьи 15:

    ```java
            } catch (Exception e) {
                logger.error("Обход продлений не удался — следующий по расписанию", e);
                return;                                                      // работать не с чем
            }
    ```

5. Задач менеджеру нет. Приложение живо. Следующей ночью — то же самое.

`catch` здесь по-прежнему правильный: одна неудачная ночь не должна
ронять сервис. Но вместе с анонимным запросом он превращает поломку
в строку лога, которую никто не читает. Падение замечают за минуту.
Тишину — когда менеджер спросит, почему человеку никто не напомнил
о продлении.

### Почему молчал стенд

На стенде учебной CRM системы клуба нет. Вместо неё отвечает двойник
из статьи 6 — WireMock: на знакомые запросы он отдаёт записанные ответы.
Правила у него — файлы JSON.
Правило двойника для продлений:

```json
{
  "request": {
    "method": "GET",
    "urlPath": "/club/memberships/ending"
  },
  "response": {
    "status": 200,
    "headers": { "Content-Type": "application/json" },
    "bodyFileName": "ending.json"
  }
}
```

`urlPath` — путь без параметров после `?`: правило подходит и к запросу
`…/ending?within-days=14`. В `request` — метод и путь. О заголовках
ни слова, и правило подходит к любому запросу: с кукой, с ключом или
вовсе без пропуска. Анонимный запрос получал на стенде `200` и честный
JSON из файла `ending.json`.

WireMock умеет сверять и заголовки: для этого в `request` пишут раздел
`headers`. Как сделать двойника строже — в конце статьи.

### Почему молчали тесты

Тест обхода из статьи 15 подменяет клиента заглушкой Mockito:

```java
// учебный тест обхода продлений — сокращено
        when(club.endingWithin(14)).thenReturn(List.of(broken, fine));
```

Заглушка в сеть не ходит, и заголовков тест не видит. Он проверяет,
что обход делает с ответом, и проверяет это хорошо. Но с каким
пропуском запрос ушёл бы в систему клуба, ему не узнать. Почему так
и что подменять в тестах — в
[статье 6 «Когда вокруг твоего кода другой код»](https://hammerhall.io/ledger/testing/6-stubs)
серии «От красного к зелёному».

### Пометка, которая не краснеет

Вспомни пометку из начала статьи: «здесь нет куки». Автор задания
увидел дыру и записал её. В двух следующих заданиях приём скопировали
вместе с пометкой.

🔑 Знание, записанное в комментарии, не защищает: комментарий
не краснеет. Защищает механизм — устройство кода, которое не даёт
ошибиться, и тест, который краснеет. Дальше — оба.

---

## Часть 3. Ключ, который нельзя забыть

### Откуда ключ

Новая настройка в учебной CRM одна:

```yaml
# учебная CRM: application.yml — сокращено
club:
  system:
    service-key: ${CLUB_SERVICE_KEY:}
```

Значение приходит из переменной окружения `CLUB_SERVICE_KEY`;
подстановку `${имя:умолчание}` ты видел в статье 2. Самого ключа нет
ни в коде, ни в `yml`, ни в репозитории. На боевом переменную заполняют
из хранилища секретов.

В статье 2 было правило: у секретов умолчания нет никогда. Здесь после
двоеточия пусто, и это сознательное исключение. Пустое умолчание значит
«ключа нет». CRM поднимается, но задания в систему клуба не ходят. Так
нужно на ноутбуке разработчика: служебного ключа там нет, а запускать
CRM надо.

Цена — та самая тишина, о которой вся статья. Поэтому на боевом
исключения нет:

```yaml
# учебная CRM: application-prod.yml — сокращено
club:
  system:
    service-key: ${CLUB_SERVICE_KEY}
```

Профильный файл побеждает общий (статья 2), и умолчания у ключа на
боевом нет. А настройки, как в статье 2, проверяют, что ссылка
подставилась. Забыли переменную — CRM не поднимется. Такое замечают
за минуту, а не через месяц.

### Два клиента вместо одного

Главная правка — в конструкторе `ClubClient`:

```java
    public ClubClient(RestClient.Builder builder, String baseUrl, String serviceKey) {
        this.http = builder
                .baseUrl(baseUrl)
                .build();
        if (serviceKey == null || serviceKey.isBlank()) {
            this.serviceHttp = null;
        } else {
            // mutate() берёт всё, что есть у клиента менеджера; добавляется только заголовок
            this.serviceHttp = http.mutate()
                    .defaultHeader(HttpHeaders.AUTHORIZATION, "Bearer " + serviceKey.strip())
                    .build();
        }
    }
```

Теперь клиентов два. `http` — для менеджера, как раньше. `serviceHttp`
— для заданий. **`defaultHeader`** — заголовок по умолчанию: клиент сам
добавляет его к каждому своему запросу. **`mutate()`** даёт строитель,
в котором уже есть всё, что у готового клиента: адрес и прочие
настройки. Меняется одно — добавляется ключ.

Почему не заголовок в каждом методе? Тогда о нём пришлось бы помнить
в трёх местах, а четвёртый метод задания рано или поздно его забудет.
У клиента менеджера ключа нет, и метод менеджера его не отправит.
Ключ заданиям кладёт клиент, а не метод. Правило держит устройство кода,
а не внимательность того, кто пишет следующий метод.

### Строитель помнит всё

⚠️ Почему `http.mutate()`, а не второй раз `builder`? Строитель
запоминает всё, что в него положили. Документация Boot так и пишет:
`RestClient.Builder` хранит состояние, и его правка попадает во все
клиенты, собранные после неё. Собери клиент заданий из `builder`
первым — и ключ уйдёт с каждым запросом менеджера. Ровно то, чего быть
не должно. `mutate()` у готового клиента даёт отдельный строитель,
а тот, что пришёл в конструктор, остаётся нетронутым.

Строитель в учебной CRM приходит от Boot:

```java
// учебная настройка клиента системы клуба — сокращено
    @Bean
    ClubClient clubClient(RestClient.Builder builder, ClubSystemProperties props) {
        ClubClient client = new ClubClient(builder, props.getBaseUrl(), props.getServiceKey());
        if (!client.hasServiceKey()) {
            logger.warn("Служебного ключа нет (CLUB_SERVICE_KEY): задания в систему клуба не ходят");
        }
        return client;
    }
```

Boot сам настраивает строитель: знает, как читать JSON и чем отправлять
запросы. Каждому, кто его попросил, он выдаёт отдельный экземпляр.
Обычный бин один на всё приложение (статья 1), а этот —
**`prototype`**: новый объект на каждую просьбу. `hasServiceKey()`
отвечает, есть ли служебный ключ. А тест передаёт строитель сам,
`RestClient.builder()`: так сделано в части 4.

⚠️ В интернете ты увидишь, что бин `RestClient.Builder` в Spring Boot
«есть всегда». Это Boot 3. В Boot 4 автонастройка клиентов вынесена
в отдельный модуль: без стартера бина `RestClient.Builder` в контексте
нет. Поэтому в `pom.xml` учебной CRM есть зависимость:

```xml
<!-- учебная CRM: pom.xml, в <dependencies> -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-restclient</artifactId>
</dependency>
```

Без неё методу `clubClient` нечего получить первым параметром,
и приложение не поднимется.

### Один путь для заданий

Все три метода заданий идут через один вход:

```java
    private String serviceCall(Function<RestClient, String> request) {
        if (serviceHttp == null) {
            throw new ServiceKeyMissingException();
        }
        try {
            return request.apply(serviceHttp);
        } catch (HttpClientErrorException.Unauthorized e) {
            throw new ServiceKeyRejectedException(e);
        }
    }
```

`Function<RestClient, String>` — лямбда, которая из клиента делает
ответ, а `apply` её вызывает.
А сам метод задания стал таким:

```java
    public String endingWithin(int days) {
        return serviceCall(service -> service.get()
                .uri("/club/memberships/ending?within-days={days}", days)
                .retrieve()
                .body(String.class));
    }
```

Сравни с версией из части 2. Было `http.get()…`, стало
`serviceCall(service -> service.get()…)`. Клиент приходит в лямбду
параметром, и это всегда клиент с ключом. На `401` `serviceCall`
бросает своё исключение, `ServiceKeyRejectedException`: о нём — ниже.

### Нет ключа — не ходим

Каждое задание теперь начинается с проверки:

```java
// учебная служба обхода продлений — начало метода
    public void pollEndingMemberships() {
        if (!club.hasServiceKey()) {
            return;                              // предупреждение — один раз, при старте
        }
```

Без ключа задание молча выходит. В логе одно предупреждение при старте,
а не ошибка каждую ночь. Если кто-то позовёт метод задания в обход этой
проверки, `serviceCall` бросит `ServiceKeyMissingException` ещё до сети.
Пока методы заданий идут через `serviceCall`, анонимный запрос не уйдёт.

💡 Метод задания можно написать и мимо `serviceCall`, прямо через
`http`. Тест из части 4 поймает это, только если метод есть в его
списке. Новый метод задания — новая строка в `jobCalls()`.

### `401` и `404` — разные беды

Права служебной записи система клуба может сузить или отозвать. Тогда
ключ она примет, а людей не покажет.

| ответ | что значит | что делать |
|---|---|---|
| `401` | ключ не принят: неверен или отозван | прервать обход — на следующем человеке будет то же |
| `404` | нет такого человека — или у ключа нет прав | смотря какое задание, ниже |

Почему система клуба отвечает `404` там, где на деле «нельзя»? Так она
не выдаёт, существует ли человек. Номер человека мог утечь вместе
с ключом, а ответ `403` подтвердил бы, что такой человек в клубе есть.
Стандарт RFC 6750 для нехватки прав предлагает `403`, а `404` — выбор
этой системы клуба.

Поэтому `serviceCall` превращает `401` в `ServiceKeyRejectedException`,
а `404` оставляет как есть, `HttpClientErrorException.NotFound`. `401` —
точно ключ. `404` — данные или права, и различить их помогает порог
в обходе предложений.

### Обход предложений: по человеку за раз

Обход предложений из статьи 15 спрашивает систему клуба о каждом
человеке. Цикл теперь, как у продлений, ловит ошибку каждого лида:

```java
// учебная служба обхода предложений — цикл, сокращено
        int notFoundInRow = 0;
        for (Lead member : members) {
            try {
                offers.consider(member);                           // спросить систему клуба и решить
                notFoundInRow = 0;
            } catch (ServiceKeyRejectedException e) {
                logger.error("Обход предложений прерван на лиде {}: {}", member.getId(), e.getMessage());
                return;                                            // ключ не приняли — дальше то же
            } catch (HttpClientErrorException.NotFound e) {
                notFoundInRow++;
                if (notFoundInRow >= MAX_NOT_FOUND_IN_ROW) {
                    logger.error("Обход предложений прерван: {} ответов 404 подряд. "
                            + "Похоже на права ключа, а не на данные", notFoundInRow);
                    return;
                }
                logger.warn("Система клуба не знает человека лида {} (404), лид пропущен", member.getId());
            } catch (Exception e) {
                notFoundInRow = 0;
                logger.error("Лид {} не разобран, идём дальше", member.getId(), e);
            }
            // … пауза между лидами — статья 15
        }
```

* **`401`** — обход прерывается сразу, одной строкой в логе. Без этого
  было бы по стеку на каждого лида — и пауза перед следующим.
* **Одиночный `404`** — лид пропускается. Скорее всего, номер человека
  у него неверный: например, лид завели руками с опечаткой. Прерывать
  на первом нельзя: один такой лид останавливал бы обход каждую ночь.
* **Три `404` подряд** — уже не случайность: похоже, у ключа отобрали
  права. Обход прерывается, и сообщение прямо говорит, что проверить.

Порог — константа `MAX_NOT_FOUND_IN_ROW = 3` в службе обхода.
В настройки его не выносят: менеджер продаж его менять не попросит
(статья 15). Как бы ты выбрал число? Один — и обход встаёт из-за одной
опечатки. Сто — и при отозванных правах обход сто раз спросит впустую.

### Продления и брони: один запрос за запуск

Обход продлений и опрос броней спрашивают систему клуба один раз
за запуск, прерывать там нечего. Отказ ловит тот же общий `catch`,
и запуск пропускается. Только теперь сообщение говорит, что чинить:
«система клуба не приняла служебный ключ (401) — проверь
CLUB_SERVICE_KEY».

---

## Часть 4. Доказать, что ключ уходит

### Кто видит заголовок

Заголовок видит только тот, кто принимает запрос. Двойник стенда
заголовков не сверяет, заглушка до сети не доходит. Значит, тесту нужен
настоящий сервер, пусть и маленький. WireMock подошёл бы и здесь, но
это ещё одна зависимость, а сервер попроще есть прямо в JDK.

**`HttpServer`** — простой HTTP-сервер из JDK.

* **Зачем.** Принять настоящий запрос клиента и увидеть его целиком,
  с заголовками.
* **Откуда.** Часть JDK, пакет `com.sun.net.httpserver`: зависимость
  ставить не нужно.
* **Как запускается.** Тест поднимает его перед каждым тестом и гасит
  после. Результат — обычный отчёт JUnit.

```java
    @BeforeEach
    void startServer() throws IOException {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/", exchange -> {
            received.add(exchange.getRequestHeaders());
            exchange.sendResponseHeaders(status, -1);
            exchange.close();
        });
        server.start();
        baseUrl = "http://127.0.0.1:" + server.getAddress().getPort();
    }
```

Как читать:

* `new InetSocketAddress("127.0.0.1", 0)` — где слушать. Порт `0` значит
  «любой свободный»: тесты не мешают друг другу и не зависят от того,
  что ещё запущено на машине. Второй аргумент `create` — длина очереди
  соединений: ноль значит «по умолчанию»;
* `createContext("/", …)` — кто отвечает на запросы с путём от `/`,
  то есть на все; `exchange` — один запрос и ответ на него;
* сервер записывает заголовки каждого запроса в `received` и отвечает
  кодом из поля `status`, без тела. По умолчанию это `204`: «готово,
  тела нет». Тест проверяет запрос, а не разбор ответа.

Сервер отвечает в своём потоке, а проверяет тест в своём. Поэтому
`received` — `CopyOnWriteArrayList`, список, который безопасно дописывать
из одного потока и читать из другого. У поля `status` по той же причине
стоит `volatile`.

### В обе стороны

Вызовы собраны в два списка — заданий и менеджера:

```java
    static Stream<Named<Consumer<ClubClient>>> jobCalls() {
        return Stream.of(
                named("продления: endingWithin(days)", c -> c.endingWithin(14)),
                named("брони: holdsWithin(hours)", c -> c.holdsWithin(48)),
                named("предложения: visits(personId)", c -> c.visits(PERSON)));
    }
```

Тест по таблице (статья 0) проходит по каждому вызову задания:

```java
    @ParameterizedTest(name = "{0}")
    @MethodSource("jobCalls")
    void jobCall_sendsServiceKeyAndNoCookie(Consumer<ClubClient> call) {
        call.accept(client(KEY));

        Headers headers = onlyRequest();
        assertThat(headers.getFirst("Authorization")).isEqualTo("Bearer " + KEY);
        assertThat(headers.get("Cookie")).isNull();
    }
```

`@MethodSource` (статья 7) и `named(…)` (статья 11) — как раньше: строки
таблицы берутся из метода, у каждой — имя. В дереве тестов IDE видно
«брони: holdsWithin(hours)», и упавшая строка находится сразу. Новое
здесь:

* `Consumer<ClubClient>` — лямбда, которая что-то делает с клиентом
  и ничего не возвращает. Здесь она зовёт один его метод;
* `onlyRequest()` проверяет, что запрос был ровно один, и отдаёт его
  заголовки.

Второй такой же тест проходит по вызовам менеджера и проверяет обратное:
кука есть, ключа нет, **даже когда ключ задан**. Это правило «не
смешивать», записанное тестом. Первый тест ловит задание без ключа,
второй — вызов менеджера, к которому ключ прилип случайно.

### Без ключа — ни одного запроса

```java
    @ParameterizedTest(name = "{0}")
    @MethodSource("jobCalls")
    void jobCall_withoutKey_failsBeforeNetwork(Consumer<ClubClient> call) {
        ClubClient client = client("");

        assertThatThrownBy(() -> call.accept(client))
                .isInstanceOf(ServiceKeyMissingException.class)
                .hasMessageContaining("CLUB_SERVICE_KEY");
        assertThat(received).as("запрос без пропуска не отправлен").isEmpty();
    }
```

`as(…)` — подпись проверки: её покажет красный отчёт. Последняя строка —
главная: сервер не получил ничего. Ещё четыре теста в том же классе
проверяют вызовы менеджера без ключа, `401` и `404` у заданий, `401`
у вызовов менеджера. И последний — что пустой ключ и ключ из пробелов
значат «ключа нет». Всего в классе 21 запуск.

### Тест умеет краснеть

Зелёному тесту верят, только если видели его красным (статья 11).
Убери из конструктора одну строку — ту, где `defaultHeader`:

```
[ERROR] Tests run: 21, Failures: 3, Errors: 0, Skipped: 0

expected: "Bearer test-service-key"
 but was: null
```

Покраснели ровно три запуска — по одному на каждый вызов задания.
Верни строку — 21 из 21 снова зелёные.

💡 Тест держит клиента, но не стенд. Пусть и двойник отвечает на запрос
без пропуска так же, как настоящая система клуба, — `401`. Одного
раздела `headers` для этого мало. На запрос, который не подошёл ни
к одному правилу, WireMock отвечает `404`, а такой ответ CRM прочтёт как
«нет человека». Нужно второе правило на тот же путь: без `headers`,
с приоритетом пониже и ответом `401`. Приоритет у WireMock — поле
`priority`: чем больше число, тем ниже приоритет.

---

## Проверь себя

Ответь своими словами — вслух или на бумаге. Не получается — перечитай
раздел.

1. Почему `endingWithin()` работал на стенде и получил бы `401`
   на боевом?
2. Чем вызов из `@Scheduled` отличается от запроса менеджера? Почему
   заданию нельзя дать куку менеджера?
3. Почему у служебного ключа права только на чтение?
4. Зачем второй `RestClient`, если заголовок можно добавить в каждом
   из трёх методов?
5. Что случится, если собрать клиент заданий из `builder` первым,
   а клиент менеджера — из того же `builder` после?
6. Почему обход предложений прерывается на первом `401`, но не на
   первом `404`?
7. Почему этот баг не могли поймать ни двойник стенда, ни заглушка
   Mockito, а тест с `HttpServer` может?
8. Все 21 запуск зелёные. Как убедиться, что им можно верить?

---

## Что дальше

Дальше в серии — разговор о самом коде: код, который пишут за тебя.
Геттеры классов настроек из статьи 15 дописывает Lombok — в следующей
статье станет видно, как он это делает и чего это стоит.

## Первоисточники

* [Spring Boot 4.0: Calling REST Services](https://docs.spring.io/spring-boot/4.0/reference/io/rest-client.html) —
  строитель `RestClient.Builder` от Boot: `prototype` и почему строитель
  хранит состояние;
* [Spring Framework: RestClient](https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/web/client/RestClient.html) —
  `mutate()`: новый клиент с настройками готового;
* [RFC 6750: Bearer Token Usage](https://www.rfc-editor.org/rfc/rfc6750) —
  что такое ключ предъявителя, как он едет в заголовке и какой ответ
  ждать при нехватке прав;
* [WireMock: Request Matching](https://wiremock.org/docs/request-matching/) —
  как правило двойника сверяет запрос, в том числе заголовки;
* [Java SE 25: HttpServer](https://docs.oracle.com/en/java/javase/25/docs/api/jdk.httpserver/com/sun/net/httpserver/HttpServer.html) —
  сервер из JDK, на котором стоит тест.

---

## Пример целиком — с импортами

Учебный пример. Запускай в песочнице `game-day` после статьи 16: журнал
в `example.gameday.journal` со всем, что накопили статьи 1–10, сторожа
статьи 11, модель статей 12–16 в `example.crm` и её тесты, Postgres
в контейнере, охрана, Actuator и стенд — всё остаётся, менять ничего
не нужно. В `pom.xml` ничего не добавляй: `RestClient` приносит
веб-стартер из статьи 4, `HttpServer` — часть JDK, JUnit и AssertJ —
со `spring-boot-starter-test`.

Что добавить: в `src/main/java/example/crm/` — `ClubClient` (упрощённая
модель клиента системы клуба) и два исключения,
`ServiceKeyMissingException` и `ServiceKeyRejectedException`;
в `src/test/java/example/crm/` — `ClubClientTest`. Куски учебной CRM —
для чтения, в песочницу их не клади: обходы с `@Scheduled`, клиент
до исправления, правило двойника, настройки, бин и цикл обхода
предложений.

Запуск: треугольником у класса в IDE или
`./mvnw test -Dtest=ClubClientTest`. Docker этому тесту не нужен;
весь `./mvnw verify` гоняет и `*IT` — для них Docker нужен. Путь
к файлу — комментарием в первой строке.

```java
// src/main/java/example/crm/ClubClient.java
package example.crm;

import java.util.UUID;
import java.util.function.Function;

import org.springframework.http.HttpHeaders;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestClient;

/**
 * Клиент системы клуба: вызовы менеджера идут с его кукой, вызовы заданий по расписанию — со служебным
 * ключом. Учебная модель: ответ — строкой JSON, разбирать его здесь не нужно.
 */
public final class ClubClient {

    private final RestClient http;          // для менеджера: куку кладёт каждый метод сам
    private final RestClient serviceHttp;   // для заданий: ключ в каждом запросе; null — ключа нет

    public ClubClient(RestClient.Builder builder, String baseUrl, String serviceKey) {
        this.http = builder
                .baseUrl(baseUrl)
                .build();
        if (serviceKey == null || serviceKey.isBlank()) {
            this.serviceHttp = null;
        } else {
            // mutate() берёт всё, что есть у клиента менеджера; добавляется только заголовок
            this.serviceHttp = http.mutate()
                    .defaultHeader(HttpHeaders.AUTHORIZATION, "Bearer " + serviceKey.strip())
                    .build();
        }
    }

    /** Есть ли служебный ключ. Нет — задания в систему клуба не ходят. */
    public boolean hasServiceKey() {
        return serviceHttp != null;
    }

    // ── задания по расписанию: пропуск — служебный ключ ──

    /** Абонементы, которые кончаются в ближайшие дни, — для ночного обхода продлений. */
    public String endingWithin(int days) {
        return serviceCall(service -> service.get()
                .uri("/club/memberships/ending?within-days={days}", days)
                .retrieve()
                .body(String.class));
    }

    /** Брони со сроком в окне — для опроса броней. */
    public String holdsWithin(int hours) {
        return serviceCall(service -> service.get()
                .uri("/club/holds?within-hours={hours}", hours)
                .retrieve()
                .body(String.class));
    }

    /** Посещения человека за месяц — для обхода предложений. */
    public String visits(UUID personId) {
        return serviceCall(service -> service.get()
                .uri("/club/people/{id}/visits", personId)
                .retrieve()
                .body(String.class));
    }

    // ── менеджер: пропуск — его кука ──

    /** Посещения человека за месяц — в карточку, которую открыл менеджер. */
    public String visits(String sessionCookie, UUID personId) {
        return http.get()
                .uri("/club/people/{id}/visits", personId)
                .header(HttpHeaders.COOKIE, "SESSION=" + sessionCookie)
                .retrieve()
                .body(String.class);
    }

    /** Абонемент человека — в карточку, которую открыл менеджер. */
    public String membership(String sessionCookie, UUID personId) {
        return http.get()
                .uri("/club/people/{id}/membership", personId)
                .header(HttpHeaders.COOKIE, "SESSION=" + sessionCookie)
                .retrieve()
                .body(String.class);
    }

    /** Единственный путь заданий в систему клуба: без ключа запрос не уходит, 401 — отдельной ошибкой. */
    private String serviceCall(Function<RestClient, String> request) {
        if (serviceHttp == null) {
            throw new ServiceKeyMissingException();
        }
        try {
            return request.apply(serviceHttp);
        } catch (HttpClientErrorException.Unauthorized e) {
            throw new ServiceKeyRejectedException(e);
        }
    }
}
```

```java
// src/main/java/example/crm/ServiceKeyMissingException.java
package example.crm;

/** Служебного ключа нет, а задание всё равно позвало систему клуба. Запрос не отправлен. */
public class ServiceKeyMissingException extends IllegalStateException {

    public ServiceKeyMissingException() {
        super("служебного ключа нет (CLUB_SERVICE_KEY): задания в систему клуба не ходят");
    }
}
```

```java
// src/main/java/example/crm/ServiceKeyRejectedException.java
package example.crm;

/** Система клуба ответила 401 на запрос задания: служебный ключ неверен или отозван. */
public class ServiceKeyRejectedException extends RuntimeException {

    public ServiceKeyRejectedException(Throwable cause) {
        super("система клуба не приняла служебный ключ (401) — проверь CLUB_SERVICE_KEY", cause);
    }
}
```

```java
// src/test/java/example/crm/ClubClientTest.java
package example.crm;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.function.Consumer;
import java.util.stream.Stream;

import com.sun.net.httpserver.Headers;
import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Named;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.MethodSource;
import org.junit.jupiter.params.provider.NullAndEmptySource;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestClient;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.junit.jupiter.api.Named.named;

/** С каким пропуском каждый метод ClubClient приходит в систему клуба: со служебным ключом или с кукой. */
class ClubClientTest {

    private static final String KEY = "test-service-key";
    private static final String SESSION = "manager-session";
    private static final UUID PERSON = UUID.fromString("00000000-0000-4000-8000-000000000001");

    private final List<Headers> received = new CopyOnWriteArrayList<>();
    private volatile int status = 204;   // чем отвечает сервер: по умолчанию 204, без тела
    private HttpServer server;
    private String baseUrl;

    @BeforeEach
    void startServer() throws IOException {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/", exchange -> {
            received.add(exchange.getRequestHeaders());
            exchange.sendResponseHeaders(status, -1);
            exchange.close();
        });
        server.start();
        baseUrl = "http://127.0.0.1:" + server.getAddress().getPort();
    }

    @AfterEach
    void stopServer() {
        server.stop(0);
    }

    private ClubClient client(String serviceKey) {
        return new ClubClient(RestClient.builder(), baseUrl, serviceKey);
    }

    /** Все вызовы заданий по расписанию. */
    static Stream<Named<Consumer<ClubClient>>> jobCalls() {
        return Stream.of(
                named("продления: endingWithin(days)", c -> c.endingWithin(14)),
                named("брони: holdsWithin(hours)", c -> c.holdsWithin(48)),
                named("предложения: visits(personId)", c -> c.visits(PERSON)));
    }

    /** Все вызовы менеджера. */
    static Stream<Named<Consumer<ClubClient>>> managerCalls() {
        return Stream.of(
                named("карточка: visits(cookie, personId)", c -> c.visits(SESSION, PERSON)),
                named("карточка: membership(cookie, personId)", c -> c.membership(SESSION, PERSON)));
    }

    private Headers onlyRequest() {
        assertThat(received).as("ровно один запрос в систему клуба").hasSize(1);
        return received.getFirst();
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("jobCalls")
    void jobCall_sendsServiceKeyAndNoCookie(Consumer<ClubClient> call) {
        call.accept(client(KEY));

        Headers headers = onlyRequest();
        assertThat(headers.getFirst("Authorization")).isEqualTo("Bearer " + KEY);
        assertThat(headers.get("Cookie")).isNull();
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("managerCalls")
    void managerCall_sendsCookieAndNoServiceKey(Consumer<ClubClient> call) {
        call.accept(client(KEY));

        Headers headers = onlyRequest();
        assertThat(headers.getFirst("Cookie")).isEqualTo("SESSION=" + SESSION);
        assertThat(headers.get("Authorization")).isNull();
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("jobCalls")
    void jobCall_withoutKey_failsBeforeNetwork(Consumer<ClubClient> call) {
        ClubClient client = client("");

        assertThatThrownBy(() -> call.accept(client))
                .isInstanceOf(ServiceKeyMissingException.class)
                .hasMessageContaining("CLUB_SERVICE_KEY");
        assertThat(received).as("запрос без пропуска не отправлен").isEmpty();
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("managerCalls")
    void managerCall_withoutKey_stillWorks(Consumer<ClubClient> call) {
        call.accept(client(""));

        assertThat(onlyRequest().getFirst("Cookie")).isEqualTo("SESSION=" + SESSION);
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("jobCalls")
    void jobCall_on401_saysKeyRejected(Consumer<ClubClient> call) {
        status = 401;
        ClubClient client = client(KEY);

        assertThatThrownBy(() -> call.accept(client))
                .isInstanceOf(ServiceKeyRejectedException.class)
                .hasMessageContaining("CLUB_SERVICE_KEY");
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("jobCalls")
    void jobCall_on404_staysNotFound(Consumer<ClubClient> call) {
        status = 404;
        ClubClient client = client(KEY);

        assertThatThrownBy(() -> call.accept(client))
                .isInstanceOf(HttpClientErrorException.NotFound.class);
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("managerCalls")
    void managerCall_on401_staysUnauthorized(Consumer<ClubClient> call) {
        status = 401;
        ClubClient client = client(KEY);

        assertThatThrownBy(() -> call.accept(client))
                .isInstanceOf(HttpClientErrorException.Unauthorized.class);
    }

    @ParameterizedTest(name = "ключ {0} — ключа нет")
    @NullAndEmptySource
    @ValueSource(strings = {"   "})
    void blankKey_meansNoKey(String serviceKey) {
        assertThat(client(serviceKey).hasServiceKey()).isFalse();
        assertThat(client(KEY).hasServiceKey()).isTrue();
    }
}
```

**Порядок проверки** — из папки песочницы:

1. `./mvnw test -Dtest=ClubClientTest` — 21 запуск, все зелёные:
   по три у четырёх тестов заданий, по два у трёх тестов менеджера,
   три строки «ключа нет». `./mvnw verify` — зелёный вместе с тестами
   прошлых статей; у сторожа статьи 11 по-прежнему 43 запуска: в папку
   журнала новые классы не попали;
2. что будет, если: без строки `defaultHeader` — красные три запуска
   `jobCall_sendsServiceKeyAndNoCookie`; клиент заданий собран из
   `builder` первым, а клиент менеджера — после — красные оба запуска
   `managerCall_sendsCookieAndNoServiceKey`: ключ прилип к менеджеру;
   без проверки `serviceHttp == null` в `serviceCall`, когда без ключа
   берут клиент менеджера, — красные три запуска
   `jobCall_withoutKey_failsBeforeNetwork`; без `catch` на `401` —
   красные три запуска `jobCall_on401_saysKeyRejected`;
3. открой отчёт теста в IDE: у каждой строки — имя из `named(…)`.
