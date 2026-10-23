# Первая ручка: как приложение отвечает по HTTP

> «От Java к Spring Boot» · статья 4 · читать минут 35
>
> **Для кого.** Ты прочитал статьи 0–3б, и в песочнице `game-day` журнал
> хранит происшествия в Postgres: сущность `Incident`, хранилище
> `IncidentRepository`, служба `IncidentLog`. HTTP знаешь на уровне
> «браузер открывает страницу».
>
> **Что будет.** Три вещи: HTTP и `curl` — запрос, ответ и как спросить
> самому; контроллер и JSON — как метод Java становится ручкой; ошибки
> и тест веб-слоя — как исключение становится ответом и как проверить
> ручку без базы, с заглушкой Mockito.
>
> **Откуда статья.** Раздел «Буткемп / Лаборатория» — о том, как пишут
> код команды Hammerhall: буткемп работает в открытых репозиториях,
> лаборатория — в закрытых. Серия «От Java к Spring Boot» — то, что
> нужно новичку до первой задачи на Spring Boot 4. Примеры — учебные:
> их можно повторить у себя.

---

## Зачем ручка

В статье 3б происшествия игрового дня легли в таблицу
`game_day.incident`. Но видит их только само приложение: тимлид,
дежурные, экран игры спросить не могут. Дать им пароль от базы? 🔴 Нет:
с паролем можно не только читать, но и стереть, а кто что читает —
не проверит никто.

Нужно окошко выдачи с правилами: спрашивают в условленной форме,
внутрь не пускают. Такое окошко — **ручка** (endpoint): адрес
в приложении, по которому задают один вид вопроса. Язык вопросов
и ответов — **HTTP**: на нём говорят и браузер, и любая программа.

В рабочем проекте ручки — частая задача джуна. Обычно рядом уже есть
ручка-образец, и новую пишут по ней: тем же способом, с той же формой
ошибок, с тем же набором тестов.

Сквозной пример — ручка `GET /game-day/incidents/{id}`: «покажи
происшествие по номеру».

---

## Часть 1. HTTP: самое нужное

### Запрос и ответ — это текст

Браузер, программа `curl` (о ней в конце части) и другие сервисы
посылают приложению **запрос** и получают **ответ**. И то и другое —
просто текст. Вот запрос к нашей ручке:

```
GET /game-day/incidents/7d1e3c52-9a4b-4f10-8c2d-1b2a3c4d5e6f HTTP/1.1
Host: localhost:8080
Accept: application/json
```

Первая строка — метод, путь и версия протокола (`HTTP/1.1`):

* **метод** HTTP (не путай с методом Java) — что сделать: `GET` —
  «дай», только чтение; `POST` — «прими и сделай»; `PUT` — «замени»;
  `DELETE` — «удали»;
* **путь** — что именно; номер происшествия сидит прямо в пути.

Дальше — **заголовки**, строки «имя: значение». `Host` говорит,
к какому серверу и порту идёт запрос: `localhost` — твоя же машина,
`8080` — порт, который слушает приложение. `Accept` — в каком виде хочу
ответ. Бывают и другие. Например, `Cookie` — **кука** (cookie): строка,
которую сервер выдал при входе; её прикладывают к каждому запросу, и по
ней узнают, кто спрашивает.

После пустой строки может идти **тело** — сами данные. У `GET` тела нет,
у `POST` и `PUT` там обычно JSON.

**Параметры запроса** — пары после `?`, через `&`:
`…/incidents?open=true&page=0`. Путь говорит, **что** спросили,
параметры — **как**: «только открытые, первая страница» (страницы
считают с нуля).

Ответ устроен так же:

```
HTTP/1.1 200
Content-Type: application/json

{"id":"7d1e3c52-9a4b-4f10-8c2d-1b2a3c4d5e6f","title":"Брокер не отвечает",
 "detectedAt":"2026-10-14T10:05:00Z","fixedAt":null,"dutyName":"duty-1"}
```

Первая строка — версия и **статус**: число-итог. Слово после числа
(`OK`) — пояснение для людей, его может и не быть: Tomcat, например,
его не пишет. Дальше заголовки: `Content-Type` — что в теле.

После пустой строки — тело. Приходит оно одной строкой, здесь разбито на две,
чтобы влезло. Порядок полей в нём у тебя может быть другим — для JSON
он неважен.

### Статусы

Первая цифра статуса — семейство: **2xx** — получилось; **4xx** —
ошибся спрашивающий, повтор без изменений получит тот же отказ;
**5xx** — сломалось у сервера. Чаще всего встретятся такие:

| статус | что значит |
|---|---|
| `200 OK` | вот ответ |
| `202 Accepted` | принял, сделаю позже |
| `400 Bad Request` | запрос негодный: кривой номер, страница `-1` |
| `401 Unauthorized` | не знаю, кто ты: не вошёл |
| `403 Forbidden` | знаю, кто ты, но тебе нельзя |
| `404 Not Found` | такого нет |
| `409 Conflict` | противоречит тому, что уже есть |
| `500 Internal Server Error` | сломалось у сервера |

⚠️ `401` называется Unauthorized — «не разрешено», а значит «не вошёл».
«Вошёл, но нельзя» — это `403`.

Отказ по роли иногда отдают и как `404`: так чужому не подсказывают,
что дверь вообще есть.

### JSON

JSON (статья 0) — текстовый формат обмена между программами:

* `{ … }` — **объект**: пары `"имя": значение` через запятую; `[ … ]` —
  **массив**, список значений;
* строки — в двойных кавычках, числа и `true`/`false` — без;
* `null` — «значения нет»: происшествие не починили, `fixedAt` пуст;
* `UUID` и время — строками: `"2026-10-14T10:05:00Z"` — формат ISO 8601,
  `Z` значит «по UTC». Так Jackson пишет любой `Instant`.

### Путь — как адрес в каталоге

Путь читают слева направо, от общего к частному: `/game-day` — игровой
день, `/incidents` — его происшествия, `/{id}` — одно из них. Список
всех происшествий жил бы на `/game-day/incidents`, одно происшествие —
на `/game-day/incidents/<номер>`. Имена — существительные во
множественном числе, маленькими латинскими буквами, слова через дефис.
Что сделать, говорит метод, а не путь: не `/getIncident`, а `GET`.

💡 В рабочих проектах путь часто начинают ещё и с версии договора
с клиентами — `/v1/…`. Несовместимая правка ответа — уже `/v2/…`,
а старые клиенты остаются на `v1`. Клиент песочницы — ты сам, и версии
в её путях нет.

### curl — запрос своими руками

**curl** — программа командной строки: посылает HTTP-запрос и печатает
ответ. Браузер для проверки ручек слаб: из адресной строки уходит только
`GET`, а статус и заголовки он прячет. В рабочем проекте ручку проверяют
`curl` на стенде, а вывод вставляют в пул-реквест. curl уже есть в Git
Bash, macOS и Linux.

```bash
curl -i http://localhost:8080/game-day/incidents/7d1e3c52-9a4b-4f10-8c2d-1b2a3c4d5e6f
```

`-i` — печатать статус и заголовки, а не только тело. Ручки пока нет:
запрос ты отправишь в конце части 3, когда журнал научится отвечать.

⚠️ Каждую команду — одной строкой: в Git Bash многострочные вставки
слипаются. В Windows PowerShell `curl` — другая команда с тем же
именем: пиши `curl.exe` или работай в Git Bash.

---

## Часть 2. Контроллер

### Spring MVC и стартер веба

Tomcat (веб-сервер внутри приложения, статья 2) отдаёт запрос программе
как есть. Без помощи на каждую ручку пришлось бы самому сверять метод
и путь, вырезать номер, собирать JSON по буквам. Эту работу делает
**Spring MVC** — часть Spring, которая раздаёт HTTP-запросы методам
твоих классов.

Spring MVC, Tomcat и Jackson приносит стартер `spring-boot-starter-webmvc`
из таблицы статьи 2. Добавь его в `pom.xml` песочницы:

```xml
<dependency>                                <!-- веб: Spring MVC, Tomcat, Jackson -->
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-webmvc</artifactId>
</dependency>
```

Версию подставляет `<parent>`. Старое имя из интернета,
`spring-boot-starter-web`, в Boot 4 устарело (та же таблица).

### Контроллер: метод становится ручкой

**Контроллер** — бин, методы которого отвечают на HTTP-запросы. Один
метод — одна ручка.

```java
@RestController                                       // контроллер; что вернёт метод — то и тело ответа
public class IncidentController {

    private final IncidentService service;            // служба (ниже) — через конструктор, как в статье 1

    public IncidentController(IncidentService service) {
        this.service = service;
    }

    @GetMapping("/game-day/incidents/{id}")           // GET на этот путь; {id} — меняющийся кусок
    public IncidentResponse get(@PathVariable("id") String id) {   // кусок {id} — в параметр id
        UUID incidentId = IncidentIds.parse(id);      // строка → UUID или ошибка 400 (ниже)
        return service.get(incidentId);               // ответ — запись IncidentResponse (ниже)
    }
}
```

* `@RestController` — «контроллер; что возвращают методы — тело
  ответа». Spring найдёт его при сканировании компонентов, как `@Service`;
* `@GetMapping("…")` — «зови метод на `GET` по такому пути»; `{id}` —
  **переменная пути**, на её месте может стоять что угодно;
* `@PathVariable("id")` — «положи кусок `{id}` в этот параметр». Имя
  пишут явно: так ручка не зависит от того, сохранил ли компилятор имена
  параметров.

Строк `import` в коротких примерах, как и раньше, нет — полные файлы
в конце статьи. Контроллер и всё, что ему нужно, живут в пакете журнала
`example.gameday.journal`.

### Параметры запроса: @RequestParam

У нашей ручки параметров нет, у списка будут. Их достаёт `@RequestParam`:

```java
@RequestParam(name = "open", required = false) Boolean open    // ?open=true → true; параметра нет → null
```

`Boolean` — обёртка: в отличие от `boolean`, может быть `null`. Без
`required = false` запрос без параметра отвергнет сам Spring, статусом
`400`. Но форма ответа будет не та, в какой отвечают наши ошибки
(о ней в части 3).
Так же Spring ответит на `?open=abc`: `abc` — не `Boolean`. Поэтому
в рабочем проекте такие параметры, как номер страницы, делают
необязательными и проверяют своим кодом — с ответом в общей форме.

### Ответ — запись, JSON делает Jackson

```java
public record IncidentResponse(UUID id, String title, Instant detectedAt,
                               Instant fixedAt, String dutyName) {        // fixedAt может быть null

    public static IncidentResponse of(Incident incident) {               // фабричный метод (статья 0)
        return new IncidentResponse(incident.getId(), incident.getTitle(),
                incident.getDetectedAt(), incident.getFixedAt(), incident.getDutyName());
    }
}
```

Метод контроллера вернул запись — Spring отдаёт её Jackson из статей 0
и 2 со статусом `200`. Jackson пишет JSON
без аннотаций: поле записи — поле JSON, `UUID` и `Instant` — строки,
`null` — `null`.

⚠️ В интернете для дат подключают `jackson-datatype-jsr310` — это
Jackson 2; в Jackson 3 даты встроены. Аннотации переехали не все:
`@JsonProperty` из `jackson-annotations` осталась
в `com.fasterxml.jackson.annotation`, а `@JsonSerialize` — уже
в `tools.jackson.databind.annotation`.

**Почему запись, а не сущность `Incident`.** Сущность повторяет
таблицу: переименовали столбец — молча сломался экран; и в ней бывает
то, что наружу нельзя. Ответ — договор с клиентами, он меняется
отдельно от таблицы. Подробнее — дальше в серии.

### Служба: откуда контроллер берёт данные

Контроллер знает HTTP, а данные достаёт служба — бин с `@Service`, как
`IncidentLog` в статье 3б. Служба держит данные и правила; её можно
позвать не только из ручки и проверить без веба. `IncidentLog`
записывает и оповещает, а показывает отдельная `IncidentService`.
Почему она отдаёт уже `IncidentResponse`, а не сущность, — дальше
в серии.

```java
@Service
@Transactional(readOnly = true)                       // на все методы класса; только чтение (ниже)
public class IncidentService {

    private final IncidentRepository repository;      // хранилище из статьи 3б

    public IncidentService(IncidentRepository repository) {
        this.repository = repository;
    }

    public IncidentResponse get(UUID id) {
        // есть происшествие — или исключение «такого нет» (часть 3)
        Incident incident = repository.findById(id)
                .orElseThrow(() -> new NoSuchEntryException("incident_not_found", "Происшествие не найдено"));
        return IncidentResponse.of(incident);
    }
}
```

`@Transactional` на классе действует на все его публичные методы.
`readOnly = true` — подсказка: транзакция только читает, и Hibernate
может не следить за изменениями прочитанных объектов (контекст
постоянства, статья 3б). Шаг здесь один, но службы чтения в рабочем
проекте помечают так целиком.

⚠️ Импорт — Spring-овый (статья 3б). Здесь это уже не вопрос стиля:
у `jakarta.transaction.Transactional` атрибута `readOnly` нет вовсе,
и код не скомпилируется.

`findById(…).orElseThrow(…)` — как в `fixAll` из статьи 3б: нет
происшествия — исключение. Только не `IllegalArgumentException`,
а своё, `NoSuchEntryException`, с кодом и текстом. Что с ним дальше —
часть 3.

### Кривой номер в пути — 400

Параметр можно объявить сразу `UUID`, и Spring разберёт строку сам.
Мы так не делаем, и причин две. Первая: на мусор вроде `abc` тогда
ответит не наш код, а сам Spring — `400` в своей форме, без нашего кода
ошибки.

Вторая: разбор у Spring нестрогий. Он зовёт `UUID.fromString`,
а тот принимает и `1-1-1-1-1` — дописывает нули и получает
`00000001-0001-0001-0001-000000000001`. Запрос с мусором дошёл бы
до службы и получил «не найдено» вместо «это не номер».

Поэтому номер берут строкой и разбирают строго — в маленьком классе
рядом с контроллером:

```java
public final class IncidentIds {                      // final — наследники не нужны

    private IncidentIds() {                           // объекты не нужны — только метод
    }

    public static UUID parse(String raw) {
        try {
            UUID id = UUID.fromString(raw);           // нестрогий разбор: 1-1-1-1-1 тоже пройдёт
            if (id.toString().equals(raw)) {          // строгая проверка: обратно в строку — та же строка
                return id;
            }
        } catch (IllegalArgumentException e) {
            // совсем не UUID — ответ тот же, что ниже
        }
        throw new InvalidInputException("incident_id_invalid", "Это не номер происшествия");
    }
}
```

`UUID.toString()` пишет номер всегда одинаково: 36 знаков по схеме
`8-4-4-4-12`, строчные буквы. Совпало с присланным — номер честный.
`1-1-1-1-1` превратился в другую строку — значит, `400`. Номер
заглавными буквами — тоже `400`: так Java номер не пишет. Это выбор
журнала: правило «как пишет сама Java» короче всех.

Текст `IllegalArgumentException` из `fromString` повторяет присланное:
`Invalid UUID string:
abc`. Поэтому наружу он не идёт, у нашего исключения свой текст.
Почему это важно — в части 3. `InvalidInputException` — второе своё
исключение, «на входе негодное»; о нём — там же.

У ручек «по номеру» в рабочем проекте одна форма: номер строкой, строгий
разбор, `400` на мусор. Сама задача обычно не в разборе номера, а в том,
что ручка достаёт.

### Кого пускают

Сейчас ручку журнала может позвать любой, кто достучался до порта 8080.
В рабочем проекте так нельзя: вход — по куке, а у человека есть
**роли**, скажем `admin` и `viewer`. Это роль человека, а не роль базы
из статьи 3а: слово то же, вещь другая. Ручку журнала звал бы только
`admin`. Вход и доступ по ролям — дальше в серии; в этой статье ручка
открыта всем.

---

## Часть 3. Ошибки

### Ручка не ловит ошибки — она их бросает

Представь, что каждый контроллер сам ловит ошибки и собирает ответ.
Десять ручек — десять копий `try/catch`: в одной забыли код ошибки,
в другой текст по-английски, в третьей `200` с ошибкой в теле. Клиент
уже не может положиться ни на статус, ни на форму.

🔑 **Код бросает исключение, а в ответ его превращает одно общее
место — обработчик ошибок.**

В песочнице для этого четыре класса. Они общие для всего приложения
и лежат в корне пакетов, `example.gameday`, — как запись настроек
`GameDayProperties`.

Первые два — исключения: `NoSuchEntryException` — «такого нет»
и `InvalidInputException` — «на входе негодное». Оба непроверяемые,
как все ошибки рабочего проекта (статьи 0 и 3б). Каждое несёт **код**,
например `incident_not_found`, и **текст** для человека:

```java
public class NoSuchEntryException extends RuntimeException {

    private final String code;                        // для машины: incident_not_found

    public NoSuchEntryException(String code, String message) {
        super(message);                               // текст для человека — его вернёт getMessage()
        this.code = code;
    }

    public String getCode() {
        return code;
    }
}
```

`InvalidInputException` устроено так же — целиком в конце статьи.

Статус выбирает обработчик: «такого нет» — `404`, «негодное» — `400`.
Исключение говорит, что случилось, а как сказать это по HTTP — дело
веба: службу зовут и оттуда, где HTTP нет, — из `main`, из другой
службы, из задачи по расписанию.

Третий класс — тело ответа об ошибке, одна форма на все ручки:

```java
public record ErrorBody(String code, String message) {
}
```

Четвёртый — сам обработчик, о нём ниже. Всё непредвиденное он отдаёт
как `500` с кодом `unexpected_error` и без подробностей: устройство
приложения чужим знать незачем.

У двух полей ответа два читателя. `code` — для **машины**: по нему
ветвится код клиента. `message` — для **человека**: одна фраза
по-русски, без того, что прислал клиент. Клиент это и так знает.
А присланное может быть чем угодно, хоть длинной строкой, хоть
переводом строки, и попало бы в ответ и в лог (статья 2).

Третий читатель — тот, кто ищет запрос в логе; о нём — ниже,
в «Номере запроса».

### Как обработчик находит исключение

Исключение из службы летит вверх через контроллер, никто его не ловит.
Его подхватывает Spring MVC и ищет, кто с ним умеет обращаться:

```
GET /game-day/incidents/7d1e…
    IncidentController.get
        IncidentService.get → throw NoSuchEntryException("incident_not_found", …)
    ↑ никто не ловит
Spring MVC: есть ли @ExceptionHandler для NoSuchEntryException?
    → ErrorHandler.noSuchEntry
    → 404 {"code":"incident_not_found","message":"Происшествие не найдено"}
```

Обработчик — обычный бин с двумя аннотациями:

```java
@RestControllerAdvice                                 // советник всех контроллеров приложения
public class ErrorHandler {

    @ExceptionHandler(NoSuchEntryException.class)     // «вылетело NoSuchEntryException — зови меня»
    public ResponseEntity<ErrorBody> noSuchEntry(NoSuchEntryException e) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND)             // статус 404
                .body(new ErrorBody(e.getCode(), e.getMessage()));     // тело — общая форма
    }

    @ExceptionHandler(InvalidInputException.class)
    public ResponseEntity<ErrorBody> invalidInput(InvalidInputException e) {
        return ResponseEntity.status(HttpStatus.BAD_REQUEST)           // статус 400
                .body(new ErrorBody(e.getCode(), e.getMessage()));
    }
    …
}
```

* `@RestControllerAdvice` — «этот бин помогает всем контроллерам
  сразу»; что вернёт его метод — то и ответ, как у `@RestController`.
  Бин Spring находит сам: это тоже компонент, его видит сканирование
  из статьи 2;
* `@ExceptionHandler(…)` — «если из любого контроллера вылетело такое
  исключение, вызови меня вместо обычного ответа»;
* `ResponseEntity` — ответ целиком: Spring возьмёт из него статус,
  заголовки и тело (в угловых скобках — тип тела, как в `List<String>`).
  `HttpStatus` — перечисление статусов Spring: `NOT_FOUND` — это `404`.

### Непредвиденное — 500

Третий метод обработчика ловит всё остальное:

```java
    @ExceptionHandler(Exception.class)                // всё, для чего нет метода точнее
    public ResponseEntity<ErrorBody> unexpected(Exception e) throws Exception {
        if (e instanceof ErrorResponse || e instanceof TypeMismatchException) {
            throw e;                                  // ошибка самого Spring MVC — пусть отвечает Spring
        }
        logger.error("Непредвиденная ошибка", e);     // в лог — всё, со стеком вызовов
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)        // клиенту — без подробностей
                .body(new ErrorBody("unexpected_error", "Непредвиденная ошибка"));
    }
```

Читай по порядку.

* `Exception.class` подходит к любому исключению. Из нескольких
  подходящих методов Spring выбирает тот, чей тип **ближе** всего:
  для `NoSuchEntryException` есть свой метод — позовут его. Сюда
  попадает то, что не узнал никто: `NullPointerException`, упавшая база,
  ошибка в нашем коде.
* Spring MVC и сам бросает исключения: такого адреса нет, метод не тот,
  обязательного параметра нет, `?open=abc`. Свой статус у них Spring
  знает и отдаёт его сам, если ему не мешать. Почти все они помечены
  интерфейсом `ErrorResponse` из `org.springframework.web` — «знаю свой
  HTTP-статус» (не путай с нашим `ErrorBody`). Из тех, что встретятся
  ручке на чтение, без метки только ошибка перевода параметра в нужный
  тип, `TypeMismatchException`.
  `throw e` — «это не моё»: Spring передаст исключение дальше, своему
  обработчику, будто нашего метода и нет. Без этого `if` запрос
  на несуществующий адрес получил бы не `404`, а `500` — «сломалось
  у нас».
* Клиенту — только код и общая фраза, а подробности — в **лог**
  приложения, со стеком вызовов: по ним и чинят.

`logger` — поле класса:

```java
    private static final Logger logger = LoggerFactory.getLogger(ErrorHandler.class);
```

**SLF4J** — библиотека, через которую код пишет в лог; `Logger`
и `LoggerFactory` — её классы. Зачем она, если есть `System.out`
из статьи 1? Строка в консоли не скажет, когда, где и насколько это
серьёзно, а строка лога скажет: время, **уровень** (`ERROR` — сломалось,
`WARN` — подозрительно, `INFO` — к сведению) и имя класса. Ставить её
не нужно: она приезжает с любым стартером Boot, а строки за неё
печатает Logback — та же библиотека, что печатает лог запуска. Где
смотреть — там же, в консоли, рядом со строками Boot.
`getLogger(ErrorHandler.class)` —
лог от имени этого класса; `logger.error(текст, e)` — строка уровня
`ERROR`, а под ней стек исключения.

Что будет, если служба бросит простое `RuntimeException("не найдено")`?
Обработчик не узнает в нём «такого нет». Клиент получит
`500 unexpected_error`, то есть «сломалось у нас» вместо «такого нет».
А в логе появится строка `ERROR`, на которую кто-то потратит утро.

💡 Список в `if` — для этой статьи: ручка только читает. У ручек,
которые принимают тело, своих ошибок у Spring больше — скажем, негодный
JSON в теле запроса. В рабочем проекте общий обработчик пишут один раз
на всё приложение, обычно это работа мидла; он знает все ошибки Spring
и отвечает на них в той же форме, что и на свои. В песочнице ошибки
Spring приходят в его собственной форме — это её упрощение.

### Номер запроса: X-Request-Id

В рабочем проекте у каждого запроса есть номер. Приложение выдаёт его
каждому запросу или берёт присланный в заголовке `X-Request-Id`.
Возвращает номер в том же заголовке ответа и третьим полем тела
ошибки, `requestId`. Тот же номер стоит в каждой строке лога по этому
запросу.

Человек пишет «у меня ошибка, номер 8c1f…» — и в логе находят путь
именно этого запроса среди тысяч других. В песочнице номера нет:
клиент один, лог короткий.

⚠️ Частая ошибка — ждать от Spring ответов об ошибке в форме
`ProblemDetail` (поля `type`, `title`, `status`, `detail`): советы
в интернете уверяют, будто он отдаёт их сам. В Boot 4.1 для ошибок
Spring MVC эта форма по умолчанию выключена
(`spring.mvc.problemdetails.enabled=false`).
А в песочнице, как и в рабочем проекте, форма своя: клиенты ждут поле
`code`. Не включай.

### Проверь руками: curl

Собери и запусти песочницу, как в статье 3б: Postgres в контейнере,
три переменные `SPRING_DATASOURCE_*` и

```bash
./mvnw package
java -jar target/game-day-0.0.1-SNAPSHOT.jar
```

`./mvnw package` прогонит и тесты на базе — Docker у тебя запущен.
В логе новое — строка Tomcat:

```
Tomcat started on port 8080 (http) with context path '/'
```

И главное: приложение больше не завершается. В статье 3б оно
записывало происшествие и выходило — ждать было некого. Теперь в нём
Tomcat, и он ждёт запросов, пока приложение не остановишь: `Ctrl+C`
в консоли или красный квадрат в IDE. На месте и строки из `main`:
`[оповещение] …` и `игра PT3H, атакующих 2`. Каждый запуск
по-прежнему записывает в журнал «Брокер не отвечает».

Номер происшествия возьми из базы — в другом окне консоли:

```bash
docker exec game-day-db psql -U postgres -c "SELECT id, title FROM game_day.incident"
```

`-c` — выполнить одну команду и выйти; печатать в `psql` не нужно,
поэтому и `-it` не нужен.

```
                  id                  |       title
--------------------------------------+--------------------
 5b0c7a52-6f1e-4c2a-9d4e-0f5a1b2c3d4e | Брокер не отвечает
(1 row)
```

Строк может быть больше: каждый запуск добавляет одну. Номер у тебя
свой. Спроси ручку:

```bash
curl -i http://localhost:8080/game-day/incidents/5b0c7a52-6f1e-4c2a-9d4e-0f5a1b2c3d4e
```

```
HTTP/1.1 200
Content-Type: application/json
…

{"id":"5b0c7a52-6f1e-4c2a-9d4e-0f5a1b2c3d4e","title":"Брокер не отвечает",
 "detectedAt":"2026-10-20T09:15:03.512704Z","fixedAt":null,"dutyName":"duty-1"}
```

`…` — ещё пара служебных заголовков, например `Date`. `detectedAt`
пришёл с долями секунды: часы записали момент точно, а `TIMESTAMPTZ`
хранит его до микросекунды (статья 3б).

Теперь номер, которого в журнале нет, и мусор вместо номера:

```bash
curl -i http://localhost:8080/game-day/incidents/7d1e3c52-9a4b-4f10-8c2d-1b2a3c4d5e6f
curl -i http://localhost:8080/game-day/incidents/1-1-1-1-1
```

```
HTTP/1.1 404
Content-Type: application/json
…

{"code":"incident_not_found","message":"Происшествие не найдено"}
```

На второй запрос — `400` и
`{"code":"incident_id_invalid","message":"Это не номер происшествия"}`:
до службы дело не дошло.

И адрес, которого нет вовсе:

```bash
curl -i http://localhost:8080/game-day/nothing
```

```
HTTP/1.1 404
Content-Type: application/json
…

{"timestamp":"…","status":404,"error":"Not Found","path":"/game-day/nothing"}
```

Это ответил сам Spring: наш обработчик бросил его ошибку дальше. Статус
верный, а форма — та, что собирает Boot, без `code`.

Загляни в лог приложения. Строк `ERROR` нет ни одной: ни `404`, ни `400`
непредвиденными не считаются. О своём `404` Spring оставил строку
уровня `WARN` с `NoResourceFoundException` — «такого адреса нет».

А ещё при старте появилось предупреждение
`spring.jpa.open-in-view is enabled by default`. С вебом Boot держит
контекст постоянства (статья 3б) открытым весь запрос, до самого ответа.
Нашей ручке это не мешает: ответ собирается в службе, внутри транзакции.
Разбирать эту настройку здесь не будем — пока не трогай.

Посмотрел — останови приложение, `Ctrl+C`. Базу можно не гасить.

---

## Часть 4. Тест веб-слоя

### Срез: веб без базы

`curl` — руками и не на каждой сборке. Тест со всем приложением и базой
(`*IT`, статья 3а) долгий и падает не только из-за ручки. А проверить
надо путь, разбор номера, статус, JSON и ошибки. Для этого есть
**срез** (помнишь, статья 2: тест, который поднимает один слой) — как
двигатель на испытательном стенде, без машины.

**`@WebMvcTest`** — аннотация Boot для среза веба. Поднимает Spring MVC,
Jackson, указанный контроллер и советников вроде обработчика ошибок —
ни служб, ни хранилищ, ни базы; без контроллера в скобках поднялись бы
все. Базы нет, поэтому тест зовут `*Test`, а не `*IT`: граница — база
(статья 3а).

Приносит срез свой тестовый стартер:

```xml
<dependency>                                <!-- срез веба: @WebMvcTest, MockMvcTester -->
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-webmvc-test</artifactId>
    <scope>test</scope>
</dependency>
```

⚠️ В интернете `@WebMvcTest` — из пакета
`org.springframework.boot.test.autoconfigure.web.servlet`, прямо
в `spring-boot-starter-test`. Это Boot 2–3. В Boot 4 у него свой
тестовый стартер `spring-boot-starter-webmvc-test` (статья 2) и пакет
`org.springframework.boot.webmvc.test.autoconfigure`.

💡 Срез берёт за основу `GameDayApplication` со всеми его аннотациями,
но сканирование сужает. `GameDayConfig` с часами и дежурным в срез
не попадает: классы `@Configuration` срез пропускает. Нет в нём
и записи настроек: `@ConfigurationPropertiesScan` на классе приложения
слушается того же фильтра, и `GameDayProperties` срез не создаёт.
Поставь `attackers: 0` — приложение не стартует, а срез останется
зелёным. Понадобится запись контроллеру — добавь к тесту
`@EnableConfigurationProperties(GameDayProperties.class)` (статья 2):
тогда Boot заполнит её из `application.yml` и проверит `@Validated`,
как при старте приложения.

### Заглушка: Mockito и @MockitoBean

В срезе нет службы, а контроллеру она нужна. Нужна **заглушка** —
помнишь `RememberingNotifier` из статьи 1? Это объект, который в тесте
стоит вместо настоящего. Руками её писать долго: класс на каждую
зависимость, а у `IncidentService` и интерфейса нет. Для хранилища
в статье 3б не вышло вовсе — в `JpaRepository` десятки методов.

**Mockito** — библиотека, которая делает заглушку одной строкой из
любого класса или интерфейса. В курсах её нет, на работе — почти
в каждом тесте службы или ручки. Ставить не нужно: она входит
в `spring-boot-starter-test`. Работает внутри теста: велишь заглушке,
что отвечать, потом проверяешь, как её звали; позвали не так — тест
падает и пишет, какой вызов ждали.

* `when(service.get(ID)).thenReturn(ответ)` — «когда спросят
  `get(ID)`, верни вот это». Внутри `when(…)` метод заглушки вызывается
  понарошку: Mockito запоминает, какой вызов настраивают, и вернёт
  ответ, когда так позовёт контроллер;
* `when(…).thenThrow(исключение)` — «…брось вот это»;
* `verifyNoInteractions(service)` — «заглушку не звали ни разу».

`when` и `verifyNoInteractions` — статические методы класса `Mockito`,
в тест их подключают `import static`. Без `when` заглушка на `get(ID)`
ответит `null`. В документации Boot встретишь `given(…).willReturn(…)`
из `BDDMockito` — то же самое, другая запись.

**`@MockitoBean`** — аннотация над полем теста: «положи в контекст
Spring заглушку этого типа и дай её мне». Есть в контексте настоящий
бин такого типа — заглушка его заменит. Контроллер получит её через
конструктор, как настоящую службу.

Второй бин часов в статье 3б не прошёл: подменять бины Boot не разрешает.
`@MockitoBean` — разрешённый способ подмены, только для тестов. В тесте
журнала на базе поле `@MockitoBean private Clock clock;` встанет на место
бина `clock`, а `when(clock.instant()).thenReturn(T0)` остановит для
журнала время. Только заводи такой тест отдельным классом: заглушка
действует на весь класс. Без `when` часы-заглушка отвечают `null`,
и в тестах, которые на это не рассчитывали, `fixAll` упадёт
с `NullPointerException`.

⚠️ В интернете ты увидишь `@MockBean`. Это Boot 2–3; в Boot 4.0 его
удалили. В Boot 4 — `@MockitoBean` из
`org.springframework.test.context.bean.override.mockito`.

### MockMvcTester: запрос без сети

**MockMvc** — инструмент Spring для тестов веба: отправляет запрос прямо
в Spring MVC, без Tomcat и сети. **`MockMvcTester`** — он же
с проверками в стиле AssertJ (статья 0); `@WebMvcTest` заводит его
бином сам. Тестовый класс создаёт JUnit, поэтому бин в тест просят
полем с `@Autowired`, как в тестах статьи 3а.

### Тест по таблице

| случай | запрос | заглушка службы | ждём |
|---|---|---|---|
| есть такое | `…/incidents/7d1e…` | отдаёт ответ | `200`, JSON целиком |
| нет такого | `…/incidents/7d1e…` | бросает `NoSuchEntryException` | `404`, `code` — `incident_not_found` |
| кривой номер | `…/abc`, `…/1-1-1-1-1` | не вызвана | `400`, `code` — `incident_id_invalid` |

```java
@WebMvcTest(IncidentController.class)                 // поднять только веб и этот контроллер
class IncidentControllerTest {

    private static final String PATH = "/game-day/incidents/{id}";
    private static final UUID ID = UUID.fromString("7d1e3c52-9a4b-4f10-8c2d-1b2a3c4d5e6f");

    @Autowired
    private MockMvcTester mvc;                        // запросы без сети, проверки AssertJ

    @MockitoBean
    private IncidentService service;                  // заглушка вместо настоящей службы

    @Test
    void returnsIncident() {
        when(service.get(ID)).thenReturn(new IncidentResponse(ID, "Брокер не отвечает",
                Instant.parse("2026-10-14T10:05:00Z"), null, "duty-1"));

        assertThat(mvc.get().uri(PATH, ID))           // GET …/incidents/7d1e…; {id} ← ID
                .hasStatusOk()                        // 200
                .bodyJson().isStrictlyEqualTo("""
                        {"id": "7d1e3c52-9a4b-4f10-8c2d-1b2a3c4d5e6f",
                         "title": "Брокер не отвечает",
                         "detectedAt": "2026-10-14T10:05:00Z",
                         "fixedAt": null,
                         "dutyName": "duty-1"}
                        """);                         // JSON целиком, без лишних полей
    }

    @Test
    void unknownIncidentIs404() {
        when(service.get(ID))
                .thenThrow(new NoSuchEntryException("incident_not_found", "Происшествие не найдено"));

        assertThat(mvc.get().uri(PATH, ID))
                .hasStatus(HttpStatus.NOT_FOUND)
                .bodyJson().extractingPath("$.code").isEqualTo("incident_not_found");
    }

    @ParameterizedTest(name = "{0} → 400")
    @ValueSource(strings = {"abc", "1-1-1-1-1"})
    void badIdIs400(String badId) {
        assertThat(mvc.get().uri(PATH, badId))
                .hasStatus(HttpStatus.BAD_REQUEST)
                .bodyJson().extractingPath("$.code").isEqualTo("incident_id_invalid");
        verifyNoInteractions(service);                // до службы дело не дошло
    }
}
```

* `mvc.get().uri(PATH, ID)` — запрос `GET`, на место `{id}` встанет
  `ID`; `assertThat(…)` выполнит его и даст проверки ответа;
* `bodyJson().isStrictlyEqualTo("""…""")` — JSON целиком: порядок полей
  не важен, но лишнего поля быть не должно — утечёт что-то из сущности,
  тест заметит. `"fixedAt": null` тоже проверка: поле есть, значения нет;
* `extractingPath("$.code")` — одно поле: `$` — весь JSON, `.code` —
  поле `code`. Текст у ошибки может поменяться, а машине важен код —
  его и сверяем;
* `verifyNoInteractions` — номер отвергнут **до** работы с данными.
  Упал этот тест — значит, до службы дело дошло: номер проверяют
  не в контроллере.

🔑 **Срез проверяет веб, заглушка отвечает за остальное.** Тест `404`
не трогает хранилище: заглушка бросает исключение, тест проверяет путь
«исключение → обработчик → `ErrorBody`». Что служба сама бросает
`NoSuchEntryException`, — дело её теста без Spring, дальше в серии.

Здесь — приём, а не полный набор: в рабочем проекте случаи для теста ручки
перечисляет таблица в тексте задачи — каждую строку.

**Запуск.** `./mvnw verify` прогонит все тесты, и тесты на базе тоже —
для них нужен запущенный Docker (статья 3а). Только срез запускают
командой `./mvnw test -Dtest=IncidentControllerTest`, где `-Dtest=`
значит «только этот класс», или треугольником в IDE. Docker срезу
не нужен: базы в нём нет.

⚠️ Тест и живое приложение могут ответить по-разному. Ошибки, на которые
Spring отвечает сам, в MockMvc видны только статусом. Это, скажем,
неизвестный адрес или не тот метод. Тело для них собирает служебный
адрес `/error`, а MockMvc до него не доходит. Поэтому в срезе
такие ответы проверяют статусом, а тело — `curl` на запущенном
приложении.

Есть и третий случай, `hasFailed()`, — исключение, которое
не поймал никто. С обработчиком песочницы до него не доходит: всё, что
не узнал Spring, становится `500`.

---

## Проверь себя

Ответь своими словами — вслух или на бумаге. Не получается — перечитай
раздел.

1. Из чего состоят HTTP-запрос и ответ? Где в запросе номер
   происшествия, а где было бы «только открытые»?
2. Чем `401` отличается от `403`? Почему отказ по роли иногда отдают
   как `404`?
3. Почему ручка отдаёт `IncidentResponse`, а не сущность `Incident`?
4. Почему номер из пути принимают строкой, а не сразу `UUID`? Что
   `UUID.fromString` сделает с `1-1-1-1-1` и как `IncidentIds` это
   замечает?
5. Служба бросила `NoSuchEntryException`. Кто ловит исключение, кто
   выбирает статус и почему не само исключение?
6. Обработчик ловит `Exception`. Зачем ему `if` с `throw e` и что было бы
   без него? Почему клиенту — общая фраза, а подробности — в лог?
7. Зачем срез `@WebMvcTest`, если можно поднять всё приложение? Почему
   он `*Test`, а не `*IT`, и чего в нём нет?
8. Чем заглушка Mockito отличается от той, что ты писал руками
   в статье 1? Что на самом деле происходит с вызовом внутри `when(…)`?

---

## Что дальше

Дальше в серии — ручка целиком: список происшествий со страницами,
доступ по ролям и тесты всех слоёв, в том числе тест службы без Spring.

## Первоисточники

* [MDN: An overview of HTTP](https://developer.mozilla.org/en-US/docs/Web/HTTP/Overview) —
  запрос, ответ, заголовки и статусы;
* [RFC 9110: HTTP Semantics](https://www.rfc-editor.org/rfc/rfc9110.html) —
  сам стандарт HTTP; читать выборочно: методы — раздел 9, статусы —
  раздел 15;
* [Spring Framework: Exceptions](https://docs.spring.io/spring-framework/reference/web/webmvc/mvc-controller/ann-exceptionhandler.html) —
  `@ExceptionHandler`: как выбирается метод и что значит бросить
  исключение дальше;
* [Spring Boot: Testing Spring Boot Applications](https://docs.spring.io/spring-boot/reference/testing/spring-boot-applications.html) —
  `@WebMvcTest`, что попадает в срез, `@MockitoBean` в деле;
* [Spring Framework: MockMvc — AssertJ Integration](https://docs.spring.io/spring-framework/reference/testing/mockmvc/assertj.html) —
  все проверки `MockMvcTester`;
* [Spring Framework: @MockitoBean and @MockitoSpyBean](https://docs.spring.io/spring-framework/reference/testing/annotations/integration-spring/annotation-mockitobean.html) —
  как заглушка встаёт на место бина.

---

## Пример целиком — с импортами

Учебный пример. Запускай в песочнице `game-day` после статьи 3б: всё,
что в ней есть, остаётся без изменений — `GameDayApplication`,
`GameDayProperties` с тестом, `application.yml` и `application-stand.yml`,
миграция `V1__game_day_incident.sql`, `TestcontainersConfiguration`,
журнал в `example.gameday.journal` (`Incident`, `IncidentRepository`,
`IncidentLog`, `DutyRoster`, `Notifier`, `ConsoleNotifier`,
`GameDayConfig`) и его тесты.

Что добавить: два стартера в `pom.xml`; в `example.gameday` — исключения
`NoSuchEntryException` и `InvalidInputException`, тело ошибки `ErrorBody`
и обработчик `ErrorHandler`; в `example.gameday.journal` —
`IncidentResponse`, `IncidentService`, `IncidentIds`, `IncidentController`
и тест `IncidentControllerTest`. Тестам на базе нужен запущенный Docker,
срезу — нет.

```xml
<!-- pom.xml: в <dependencies>, рядом с тем, что уже есть -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-webmvc</artifactId>
</dependency>
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-webmvc-test</artifactId>
    <scope>test</scope>
</dependency>
```

```java
// src/main/java/example/gameday/NoSuchEntryException.java
package example.gameday;

/** «Такого нет»: обработчик ответит 404. Код — для машины, текст — для человека. */
public class NoSuchEntryException extends RuntimeException {

    private final String code;

    public NoSuchEntryException(String code, String message) {
        super(message);
        this.code = code;
    }

    public String getCode() {
        return code;
    }
}
```

```java
// src/main/java/example/gameday/InvalidInputException.java
package example.gameday;

/** «На входе негодное»: обработчик ответит 400. Код — для машины, текст — для человека. */
public class InvalidInputException extends RuntimeException {

    private final String code;

    public InvalidInputException(String code, String message) {
        super(message);
        this.code = code;
    }

    public String getCode() {
        return code;
    }
}
```

```java
// src/main/java/example/gameday/ErrorBody.java
package example.gameday;

/** Тело ответа об ошибке — одно на все ручки. */
public record ErrorBody(String code, String message) {
}
```

```java
// src/main/java/example/gameday/ErrorHandler.java
package example.gameday;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.TypeMismatchException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.ErrorResponse;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice
public class ErrorHandler {

    private static final Logger logger = LoggerFactory.getLogger(ErrorHandler.class);

    @ExceptionHandler(NoSuchEntryException.class)
    public ResponseEntity<ErrorBody> noSuchEntry(NoSuchEntryException e) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND)
                .body(new ErrorBody(e.getCode(), e.getMessage()));
    }

    @ExceptionHandler(InvalidInputException.class)
    public ResponseEntity<ErrorBody> invalidInput(InvalidInputException e) {
        return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                .body(new ErrorBody(e.getCode(), e.getMessage()));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ErrorBody> unexpected(Exception e) throws Exception {
        if (e instanceof ErrorResponse || e instanceof TypeMismatchException) {
            throw e;
        }
        logger.error("Непредвиденная ошибка", e);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(new ErrorBody("unexpected_error", "Непредвиденная ошибка"));
    }
}
```

```java
// src/main/java/example/gameday/journal/IncidentResponse.java
package example.gameday.journal;

import java.time.Instant;
import java.util.UUID;

public record IncidentResponse(UUID id, String title, Instant detectedAt,
                               Instant fixedAt, String dutyName) {

    public static IncidentResponse of(Incident incident) {
        return new IncidentResponse(incident.getId(), incident.getTitle(),
                incident.getDetectedAt(), incident.getFixedAt(), incident.getDutyName());
    }
}
```

```java
// src/main/java/example/gameday/journal/IncidentService.java
package example.gameday.journal;

import example.gameday.NoSuchEntryException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.UUID;

@Service
@Transactional(readOnly = true)
public class IncidentService {

    private final IncidentRepository repository;

    public IncidentService(IncidentRepository repository) {
        this.repository = repository;
    }

    public IncidentResponse get(UUID id) {
        Incident incident = repository.findById(id)
                .orElseThrow(() -> new NoSuchEntryException("incident_not_found", "Происшествие не найдено"));
        return IncidentResponse.of(incident);
    }
}
```

```java
// src/main/java/example/gameday/journal/IncidentIds.java
package example.gameday.journal;

import example.gameday.InvalidInputException;

import java.util.UUID;

/** Номер происшествия из пути: строго в том виде, в каком его пишет UUID.toString(). */
public final class IncidentIds {

    private IncidentIds() {
    }

    public static UUID parse(String raw) {
        try {
            UUID id = UUID.fromString(raw);
            if (id.toString().equals(raw)) {
                return id;
            }
        } catch (IllegalArgumentException e) {
            // совсем не UUID — ответ тот же, что ниже
        }
        throw new InvalidInputException("incident_id_invalid", "Это не номер происшествия");
    }
}
```

```java
// src/main/java/example/gameday/journal/IncidentController.java
package example.gameday.journal;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

@RestController
public class IncidentController {

    private final IncidentService service;

    public IncidentController(IncidentService service) {
        this.service = service;
    }

    @GetMapping("/game-day/incidents/{id}")
    public IncidentResponse get(@PathVariable("id") String id) {
        UUID incidentId = IncidentIds.parse(id);
        return service.get(incidentId);
    }
}
```

```java
// src/test/java/example/gameday/journal/IncidentControllerTest.java
package example.gameday.journal;

import example.gameday.NoSuchEntryException;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.http.HttpStatus;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.assertj.MockMvcTester;

import java.time.Instant;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

@WebMvcTest(IncidentController.class)
class IncidentControllerTest {

    private static final String PATH = "/game-day/incidents/{id}";
    private static final UUID ID = UUID.fromString("7d1e3c52-9a4b-4f10-8c2d-1b2a3c4d5e6f");

    @Autowired
    private MockMvcTester mvc;

    @MockitoBean
    private IncidentService service;

    @Test
    void returnsIncident() {
        when(service.get(ID)).thenReturn(new IncidentResponse(ID, "Брокер не отвечает",
                Instant.parse("2026-10-14T10:05:00Z"), null, "duty-1"));

        assertThat(mvc.get().uri(PATH, ID))
                .hasStatusOk()
                .bodyJson().isStrictlyEqualTo("""
                        {"id": "7d1e3c52-9a4b-4f10-8c2d-1b2a3c4d5e6f",
                         "title": "Брокер не отвечает",
                         "detectedAt": "2026-10-14T10:05:00Z",
                         "fixedAt": null,
                         "dutyName": "duty-1"}
                        """);
    }

    @Test
    void unknownIncidentIs404() {
        when(service.get(ID))
                .thenThrow(new NoSuchEntryException("incident_not_found", "Происшествие не найдено"));

        assertThat(mvc.get().uri(PATH, ID))
                .hasStatus(HttpStatus.NOT_FOUND)
                .bodyJson().extractingPath("$.code").isEqualTo("incident_not_found");
    }

    @ParameterizedTest(name = "{0} → 400")
    @ValueSource(strings = {"abc", "1-1-1-1-1"})
    void badIdIs400(String badId) {
        assertThat(mvc.get().uri(PATH, badId))
                .hasStatus(HttpStatus.BAD_REQUEST)
                .bodyJson().extractingPath("$.code").isEqualTo("incident_id_invalid");
        verifyNoInteractions(service);
    }
}
```
