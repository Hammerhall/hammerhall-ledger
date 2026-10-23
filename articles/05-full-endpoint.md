# Ручка целиком: слои, доступ, страницы, тесты всех слоёв

> «От Java к Spring Boot» · статья 5 · читать минут 45
>
> **Для кого.** Ты прочитал статьи 0–4. В песочнице `game-day` журнал
> отвечает по HTTP: ручка по номеру, служба `IncidentService`, свои
> ошибки и срез `IncidentControllerTest` с заглушкой Mockito. Звать ручку
> пока может кто угодно.
>
> **Что будет.** Зачем ручку делят на слои и почему наружу уходит
> запись, а не сущность. Как отдавать список страницами и кто вправе его
> звать — вход и роли на Spring Security. Какие тесты ставить на каждый
> слой и как показать ручку живьём.
>
> **Откуда статья.** Раздел «Буткемп / Лаборатория» — о том, как пишут
> код команды Hammerhall: буткемп работает в открытых репозиториях,
> лаборатория — в закрытых. Серия «От Java к Spring Boot» — то, что
> нужно новичку до первой задачи на Spring Boot 4. Примеры — учебные:
> их можно повторить у себя.

---

## Зачем раскладывать ручку по слоям

В статье 4 ручка по номеру уже шла через службу `IncidentService`,
и статья обещала объяснить зачем. На списке это видно ярче.

Нужна ручка `GET /game-day/incidents?page&size&open`. После игрового
дня тимлид листает журнал, новые происшествия сверху. Может оставить
и только открытые. Звать её может только `admin`. Сложи всё это
в контроллер — и вот что окажется в одном методе:

```java
@GetMapping("/game-day/incidents")
public Object list(Integer page, Integer size, boolean open) {
    // 1. HTTP: разобрать page и size, на кривые ответить 400
    // 2. доступ: вошёл ли человек и admin ли он
    // 3. данные: какую выборку взять и как попросить у неё страницу
    // 4. правила: «открытое» — это без fixedAt; что из строки отдать наружу
}
```

Четыре заботы — и каждую надо проверить. Возьмём одно правило:
«`open=true` — только открытые, иначе все». Чтобы его проверить,
придётся поднять Spring, войти под `admin` и послать HTTP-запрос. Тест
покраснел — а что сломалось: путь, вход или правило? Такой класс трудно
прочитать и ещё труднее протестировать.

Журнал игрового дня — учебный пример. Но в рабочем проекте так устроена
почти любая ручка-список: страницы, роль, тесты на каждом слое и показ
живьём. Эта статья собирает в одну ручку всё, что было в серии.

В коротких примерах нет строк `import` — полные файлы в конце статьи.

---

## Часть 1. Слои

### Официант, повар, склад

Представь кухню ресторана. **Официант** принимает заказ, переспрашивает
непонятное и приносит блюдо — но не готовит. **Повар** знает рецепты,
что взять и как приготовить. Но к гостям он не выходит, и ему всё равно,
заказ пришёл из зала или по телефону. **Склад** выдаёт продукты по
накладной и не знает, что из них приготовят.

У ручки те же три обязанности — **слои**:

| слой | знает | не знает |
|---|---|---|
| контроллер — официант | путь, параметры, статусы, JSON | таблицы и правило «открытые — без `fixedAt`» |
| служба — повар | правила: какую выборку взять, что отдать наружу; транзакцию | HTTP: пути, `?page=`, коды ответа |
| хранилище — склад | таблицу и запросы к ней | кто спрашивает и зачем |

🔑 **Контроллер переводит HTTP в вызов службы и обратно. Правила живут
в службе, данные — в хранилище.** Тогда каждый слой проверяется
отдельно: служба — без HTTP и без базы, хранилище — без HTTP,
контроллер — без базы.

В рабочем проекте у каждой ручки обычно свои контроллер и служба. Один
класс на все ручки разрастается, и в нём уже не найти, что к какой
ручке относится. Поэтому у списка тоже свои — `IncidentListController`
и `IncidentListService`. Код ручки по номеру из статьи 4 не трогаем.

### Контроллер: только HTTP

```java
@RestController
public class IncidentListController {

    private final IncidentListService service;

    public IncidentListController(IncidentListService service) {   // служба — через конструктор
        this.service = service;
    }

    // доступ: только admin — в настройке охраны SecurityConfig (часть 3)
    @GetMapping("/game-day/incidents")
    public PageBody<IncidentResponse> list(                             // страница ответов — часть 2
            @RequestParam(name = "page", required = false) Integer page,    // не пришёл — null
            @RequestParam(name = "size", required = false) Integer size,
            @RequestParam(name = "open", defaultValue = "false") boolean open) {
        PageRequest pageRequest = Pages.request(page, size);            // умолчания и 400 — там
        return service.list(pageRequest, open);                         // остальное — служба
    }
}
```

Три вещи здесь важны:

* `page` и `size` — `Integer` с `required = false`, как `Boolean open`
  в статье 4: не пришедший параметр доходит как `null`, а умолчания
  знает `Pages.request` (часть 2);
* `defaultValue = "false"` — не пришёл `open`, будет `false`. Поэтому
  здесь `boolean`, а не `Boolean`: `null` не бывает;
* в методе нет ни одного `if`. Появилось в контроллере условие про
  данные — правило просочилось не в тот слой.

На `?page=abc` до `Pages.request` дело не дойдёт. Строку в `Integer`
переводит сам Spring и отвечает своей ошибкой — `400` в форме Boot, без
нашего `code`, как на `?open=abc` в статье 4. Это то же упрощение
песочницы.

### Служба: правила и транзакция

```java
@Service
@Transactional(readOnly = true)                                    // только читаем — как в статье 4
public class IncidentListService {

    private final IncidentRepository repository;

    public IncidentListService(IncidentRepository repository) {
        this.repository = repository;
    }

    public PageBody<IncidentResponse> list(Pageable pageable, boolean openOnly) {   // «какая страница»
        Page<Incident> found;
        if (openOnly) {                                                // правило журнала
            found = repository.findByFixedAtIsNullOrderByDetectedAtDesc(pageable);
        } else {
            found = repository.findAllByOrderByDetectedAtDesc(pageable);
        }
        Page<IncidentResponse> responses = found.map(IncidentResponse::of);   // сущность → ответ
        return new PageBody<>(responses.getContent(), pageable.getPageNumber(), pageable.getPageSize(),
                responses.getTotalElements());                         // страница в нашей форме
    }
}
```

`Page`, `Pageable`, `PageRequest` — страница Spring Data (часть 2); пока
читай как «дай страницу номер N — и сколько всего». `map` — готовый
метод страницы. С ссылкой на метод `IncidentResponse::of` (статья 3б) он
превращает каждую строку в ответ, а число «всего» оставляет как было.
`PageBody` — наша форма страницы в ответе, о ней тоже часть 2.

Служба не знает слов «запрос» и «400». Поэтому её можно позвать из ручки,
из задания по расписанию или из теста обычным `new`.

**Где транзакция.** Границу действия задаёт служба: «дай страницу» —
это строки и подсчёт. Поэтому `@Transactional(readOnly = true)` —
на службе, как в статье 4, а не на контроллере и не на хранилище
(статья 3б).

**Выбор журнала.** Здесь журнал решил за тебя. Между HTTP и базой два
класса. «Какую страницу» собирает `Pages`, а служба получает готовый
`Pageable`, отдаёт готовый `PageBody` и держит развилку по `open`.
В рабочей задаче такие вопросы решает тот, кто её делает, и на ревью
его спросят почему. Дальше такие места помечены коротко —
«выбор журнала».

### Наружу — запись-ответ, а не сущность

Статья 4 обещала разобрать, почему ручка отдаёт запись. Причины —
на журнале:

* **Утечка полей.** Завтра в таблицу добавят столбец `attacker_note`,
  заметку тимлида о том, как он сломал стенд. Будь наружу сущность, новое
  поле ушло бы в JSON само, и дежурный прочитал бы разгадку посреди игры.
  Запись отдаёт только то, что в ней перечислено.
* **Ленивые связи** — связанные строки, которые JPA дочитывает из базы
  только при первом обращении (у журнала их нет). Jackson при переводе
  в JSON обратится ко всему — лишние запросы к базе, а то и ошибка.
* **Контракт меняется вместе с таблицей.** Переименуешь поле сущности —
  и у всех, кто зовёт ручку, поменяется JSON. Запись-ответ — договор
  с клиентом, а таблица — внутреннее дело приложения. Меняются они порознь.

Переводит сущность в ответ служба. Так сущность не выходит за её
пределы и за пределы транзакции (выбор журнала). 💡 Перевод живёт в одном
из двух мест: метод `of` на записи-ответе, как у нас, или отдельный
класс-переводчик — тогда запись-ответ ничего не знает про сущность
и JPA. В рабочих проектах встречается и то и другое.

---

## Часть 2. Страницы

### Зачем постранично

За сезон игровых дней происшествий наберётся тысяча. Одним ответом —
огромный JSON, долгий запрос и экран, который всё равно покажет двадцать
строк. Поэтому список отдают **страницами**: «страница 0, по 20» —
двадцать строк и число «всего».

### Параметры: умолчания и 400

`page` не пришёл — 0, `size` не пришёл — 20; `page` меньше нуля — `400`
с кодом `page_number_invalid`; `size` вне 1..50 — `400` с кодом
`page_size_invalid`. Правило одно на все списки приложения. Поэтому живёт
оно не в журнале, а в корне пакетов, `example.gameday`, рядом
с `ErrorBody`. Это маленький класс, как `IncidentIds` из статьи 4:

```java
public final class Pages {

    public static final int DEFAULT_SIZE = 20;
    public static final int MAX_SIZE = 50;

    private Pages() {                                     // объекты не нужны — только метод
    }

    public static PageRequest request(Integer page, Integer size) {
        int number = 0;                                   // не пришёл — первая страница
        if (page != null) {
            number = page;
        }
        int rows = DEFAULT_SIZE;                          // не пришёл — по 20
        if (size != null) {
            rows = size;
        }
        if (number < 0) {
            throw new InvalidInputException("page_number_invalid", "Номер страницы — 0 или больше");
        }
        if (rows < 1 || rows > MAX_SIZE) {
            throw new InvalidInputException("page_size_invalid", "Размер страницы — от 1 до 50");
        }
        return PageRequest.of(number, rows);              // «страница number, по rows строк»
    }
}
```

Кривые числа — `InvalidInputException` из статьи 4: обработчик ответит
`400` в нашей форме, с кодом. Проверять их надо до `PageRequest.of`.
На `-1` он сам бросит `IllegalArgumentException`, и клиент получил бы
`500` «сломалось у нас» вместо «запрос негодный».

### Ответ: PageBody

Форма ответа одна на все списки приложения — запись `PageBody<T>`, тоже
в `example.gameday`:

```java
public record PageBody<T>(List<T> items, int page, int size, long total) {
}
```

```json
{"items":[…],"page":0,"size":20,"total":57}
```

`items` — строки страницы, `page` и `size` — какие спросили, `total` —
сколько всего. По `total` экран рисует число страниц. `<T>` — параметр
типа, как в `JpaRepository<Incident, UUID>` (статья 3б):
`PageBody<IncidentResponse>` — страница ответов о происшествиях.
Появится список дежурных — будет `PageBody` с их ответами, запись та же.
Пустые `<>` в `new PageBody<>(…)` ты видел в статье 1: тип Java выводит
из аргументов.

### Как попросить страницу у хранилища

Последним параметром метода хранилища передают «какую страницу» —
`Pageable`, его создаёт `PageRequest.of(номер, размер)`. Возвращает метод
`Page` — строки и общее число:

```java
public interface IncidentRepository extends JpaRepository<Incident, UUID> {

    // findByDutyName, findByFixedAtIsNull, findOpenOf — из статьи 3б

    Page<Incident> findAllByOrderByDetectedAtDesc(Pageable pageable);            // все, новые сверху

    Page<Incident> findByFixedAtIsNullOrderByDetectedAtDesc(Pageable pageable);  // только открытые
}
```

`findAllBy` без условия — «все строки»: `By` нужен, даже когда условия
нет. Дальше `OrderByDetectedAtDesc` — «по `detectedAt`, по убыванию».
Во втором методе условие есть — `FixedAtIsNull`, как в
`findByFixedAtIsNull` из статьи 3б.

Из `Pageable` Spring Data возьмёт, сколько строк пропустить и сколько
взять. В SQL, который Hibernate пошлёт в Postgres для второй страницы
и дальше, это хвост `offset ? rows fetch first ? rows only` — «пропусти
столько-то строк, возьми первые столько-то». Строки страницы —
`getContent()`.

Общее число — `getTotalElements()`: за него Spring Data
обычно платит вторым запросом, `count`. Пропускает он его, когда число
и так видно. Страница пришла неполной, но не пустой — значит, она
последняя. Всего тогда — сколько пропустили плюс сколько пришло.

⚠️ `Page`, `Pageable`, `PageRequest` — из `org.springframework.data.domain`.
IDE может первым предложить `java.awt.print.Pageable` из JDK — это не тот.

⚠️ `total` — только из `getTotalElements()`, а не из длины `items`:
на странице 20 строк, а всего их может быть 57.

💡 У двух строк может быть одинаковое `detectedAt`. Порядок между ними
база не обещает, и строка может перескочить на соседнюю страницу. Лечится
вторым ключом сортировки: `…OrderByDetectedAtDescIdDesc`.

### Фильтр open и страница за концом

Открытое происшествие — без `fixedAt`. В журнале договорились:
`open=true` — только открытые; не передан или `false` — все, а не
«только закрытые». Такое не угадывают, а пишут в контракт ручки.

Страница за концом — `?page=5`, а происшествий три. Хранилище вернёт
пустые строки и настоящий `total`. Отдать это как `200` или ответить
`404` — выбор журнала; он отдаёт `200` с пустой страницей.

---

## Часть 3. Доступ

### Кто пришёл и можно ли ему

Сейчас список, как и ручку по номеру, может позвать любой, кто
достучался до порта 8080. Статья 4 обещала: журнал — внутреннее дело
команды, и звать его будет только `admin`. Для этого на каждый запрос
нужно два ответа:

* **кто пришёл** — это **вход** (аутентификация): человек доказывает,
  что он — это он;
* **можно ли ему сюда** — это **доступ** (авторизация): решают по ролям
  вошедшего.

В рабочем проекте вход — по куке (статья 4). Пишет его мидл, один раз
на все ручки, а джун им пользуется. В своей ручке он только говорит,
кого пускать. В песочнице вход попроще, но вопросы те же, и отвечать
на них будет одна библиотека.

### Spring Security — охрана перед контроллером

**Spring Security** — библиотека, которая проверяет каждый запрос
раньше, чем он дойдёт до контроллера: кто пришёл и можно ли ему сюда.

**Зачем.** В курсах проверку пишут прямо в методе: `if (!isAdmin(…))`.
Десять ручек — десять таких `if`, и в одной его обязательно забудут.
Охрана перед всеми ручками сразу закрывает и те, про которые забыли.
Как проходная в здании: пропуск смотрят на входе, а не у каждого
кабинета.

**Откуда берётся.** Стартер `spring-boot-starter-security`, а для
тестов — свой тестовый стартер. Добавь их в `pom.xml` песочницы:

```xml
<dependency>                                <!-- охрана: вход и доступ -->
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-security</artifactId>
</dependency>
<dependency>                                <!-- охрана в тестах: срез, вход в запросе -->
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-security-test</artifactId>
    <scope>test</scope>
</dependency>
```

Версии подставляет `<parent>`.

⚠️ В интернете ты увидишь для тестов зависимость
`org.springframework.security:spring-security-test`. Это Boot 2–3.
В Boot 4 у Spring Security, как у веба, свой тестовый
стартер — `spring-boot-starter-security-test`. `spring-security-test`
он приносит сам и, главное, подключает охрану к срезу `@WebMvcTest`.
Без него срез об охране не знает, и тест с нашей настройкой охраны
не поднимется.

**Как работает.** Охрана — это **фильтры**: код, через который Tomcat
пропускает запрос раньше Spring MVC. Отказали — до контроллера и нашего
обработчика ошибок дело не доходит. Подключи один стартер без всякой
настройки — и Boot закроет всё приложение. Каждый запрос пустят только
со входом, а пользователь один, `user`. Пароль Boot придумает при старте
и напечатает в лог: `Using generated security password: …`.
Это охрана по умолчанию. Своя — ниже, и с ней эта строка из лога
пропадёт.

### Вход по Basic

**HTTP Basic** — самый простой вход по HTTP: имя и пароль едут в каждом
запросе, в заголовке `Authorization`:

```
Authorization: Basic YWRtaW46YWRtaW4tbG9jYWw=
```

После слова `Basic` — строка `admin:admin-local` в **base64**: так любые
байты записывают латинскими буквами и цифрами. Руками заголовок
не собирают. У `curl` для этого ключ `-u admin:admin-local`, в тесте
есть `httpBasic("admin", "admin-local")` (часть 4). Не вошёл или пароль
не тот — охрана отвечает `401` с заголовком
`WWW-Authenticate: Basic realm="Realm"`: «войди по Basic».

🔴 base64 — не шифр: `echo YWRtaW46YWRtaW4tbG9jYWw= | base64 -d`
напечатает пароль. Кто видит запрос, видит и пароль. Поэтому Basic без
HTTPS, шифрованного HTTP, годится только для своей машины, как
песочница на `localhost`.

Пользователей в песочнице двое, с ролями из статьи 4: `admin` — ему
журнал можно, и `viewer` — вошёл, но журнал ему нельзя.

### Охрана песочницы: SecurityConfig

Правила охраны — бины в классе настроек, как `GameDayConfig`
из статьи 1. Охрана общая для всего приложения, поэтому класс лежит
в корне пакетов, `example.gameday`, рядом с `ErrorHandler`:

```java
@Configuration
public class SecurityConfig {

    @Bean
    public SecurityFilterChain security(HttpSecurity http) {             // правила охраны
        http.authorizeHttpRequests(access -> access                         // кого куда пускать
                        .dispatcherTypeMatchers(DispatcherType.ERROR).permitAll()   // тело ошибки — Boot
                        .requestMatchers(HttpMethod.GET, "/game-day/incidents").hasRole("admin")
                        .requestMatchers(HttpMethod.GET, "/game-day/incidents/{id}").hasRole("admin")
                        .anyRequest().denyAll())                             // остальное — никому
                .httpBasic(Customizer.withDefaults())                        // вход: имя и пароль в запросе
                .sessionManagement(session -> session
                        .sessionCreationPolicy(SessionCreationPolicy.STATELESS));   // без сеанса и кук
        return http.build();
    }

    @Bean
    public UserDetailsService users() {                                   // кто есть: пользователи в памяти
        return new InMemoryUserDetailsManager(
                User.withUsername("admin").password("{noop}admin-local").roles("admin").build(),
                User.withUsername("viewer").password("{noop}viewer-local").roles("viewer").build());
    }
}
```

Читай сверху вниз.

* `HttpSecurity` — конструктор правил, его даёт Spring Security. Метод
  собирает из него `SecurityFilterChain` — цепочку фильтров охраны. Бин
  такого типа — знак для Boot: охрана своя, умолчание не нужно.
* `authorizeHttpRequests` — правила доступа, каждое — «какие запросы →
  кого пускать». Охрана читает их по порядку, и срабатывает **первое**
  подошедшее.
* `dispatcherTypeMatchers(DispatcherType.ERROR).permitAll()` — пересылка
  на служебный адрес `/error`. Ошибки Spring и отказы охраны Tomcat
  пересылает туда, и там Boot собирает тело ответа (статья 4). Пересылка —
  тоже запрос, и охрана проверяет и её. Документация Spring Security
  советует её открыть, чтобы Boot мог собрать ответ об ошибке.
* `requestMatchers(HttpMethod.GET, "…").hasRole("admin")` — `GET` на этот
  путь пускают только с ролью `admin`. Путь — ровно как в `@GetMapping`,
  с `{id}` у ручки по номеру. То, что после `?`, в путь не входит:
  охрана смотрит только на путь.
* `anyRequest().denyAll()` — всё, что не разрешено выше, никому.
  Документация Spring Security советует такой конец. Правила становятся
  списком разрешённого, и ручка, которую забыли вписать, останется
  закрытой, а не открытой.
* `httpBasic(Customizer.withDefaults())` — вход по Basic с настройками
  по умолчанию.
* `sessionCreationPolicy(SessionCreationPolicy.STATELESS)` — без сеанса.
  **Сеанс** (session) — память сервера о том, кто уже вошёл: сервер
  выдаёт куку и дальше узнаёт человека по ней. Basic сеанс не нужен:
  пароль приходит с каждым запросом. Поэтому куки охрана не выдаёт.
* `UserDetailsService` — откуда охрана берёт пользователей: имя, пароль,
  роли. `InMemoryUserDetailsManager` держит их в памяти — песочнице
  хватит. `{noop}` перед паролем — «хранится как есть, без шифрования»:
  Spring Security требует сказать, чем зашифрован пароль.

🔴 Пароли в коде — только в учебной песочнице. Код читает всякий, кто
видит репозиторий, а `{noop}` хранит пароль открытым текстом. В рабочем
проекте паролей приложения в коде нет вовсе — вход там по куке.

⚠️ В интернете ты увидишь класс-наследник `WebSecurityConfigurerAdapter`,
правила через `authorizeRequests()` и цепочки настроек с `.and()`. Это
Spring Security 5 — Boot 2. В Spring Security 7, который приносит
Boot 4, ничего из этого нет, и такой код не скомпилируется: правила —
бином `SecurityFilterChain`, через `authorizeHttpRequests` и лямбды, как
выше.

### Кого пускать — одним способом

Сказать «эта ручка — только для `admin`» можно двумя способами: строкой
в общей настройке охраны, как у нас, или аннотацией над методом
контроллера — `@PreAuthorize("hasRole('admin')")`. Такие аннотации
включает `@EnableMethodSecurity` на классе настроек.

В рабочем проекте выбирают один способ на всё приложение, и новую ручку
объявляют так же, как соседние. Второй способ не изобретают: ревьюер
проверяет доступ глазами, а это возможно, только если он везде записан
одинаково. Журнал — внутреннее дело команды, поэтому пускаем только
`admin`.

⚠️ В песочнице способ один — настройка охраны, и это не случайно. Отказ
из `@PreAuthorize` — исключение, которое вылетает уже из метода
контроллера. Его поймает наш обработчик `Exception` из статьи 4 —
и `viewer` получит `500` «сломалось у нас» вместо `403`. Правило
в настройке срабатывает раньше Spring MVC, и обработчик отказа не видит.

### Отказ: сначала вход, потом всё остальное

`401` — не вошёл или пароль не тот, `403` — вошёл, но нельзя. Иногда
вместо `403` отвечают `404` (статья 4), а в песочнице — точные `401`
и `403`. В рабочем проекте, что отвечать на «нельзя», решает тот, кто
пишет вход. Тест ручки проверяет ровно этот статус.

Охрана стоит **до** контроллера: запрос без входа получит `401`, даже
если в нём `?size=500`. Отсюда два правила для тестов. `400` проверяют
со входом под `admin`, а при отказе убеждаются, что служба не вызвана.
Служба вызвана при отказе — значит, чужой запрос дошёл до данных:
прочитал, а у ручки, которая меняет, уже изменил. Отказ должен
случиться раньше.

Заметь, что стало с адресом, которого нет. В статье 4 на
`/game-day/nothing` отвечал Spring — `404`. Теперь раньше отвечает
охрана: без входа — `401`, под `admin` — `403`, это сработал `denyAll`.
Охрана не знает, есть ли такая ручка, — и чужому этого не подскажет.

### Строка в таблице периметра

В рабочем проекте есть **тест периметра**. Он сверяет все ручки
приложения с таблицей `DECLARED`: метод, путь и кого пускают. Ручка
есть, а строки нет — тест красный. В песочнице заведём такой же —
`PerimeterTest` в `example.gameday`:

```java
@WebMvcTest                                                     // все контроллеры приложения, без базы
class PerimeterTest {

    static final List<Endpoint> DECLARED = List.of(              // метод, путь, кого пускают
            new Endpoint("GET", "/game-day/incidents/{id}", "admin"),
            new Endpoint("GET", "/game-day/incidents", "admin"));

    @Autowired
    private RequestMappingHandlerMapping mappings;               // Spring MVC: какой метод на какой путь

    @MockitoBean
    private IncidentService incidentService;                     // контроллерам нужны службы — заглушки

    @MockitoBean
    private IncidentListService incidentListService;

    @Test
    void everyEndpointIsDeclared() {
        List<String> found = new ArrayList<>();
        mappings.getHandlerMethods().forEach((mapping, handler) -> {
            if (handler.getBeanType().getPackageName().startsWith("example.gameday")) {   // только наши
                for (RequestMethod method : mapping.getMethodsCondition().getMethods()) {
                    for (String path : mapping.getPatternValues()) {
                        found.add(method + " " + path);                    // «GET /game-day/incidents»
                    }
                }
            }
        });
        List<String> declared = new ArrayList<>();
        for (Endpoint endpoint : DECLARED) {
            declared.add(endpoint.method() + " " + endpoint.path());
        }
        assertThat(found).containsExactlyInAnyOrderElementsOf(declared);   // те же, порядок не важен
    }

    record Endpoint(String method, String path, String role) {
    }
}
```

* `@WebMvcTest` без контроллера в скобках — срез со всеми контроллерами
  приложения (статья 4). Службы — заглушки: без них контроллеры
  не создать.
* `RequestMappingHandlerMapping` — бин Spring MVC, который помнит, какой
  метод контроллера отвечает на какой HTTP-метод и путь.
  `getHandlerMethods()` — весь этот список. `forEach((mapping, handler) -> …)`
  обходит его парами «адрес — метод контроллера»: у лямбды два параметра.
* Проверка пакета отсекает чужие ручки — например, `/error` самого Boot.
* `containsExactlyInAnyOrderElementsOf` — «те же строки, порядок
  не важен». Лишняя ручка или лишняя строка — тест красный и пишет,
  какая.
* `record Endpoint` внутри класса — запись только для этого теста.

У списка своя строка — `new Endpoint("GET", "/game-day/incidents", "admin")`.
Путь — ровно как в `@GetMapping`, без `?page&size`; у ручки по номеру —
своя строка, с `{id}`. Столбец «кто» тест не проверяет. Его сверяет
ревьюер — с тем, как доступ записан в `SecurityConfig`.

🔴 Ручка без объявленного доступа — дверь, про которую забыли.
В песочнице такую дверь закрывает `denyAll`, а строка в `DECLARED`
заставляет ручку представиться. Появилась ручка без строки — тест
периметра красный.

---

## Часть 4. Тесты всех слоёв

### Пирамида

**Юнит-тест** — модульный тест из статьи 3б: один класс, без Spring и без
базы. Он идёт миллисекунды. Веб-тест и `*IT` — секунды (первый запуск
с Docker дольше), показ — минуты и руки. Поэтому тесты ставят
**пирамидой**: внизу много дешёвых, наверху мало дорогих. Виды тестов
и пирамида подробно — в [статье 1 «Зачем тесты и чего от тебя ждут
на проекте»](https://hammerhall.io/ledger/testing/1-why-tests) серии «От красного к зелёному».

```
             показ на своей машине             один, руками
          сквозной: база + настоящий вход      один на ручку
       *IT хранилища на настоящей базе         несколько
    веб-тест контроллера                       по тесту на каждый ответ
юнит-тесты службы и записей                    много
```

### Mockito без Spring

Заглушки Mockito ты знаешь по статье 4: там заглушку службы делал
`@MockitoBean` внутри Spring. Новое одно — Mockito без Spring. Юнит-тест
службы Spring не поднимает. Mockito подключают расширением JUnit
(статья 3а) — аннотацией `@ExtendWith(MockitoExtension.class)` над
классом теста. Перед каждым тестом оно создаёт заглушки и кладёт их
в поля с `@Mock`.

Запись — как в статье 4: `when(…).thenReturn(…)`, `verifyNoInteractions(…)` —
и новое `verify(заглушка).метод(аргументы)`: «метод звали ровно один
раз с такими аргументами». В чужом коде встретишь и `mock(Класс.class)`
вместо поля с `@Mock` — та же заглушка.

⚠️ В интернете ты увидишь поля `@Mock`, которые «сами работают» в тесте,
поднимающем всё приложение с `@SpringBootTest`, как тесты `*IT`. Это
Boot 2–3. В Boot 4 такие поля Boot не обслуживает. Без
`@ExtendWith(MockitoExtension.class)` поле останется `null`, и тест
упадёт с `NullPointerException`.

⚠️ `MockitoExtension` строгий. Настроил заглушку через `when`, а код её
так и не позвал? Тест красный с `UnnecessaryStubbingException`, даже
если все проверки прошли. Это не придирка: лишний `when` значит, что
тест думает о коде не то, что код делает.

### Служба — юнит-тест

```java
@ExtendWith(MockitoExtension.class)
class IncidentListServiceTest {

    private static final Instant T0 = Instant.parse("2026-10-05T09:15:00Z");

    @Mock
    private IncidentRepository repository;                 // заглушка — без Spring и без базы

    private IncidentListService service;

    @BeforeEach
    void setUp() {
        service = new IncidentListService(repository);     // обычный new
    }

    @Test
    void returnsPageWithTotalFromRepository() {
        Incident fresh = new Incident("лента стоит", T0.plusSeconds(120), "duty-1");
        Incident old = new Incident("брокер молчит", T0, "duty-2");
        when(repository.findAllByOrderByDetectedAtDesc(PageRequest.of(0, 2)))
                .thenReturn(new PageImpl<>(List.of(fresh, old), PageRequest.of(0, 2), 3));

        PageBody<IncidentResponse> page = service.list(PageRequest.of(0, 2), false);

        assertThat(page.items()).containsExactly(                     // все поля, тот же порядок
                new IncidentResponse(null, "лента стоит", T0.plusSeconds(120), null, "duty-1"),
                new IncidentResponse(null, "брокер молчит", T0, null, "duty-2"));
        assertThat(page.total()).isEqualTo(3);                        // всего, а не длина items
    }

    @Test
    void openOnlyAsksForOpenIncidents() {
        when(repository.findByFixedAtIsNullOrderByDetectedAtDesc(PageRequest.of(2, 10)))
                .thenReturn(new PageImpl<>(List.of(), PageRequest.of(2, 10), 0));

        service.list(PageRequest.of(2, 10), true);

        verify(repository).findByFixedAtIsNullOrderByDetectedAtDesc(PageRequest.of(2, 10));
    }
}
```

`@BeforeEach` — пара к `@AfterEach` из статьи 3а: JUnit выполняет метод
перед каждым тестом. Mockito сравнивает аргументы через `equals`.
`PageRequest.of(0, 2)` в `when` и тот, что тест отдал службе, — разные
объекты, но равные, как две записи с одинаковыми полями (статья 0).
`id` в ответах — `null`: ключ выдаёт база при сохранении. Второй тест
проверяет развилку по `open` — выбор журнала, как и сама развилка.

⚠️ `PageImpl`, готовая страница для заглушки, сам поправит `total`,
если страница неполная. Две строки, `PageRequest.of(0, 20)`, `total` 3 —
и `getTotalElements()` вернёт 2. Поэтому в тесте размер страницы равен
числу строк.

**Долг статьи 4.** Статья 4 обещала: что служба по номеру сама бросает
`NoSuchEntryException`, проверит её тест без Spring. Тем же приёмом
проверяются оба пути `IncidentService.get`, нашлось и не нашлось:

```java
when(repository.findById(ID)).thenReturn(Optional.of(
        new Incident("стенд не отвечает", Instant.parse("2026-10-05T09:15:00Z"), "duty-1")));
assertThat(service.get(ID).title()).isEqualTo("стенд не отвечает");      // нашлось — ответ

when(repository.findById(ID)).thenReturn(Optional.empty());                 // хранилище: «нет такого»
assertThatThrownBy(() -> service.get(ID))
        .isInstanceOfSatisfying(NoSuchEntryException.class,                 // исключение этого типа…
                e -> assertThat(e.getCode()).isEqualTo("incident_not_found")); // …и вот с таким кодом
```

`isInstanceOfSatisfying(тип, проверка)` — «исключение этого типа, и вот
что в нём»: лямбда получает его уже нужного типа, с `getCode()`.
Целиком, двумя тестами, — `IncidentServiceTest` в конце статьи.

**Долг статьи 3б.** Статья 3б удалила `IncidentLogTest` и честно
сказала: текст оповещения не проверяет ни один тест. Проверка вернётся
вместе с Mockito. Возвращаем — с заглушками хранилища и `Notifier`:

```java
@ExtendWith(MockitoExtension.class)
class IncidentLogTest {

    private static final Instant T0 = Instant.parse("2026-10-05T09:15:00Z");

    @Mock
    private IncidentRepository incidents;

    @Mock
    private Notifier notifier;

    @Test
    void addNotifiesDutyWithDetectionTime() {
        when(incidents.save(any(Incident.class))).thenAnswer(call -> call.getArgument(0));   // что дали
        IncidentLog log = new IncidentLog(new DutyRoster("duty-1"), notifier,
                Clock.fixed(T0, ZoneOffset.UTC), incidents);          // часы и дежурный — как в статье 1

        log.add("Брокер не отвечает");

        verify(notifier).send("duty-1", "Брокер не отвечает — замечено 2026-10-05T09:15:00Z");
    }
}
```

* `any(Incident.class)` — «любое происшествие»: какой объект создаст
  `add`, тест заранее не знает;
* `thenAnswer(call -> call.getArgument(0))` — ответ считает лямбда.
  Она возвращает первый аргумент вызова, то есть то, что сохраняли.
  Настоящий `save` возвращает сохранённую сущность — заглушка делает
  так же;
* `verify(notifier).send(…)` — оповещение целиком: кому и какой текст.

Свой юнит-тест есть и у `Pages`: умолчания, граница `size` и кривые
числа таблицей, как в статье 0, — `PagesTest` в конце статьи.

### Хранилище — тест на настоящей базе

Понял ли Spring Data имя метода и отбирает ли запрос нужное, заглушка
не скажет. Это дело `*IT`: новый класс `IncidentPagesIT` со своими
данными. Аннотации у него те же, что у `IncidentRepositoryIT`, поэтому
приложение и контейнер Spring возьмёт из кэша (статья 3а).
`IncidentRepositoryIT` из статьи 3б не трогаем: его тесты ждут в таблице
только свои строки.

```java
@SpringBootTest
@Import(TestcontainersConfiguration.class)
class IncidentPagesIT {

    private static final Instant T0 = Instant.parse("2026-10-05T09:15:00Z");

    @Autowired
    private IncidentRepository incidents;

    @BeforeEach
    void fillJournal() {
        incidents.save(new Incident("брокер молчит", T0, "duty-1"));
        incidents.save(new Incident("лента стоит", T0.plusSeconds(120), "duty-2"));
        Incident fixed = new Incident("письма копятся", T0.plusSeconds(240), "duty-1");   // самое новое…
        fixed.fix(T0.plusSeconds(600));                                                    // …но закрыто
        incidents.save(fixed);
    }

    @AfterEach
    void cleanUp() {
        incidents.deleteAll();                          // база общая — убрать за собой, как в статье 3б
    }

    @Test
    void openOnlyNewestFirst() {
        Page<Incident> page = incidents.findByFixedAtIsNullOrderByDetectedAtDesc(PageRequest.of(0, 1));

        assertThat(page.getContent()).extracting(Incident::getTitle).containsExactly("лента стоит");
        assertThat(page.getTotalElements()).isEqualTo(2);              // закрытое не посчитано
    }
}
```

Посмотри на данные: самое новое происшествие — закрытое. Не работает
фильтр — первой окажется «письма копятся», и тест покраснеет.

Данные для `*IT` подбирают так, чтобы ошибка **была видна**. Нужны
закрытая или чужая строка, разное время. Иначе тест зелёный при любом
коде. Какие строки нужны ручке — решают в каждой задаче заново.

Ещё два теста этого класса, «все, новые сверху» и «страница за
концом», — в конце статьи.

### Контроллер — веб-тест

Срез `@WebMvcTest` с `MockMvcTester` — как в статье 4, и служба в нём
тоже заглушка `@MockitoBean`. Параметры запроса передаёт
`.param("page", "0")`. Нового два.

**Охрана в срезе.** Срез берёт контроллеры, советников и фильтры, но
не классы `@Configuration` (статья 4), а `SecurityConfig` как раз такой.
Поэтому тест подключает её сам, через `@Import(SecurityConfig.class)`,
как `TestcontainersConfiguration` в тестах на базе.

**Вход в запросе.** `.with(ADMIN)` прикладывает к запросу заголовок
`Authorization`, как `curl -u`. `ADMIN` — **добавка к запросу**
(`RequestPostProcessor`). Её делает
`SecurityMockMvcRequestPostProcessors.httpBasic(имя, пароль)` из тестовой
части Spring Security. Вход настоящий: охрана сверит имя и пароль
с `SecurityConfig`.

```java
@WebMvcTest(IncidentListController.class)
@Import(SecurityConfig.class)                                     // охрана песочницы — срез сам её не берёт
class IncidentListControllerTest {

    private static final String PATH = "/game-day/incidents";
    private static final RequestPostProcessor ADMIN =                // вход в запросе — как curl -u
            SecurityMockMvcRequestPostProcessors.httpBasic("admin", "admin-local");
    private static final RequestPostProcessor VIEWER =
            SecurityMockMvcRequestPostProcessors.httpBasic("viewer", "viewer-local");
    …

    @Test
    void returnsPage() {
        when(service.list(PageRequest.of(0, 2), false)).thenReturn(new PageBody<>(
                List.of(new IncidentResponse(ID, "лента стоит", T0, null, "duty-1")), 0, 2, 3));

        assertThat(mvc.get().uri(PATH).param("page", "0").param("size", "2").with(ADMIN))
                .hasStatusOk()
                .bodyJson().isStrictlyEqualTo("""
                        {"items":[{"id":"7d1e3c52-9a4b-4f10-8c2d-1b2a3c4d5e6f","title":"лента стоит",
                                   "detectedAt":"2026-10-05T09:15:00Z","fixedAt":null,"dutyName":"duty-1"}],
                         "page":0,"size":2,"total":3}
                        """);
    }

    @ParameterizedTest(name = "{0}={1} → 400 {2}")
    @CsvSource(delimiter = '|', textBlock = """
            page | -1 | page_number_invalid
            size | 0  | page_size_invalid
            size | 51 | page_size_invalid
            """)
    void rejectsBadPageParams(String name, String value, String code) {
        assertThat(mvc.get().uri(PATH).param(name, value).with(ADMIN))
                .hasStatus(HttpStatus.BAD_REQUEST)
                .bodyJson().extractingPath("$.code").isEqualTo(code);
        verifyNoInteractions(service);                             // до службы не дошло
    }

    @Test
    void rejectsWithoutLogin() {
        assertThat(mvc.get().uri(PATH)).hasStatus(HttpStatus.UNAUTHORIZED);         // не вошёл
        verifyNoInteractions(service);
    }

    @Test
    void refusesViewer() {
        assertThat(mvc.get().uri(PATH).with(VIEWER)).hasStatus(HttpStatus.FORBIDDEN);   // вошёл, но нельзя
        verifyNoInteractions(service);
    }
}
```

`…` — `ID`, `T0`, `mvc` и заглушка `service`, как в статье 4. Тест «без
параметров» — в полном примере в конце.

⚠️ Забыл `@Import` — срез не упадёт сразу, а возьмёт охрану Boot
по умолчанию. Это пользователь `user` со случайным паролем, в выводе
теста — `Using generated security password: …`. Пользователя `admin`
в ней нет, и тесты под `admin` получат `401`.

💡 В интернете тесты со входом часто пишут аннотацией
`@WithMockUser(roles = "admin")`. Она подставляет вошедшего, минуя
пароль. В Boot 4 она работает с тестовым стартером охраны. Мы входим
по-настоящему: так тест заодно проверяет пользователей и пароли
из `SecurityConfig`.

Ручка по номеру из статьи 4 теперь тоже только для `admin`. Поэтому
`IncidentControllerTest` меняется так же: `@Import(SecurityConfig.class)`,
`.with(ADMIN)` в каждом запросе и два новых случая — без входа `401`, под
`viewer` `403`. Целиком — в конце статьи.

### Сквозной тест

Над `*IT` — один сквозной тест на ручку. В нём всё приложение, настоящая
база и настоящий вход под `admin`. В базе — закрытая строка новее
открытых. Проверить надо `200`, `items` и `total`. Слои проверены
по отдельности, а сквозной проверяет, что они сложились: путь, охрана,
выборка и JSON вместе.

```java
@SpringBootTest
@AutoConfigureMockMvc                                       // MockMvcTester — поверх всего приложения
@Import(TestcontainersConfiguration.class)
class IncidentListIT {

    private static final Instant T0 = Instant.parse("2026-10-05T09:15:00Z");
    private static final RequestPostProcessor ADMIN =
            SecurityMockMvcRequestPostProcessors.httpBasic("admin", "admin-local");

    @Autowired
    private MockMvcTester mvc;

    @Autowired
    private IncidentRepository incidents;

    @AfterEach
    void cleanUp() {
        incidents.deleteAll();
    }

    @Test
    void adminGetsOpenIncidentsNewestFirst() {
        Incident older = incidents.save(new Incident("брокер молчит", T0, "duty-1"));
        Incident newer = incidents.save(new Incident("лента стоит", T0.plusSeconds(120), "duty-2"));
        Incident fixed = new Incident("письма копятся", T0.plusSeconds(240), "duty-1");   // самое новое…
        fixed.fix(T0.plusSeconds(600));                                                    // …но закрыто
        incidents.save(fixed);

        assertThat(mvc.get().uri("/game-day/incidents").param("open", "true").with(ADMIN))
                .hasStatusOk()
                .bodyJson().isStrictlyEqualTo("""
                        {"items":[
                            {"id":"%s","title":"лента стоит","detectedAt":"2026-10-05T09:17:00Z",
                             "fixedAt":null,"dutyName":"duty-2"},
                            {"id":"%s","title":"брокер молчит","detectedAt":"2026-10-05T09:15:00Z",
                             "fixedAt":null,"dutyName":"duty-1"}],
                         "page":0,"size":20,"total":2}
                        """.formatted(newer.getId(), older.getId()));       // ключи выдала база
    }
}
```

* `@AutoConfigureMockMvc` — сам `@SpringBootTest` `MockMvcTester`
  не даёт, а эта аннотация даёт. Запрос идёт через настоящие охрану,
  контроллер, службу и хранилище, только без Tomcat;
* `"""…""".formatted(a, b)` — подставить значения на места `%s`
  по порядку: ключи строк выдала база, заранее их не знаешь;
* данные — как в `IncidentPagesIT`: самое новое происшествие закрыто,
  и сломанный фильтр тест заметит.

Аннотаций у сквозного теста больше, чем у `IncidentPagesIT`, и
приложение из кэша ему не подойдёт (статья 3а). Spring поднимет
второе, со своим контейнером Postgres. Поэтому сквозной тест — один
на ручку, а не на каждый случай.

### Что ловит каждый тест

| тест | ловит | не ловит |
|---|---|---|
| юнит службы | выбор выборки по `open`; страница доходит до хранилища; `total`; перевод полей | отбирает ли выборка нужные строки; HTTP, вход |
| юнит `Pages` | умолчания и границы `page` и `size`, коды ошибок | HTTP: статус и форму ответа |
| `*IT` хранилища | имя метода понято; фильтр «без `fixedAt`», порядок и `total` на Postgres | HTTP, доступ, перевод в ответ |
| веб-тест | путь, умолчания, `400` с `code`, форма JSON, `401` и `403` | базу; работает ли всё вместе |
| тест периметра | у каждой ручки есть строка в `DECLARED` | верно ли записан доступ — это ревью |
| сквозной | путь, вход, выборка и JSON вместе | редкие случаи — их ловят нижние |
| показ | `.jar`, миграции, настройки из окружения, Tomcat, вход по `curl` | то, что руками не повторить |

Слои друг друга не заменяют: при сломанной выборке юнит службы и веб-тест
зелёные — там заглушки.

### Таблица случаев ручки

Таблица «на входе → итог», как в статье 0, — с новым столбцом «где
ловим».

| случай | запрос | ждём | где ловим |
|---|---|---|---|
| есть данные | `?page=0&size=2` под `admin` | 200, две строки, `total` — всего | служба, веб |
| без параметров | без `page` и `size` | 200, служба получила `(0, 20)` | `Pages`, веб |
| только открытые | `?open=true` | только строки без `fixedAt` | служба (какая выборка), `*IT` (что отбирает) |
| новые сверху | любой | по `detectedAt`, по убыванию | `*IT` |
| страница за концом | `?page=5` | 200, `items` пуст, `total` настоящий (выбор журнала) | `*IT` |
| журнал пуст | любой | 200, `items` пуст, `total` 0 | служба |
| `page` меньше 0 | `?page=-1` | 400 `page_number_invalid`, служба не вызвана | `Pages`, веб |
| `size` вне 1..50 | `?size=0`, `?size=51` | 400 `page_size_invalid`, служба не вызвана | `Pages`, веб |
| не вошёл | любой | 401, служба не вызвана | веб |
| вошёл `viewer` | любой | 403, служба не вызвана | веб |

🔑 **Каждая строка таблицы случаев — тест на самом нижнем слое, который
её ловит.** Строка без теста — дыра. В рабочем проекте на ревью таблицу
сверяют с тестами первым делом. Там, где в столбце два слоя, нижний
проверяет правило, а веб — что из него вышел нужный ответ.

### Верх пирамиды: показ

Тесты зелёные — ручка готова? Ещё нет: её показывают живьём. В рабочем
проекте — на стенде, а вывод `curl` вставляют в пул-реквест (статья 4).
В песочнице стенд — твоя машина: Postgres в контейнере и `java -jar`.

**1. Запуск.** Как в статье 4: база — `docker run` из статьи 3а, три
переменные `SPRING_DATASOURCE_*`, затем `./mvnw package` и
`java -jar target/game-day-0.0.1-SNAPSHOT.jar`. Строки
`Using generated security password` в логе нет, пользователей мы задали
сами. Как и раньше, запуск записал в журнал «Брокер не отвечает» —
открытое происшествие.

**2. Данные.** Добавь ещё два — открытое и закрытое. Открой `psql`
(`docker exec -it game-day-db psql -U postgres`) и выполни:

```sql
INSERT INTO game_day.incident (title, detected_at, fixed_at, duty_name) VALUES
    ('лента стоит',   '2026-10-05T09:17:00Z', NULL,                   'duty-1'),
    ('брокер молчит', '2026-10-05T09:15:00Z', '2026-10-05T09:40:00Z', 'duty-2');
```

```
INSERT 0 2
```

`id` не передаём — его придумает `DEFAULT` (статья 3а).

🔴 Руками в базу — только в своей базе в контейнере. На общих стендах
рабочего проекта руками не правят ничего — ни базу, ни запущенные
сервисы.

**3. Запрос.** В другом окне консоли. Адрес — в кавычках, иначе Git Bash
примет `&` за «запусти в фоне»:

```bash
curl -i -u admin:admin-local "http://localhost:8080/game-day/incidents?page=0&size=20&open=true"
```

Что должно вернуться:

```
HTTP/1.1 200
…
Content-Type: application/json
…

{"items":[
  {"id":"…","title":"Брокер не отвечает","detectedAt":"2026-10-20T…Z","fixedAt":null,"dutyName":"duty-1"},
  {"id":"…","title":"лента стоит","detectedAt":"2026-10-05T09:17:00Z","fixedAt":null,"dutyName":"duty-1"}],
 "page":0,"size":20,"total":2}
```

Тело приходит одной строкой, здесь разбито, чтобы влезло. Номера
и время «Брокера» у тебя свои, порядок полей может быть другим.
«Брокер не отвечает» — сверху: его записали только что.

`…` — служебные заголовки: `Date` и защитные, которые Spring Security
добавляет к каждому ответу. Например, `Cache-Control: no-cache, no-store, max-age=0, must-revalidate` —
ответ с данными журнала не кладут в кэш. Куки в ответе нет: сеанса нет.

Без `open=true` придут все три происшествия, новые сверху, и
`"total":3`.

**4. Отказы.** Большая страница, запрос без входа и вход под `viewer`:

```bash
curl -i -u admin:admin-local "http://localhost:8080/game-day/incidents?size=500"
curl -i "http://localhost:8080/game-day/incidents"
curl -i -u viewer:viewer-local "http://localhost:8080/game-day/incidents"
```

На первый — `400` и наша форма:

```
{"code":"page_size_invalid","message":"Размер страницы — от 1 до 50"}
```

На второй — `401`. Среди заголовков — просьба войти, а тело — форма Boot:

```
HTTP/1.1 401
WWW-Authenticate: Basic realm="Realm"
…

{"timestamp":"…","status":401,"error":"Unauthorized","path":"/game-day/incidents"}
```

На третий — `403` и `{"timestamp":"…","status":403,"error":"Forbidden","path":"/game-day/incidents"}`.

Тела `401` и `403` — в форме Boot, как у неизвестного адреса в статье 4.
Отказала охрана, и до контроллера и нашего обработчика дело не дошло.
Тело собрал Boot на `/error` — для этого пересылка `ERROR` и открыта.
Порядок заголовков у тебя может быть другим.

Форма показа: `curl` и ответы `200`, `400`, `401`, `403` —
в пул-реквест. Как получить данные для показа — вопрос задачи. Где-то
хватит строк, вставленных руками в свою базу. А где-то данные должна
завести сама система — тогда их создают её же ручками.

**Почему показ — часть «готово».** В тестах вокруг проверяемого куска
многое подменено: заглушки, база из Testcontainers, MockMvc вместо
Tomcat, вход приложен к запросу из кода. Запуск — первое место, где всё
собрано по-настоящему: `.jar`, миграции, настройки из окружения, Tomcat,
`curl` с паролем. Поэтому в рабочем проекте «готово» значит не «влито»,
а «работает». Ревьюер видит вывод `curl` в пул-реквесте — что ручка
отвечает, а не что должна отвечать.

Посмотрел — останови приложение, `Ctrl+C`. Нужна чистая база —
пересоздай контейнер: `docker stop game-day-db` и снова `docker run`.

---

## Чек-лист: перед пул-реквестом

- [ ] **Контракт** таблицей: метод и путь, параметры с умолчаниями,
      ответ, ошибки с кодами, роли.
- [ ] **Таблица случаев**: у каждой строки — слой, где её ловишь.
- [ ] **Хранилище**: выборка страницей; `*IT` на данных, где ошибка
      была бы видна; уборка в `@AfterEach`.
- [ ] **Служба**: правила и транзакция, без HTTP; наружу — запись-ответ;
      юнит-тест с `MockitoExtension`.
- [ ] **Контроллер**: параметры → разбор страницы → служба; доступ —
      тем же способом, что у соседних ручек.
- [ ] **Веб-тест**: каждый ответ из таблицы ошибок; у `400` — `code`;
      вход — настоящий; при отказе служба не вызвана.
- [ ] **Сквозной тест** — один на ручку.
- [ ] **Строка в `DECLARED`**; без неё тест периметра красный — проверь.
- [ ] `./mvnw verify` зелёный; новые классы — 100% строк и веток
      (в рабочем проекте это покажет отчёт JaCoCo).
- [ ] **Показ**: `200`, `400`, `401`, `403` — вывод `curl` в пул-реквест.
- [ ] В пул-реквесте — «как я устроил ручку»: что выбрал и почему.

Так ручку готовят к ревью в рабочем проекте. Места с пометкой «выбор
журнала» в рабочей задаче решает тот, кто её делает. На ревью его
спросят, почему ответ годится для этой ручки и чем она отличается
от соседних.

---

## Проверь себя

Ответь своими словами — вслух или на бумаге. Не получается — перечитай
раздел.

1. Что в ручке-списке делает контроллер, что служба и что хранилище?
   Чего каждый из них не знает — и что это даёт тестам?
2. Сущность и запись-ответ совпадают полями. Почему ручка всё равно
   отдаёт запись? Объясни на примере заметки атакующего.
3. Почему `@Transactional` ставят на службу, а не на контроллер или
   хранилище?
4. Откуда в ответе берётся `total` и почему это не длина `items`? Чем
   `PageImpl` опасен в тесте с заглушкой?
5. Чем `401` отличается от `403`? Почему на `?size=500` без входа
   приходит `401`, а не `400`, и что теперь отвечает адрес, которого нет?
6. Почему тест на `?size=0` идёт под `admin`? Зачем при отказе проверять,
   что служба не вызвана, и зачем веб-тесту `@Import(SecurityConfig.class)`?
7. Юнит службы и веб-тест зелёные, а на показе ручка с `open=true`
   отдаёт и закрытые происшествия. Какой тест должен был это поймать
   и какие данные ему нужны?
8. Зачем тест периметра, если `denyAll` и так закрывает забытую ручку?
   И зачем показывать ручку живьём, если все тесты зелёные?

---

## Что дальше

Это последняя статья серии «От Java к Spring Boot». Журнал прошёл весь
путь: от оповещения без памяти до ручки со страницами, входом и тестами
на каждом слое.

Дальше — серия «От Spring к системе» о том, что встречается в задачах
после первых ручек. Это стенд в Docker, события в JSON, объекты-значения, данные
посложнее, метрики и тесты, которые сторожат правила проекта.
Начинается она со статьи 6 «Стенд своими руками».

## Первоисточники

* [Spring Framework: Using @Transactional](https://docs.spring.io/spring-framework/reference/data-access/transaction/declarative/annotations.html) —
  где ставить аннотацию и что значит `readOnly`;
* [Spring Data JPA: Query Methods](https://docs.spring.io/spring-data/jpa/reference/jpa/query-methods.html) —
  раздел Paging, Iterating Large Results, Sorting & Limiting: страницы
  и цена подсчёта;
* [Spring Security: Authorize HttpServletRequests](https://docs.spring.io/spring-security/reference/servlet/authorization/authorize-http-requests.html) —
  правила по путям, их порядок, `denyAll` в конце и пересылка `ERROR`;
* [Spring Security: Basic Authentication](https://docs.spring.io/spring-security/reference/servlet/authentication/passwords/basic.html) —
  как охрана отвечает `401` и просит войти;
* [Spring Security: Testing HTTP Basic Authentication](https://docs.spring.io/spring-security/reference/servlet/test/mockmvc/http-basic.html) —
  `httpBasic` в тестах MockMvc;
* [Spring Boot how-to: Testing](https://docs.spring.io/spring-boot/how-to/testing.html) —
  тесты с Spring Security и почему класс настроек охраны срез сам
  не берёт;
* [Mockito: javadoc класса Mockito](https://javadoc.io/doc/org.mockito/mockito-core/latest/org/mockito/Mockito.html) —
  `when`, `verify`, `thenAnswer` и строгие заглушки;
* [Spring Boot 4.0 Migration Guide](https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-4.0-Migration-Guide) —
  тестовые стартеры, `spring-boot-starter-security-test` и почему
  полям `@Mock` нужен `MockitoExtension`.

---

## Пример целиком — с импортами

Учебный пример. Запускай в песочнице `game-day` после статьи 4: всё,
что в ней есть, остаётся без изменений — `GameDayApplication`,
`GameDayProperties` с тестом, `application.yml` и `application-stand.yml`,
миграция `V1__game_day_incident.sql`, `TestcontainersConfiguration`,
общие `ErrorBody`, `ErrorHandler`, `NoSuchEntryException`
и `InvalidInputException`, журнал в `example.gameday.journal` (`Incident`,
`IncidentLog`, `DutyRoster`, `Notifier`, `ConsoleNotifier`,
`GameDayConfig`, `IncidentResponse`, `IncidentService`, `IncidentIds`,
`IncidentController`) и его тесты — кроме одного.

Что поменять: в `IncidentRepository` — два метода страниц;
в `IncidentControllerTest` — вход под `admin` и два случая отказа. Оба
файла ниже целиком.

Что добавить: два стартера в `pom.xml`; в `example.gameday` — `Pages`,
`PageBody` и настройку охраны `SecurityConfig`; в
`example.gameday.journal` — `IncidentListService`
и `IncidentListController`. Тесты: `PagesTest` и `PerimeterTest`
в `example.gameday`; `IncidentListServiceTest`, `IncidentServiceTest`,
`IncidentLogTest`, `IncidentPagesIT`, `IncidentListControllerTest`
и `IncidentListIT` в `example.gameday.journal`. Тестам на базе нужен
запущенный Docker, юнит-тестам и срезам — нет.

```xml
<!-- pom.xml: в <dependencies>, рядом с тем, что уже есть -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-security</artifactId>
</dependency>
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-security-test</artifactId>
    <scope>test</scope>
</dependency>
```

```java
// src/main/java/example/gameday/Pages.java
package example.gameday;

import org.springframework.data.domain.PageRequest;

/** Номер и размер страницы из запроса: умолчания и проверка — одни на все списки. */
public final class Pages {

    public static final int DEFAULT_SIZE = 20;
    public static final int MAX_SIZE = 50;

    private Pages() {
    }

    public static PageRequest request(Integer page, Integer size) {
        int number = 0;
        if (page != null) {
            number = page;
        }
        int rows = DEFAULT_SIZE;
        if (size != null) {
            rows = size;
        }
        if (number < 0) {
            throw new InvalidInputException("page_number_invalid", "Номер страницы — 0 или больше");
        }
        if (rows < 1 || rows > MAX_SIZE) {
            throw new InvalidInputException("page_size_invalid", "Размер страницы — от 1 до 50");
        }
        return PageRequest.of(number, rows);
    }
}
```

```java
// src/main/java/example/gameday/PageBody.java
package example.gameday;

import java.util.List;

/** Страница списка в ответе — одна форма на все списки. */
public record PageBody<T>(List<T> items, int page, int size, long total) {
}
```

```java
// src/main/java/example/gameday/SecurityConfig.java
package example.gameday;

import jakarta.servlet.DispatcherType;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.core.userdetails.User;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.provisioning.InMemoryUserDetailsManager;
import org.springframework.security.web.SecurityFilterChain;

/** Охрана песочницы: вход по Basic, пользователи в памяти, ручки журнала — только admin. */
@Configuration
public class SecurityConfig {

    @Bean
    public SecurityFilterChain security(HttpSecurity http) {
        http.authorizeHttpRequests(access -> access
                        .dispatcherTypeMatchers(DispatcherType.ERROR).permitAll()
                        .requestMatchers(HttpMethod.GET, "/game-day/incidents").hasRole("admin")
                        .requestMatchers(HttpMethod.GET, "/game-day/incidents/{id}").hasRole("admin")
                        .anyRequest().denyAll())
                .httpBasic(Customizer.withDefaults())
                .sessionManagement(session -> session
                        .sessionCreationPolicy(SessionCreationPolicy.STATELESS));
        return http.build();
    }

    @Bean
    public UserDetailsService users() {
        return new InMemoryUserDetailsManager(
                User.withUsername("admin").password("{noop}admin-local").roles("admin").build(),
                User.withUsername("viewer").password("{noop}viewer-local").roles("viewer").build());
    }
}
```

```java
// src/main/java/example/gameday/journal/IncidentRepository.java
package example.gameday.journal;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.util.List;
import java.util.UUID;

public interface IncidentRepository extends JpaRepository<Incident, UUID> {

    List<Incident> findByDutyName(String dutyName);

    List<Incident> findByFixedAtIsNull();

    @Query("select i from Incident i where i.dutyName = ?1 and i.fixedAt is null order by i.detectedAt")
    List<Incident> findOpenOf(String dutyName);

    Page<Incident> findAllByOrderByDetectedAtDesc(Pageable pageable);

    Page<Incident> findByFixedAtIsNullOrderByDetectedAtDesc(Pageable pageable);
}
```

```java
// src/main/java/example/gameday/journal/IncidentListService.java
package example.gameday.journal;

import example.gameday.PageBody;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Transactional(readOnly = true)
public class IncidentListService {

    private final IncidentRepository repository;

    public IncidentListService(IncidentRepository repository) {
        this.repository = repository;
    }

    public PageBody<IncidentResponse> list(Pageable pageable, boolean openOnly) {
        Page<Incident> found;
        if (openOnly) {
            found = repository.findByFixedAtIsNullOrderByDetectedAtDesc(pageable);
        } else {
            found = repository.findAllByOrderByDetectedAtDesc(pageable);
        }
        Page<IncidentResponse> responses = found.map(IncidentResponse::of);
        return new PageBody<>(responses.getContent(), pageable.getPageNumber(), pageable.getPageSize(),
                responses.getTotalElements());
    }
}
```

```java
// src/main/java/example/gameday/journal/IncidentListController.java
package example.gameday.journal;

import example.gameday.PageBody;
import example.gameday.Pages;
import org.springframework.data.domain.PageRequest;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class IncidentListController {

    private final IncidentListService service;

    public IncidentListController(IncidentListService service) {
        this.service = service;
    }

    // доступ: только admin — в SecurityConfig
    @GetMapping("/game-day/incidents")
    public PageBody<IncidentResponse> list(
            @RequestParam(name = "page", required = false) Integer page,
            @RequestParam(name = "size", required = false) Integer size,
            @RequestParam(name = "open", defaultValue = "false") boolean open) {
        PageRequest pageRequest = Pages.request(page, size);
        return service.list(pageRequest, open);
    }
}
```

```java
// src/test/java/example/gameday/PagesTest.java
package example.gameday;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.springframework.data.domain.PageRequest;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class PagesTest {

    @Test
    void defaultsWhenNothingCame() {
        assertThat(Pages.request(null, null)).isEqualTo(PageRequest.of(0, 20));
    }

    @Test
    void keepsWhatCame() {
        assertThat(Pages.request(3, 50)).isEqualTo(PageRequest.of(3, 50));
    }

    @ParameterizedTest(name = "page={0}, size={1} → {2}")
    @CsvSource(delimiter = '|', nullValues = "null", textBlock = """
            -1   | null | page_number_invalid
            null | 0    | page_size_invalid
            null | 51   | page_size_invalid
            """)
    void rejectsBadNumbers(Integer page, Integer size, String code) {
        assertThatThrownBy(() -> Pages.request(page, size))
                .isInstanceOfSatisfying(InvalidInputException.class,
                        e -> assertThat(e.getCode()).isEqualTo(code));
    }
}
```

```java
// src/test/java/example/gameday/PerimeterTest.java
package example.gameday;

import example.gameday.journal.IncidentListService;
import example.gameday.journal.IncidentService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.web.bind.annotation.RequestMethod;
import org.springframework.web.servlet.mvc.method.annotation.RequestMappingHandlerMapping;

import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/** Тест периметра: каждая ручка приложения объявлена в DECLARED — метод, путь и кого пускают. */
@WebMvcTest
class PerimeterTest {

    static final List<Endpoint> DECLARED = List.of(
            new Endpoint("GET", "/game-day/incidents/{id}", "admin"),
            new Endpoint("GET", "/game-day/incidents", "admin"));

    @Autowired
    private RequestMappingHandlerMapping mappings;

    @MockitoBean
    private IncidentService incidentService;

    @MockitoBean
    private IncidentListService incidentListService;

    @Test
    void everyEndpointIsDeclared() {
        List<String> found = new ArrayList<>();
        mappings.getHandlerMethods().forEach((mapping, handler) -> {
            if (handler.getBeanType().getPackageName().startsWith("example.gameday")) {
                for (RequestMethod method : mapping.getMethodsCondition().getMethods()) {
                    for (String path : mapping.getPatternValues()) {
                        found.add(method + " " + path);
                    }
                }
            }
        });
        List<String> declared = new ArrayList<>();
        for (Endpoint endpoint : DECLARED) {
            declared.add(endpoint.method() + " " + endpoint.path());
        }
        assertThat(found).containsExactlyInAnyOrderElementsOf(declared);
    }

    record Endpoint(String method, String path, String role) {
    }
}
```

```java
// src/test/java/example/gameday/journal/IncidentListServiceTest.java
package example.gameday.journal;

import example.gameday.PageBody;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;

import java.time.Instant;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class IncidentListServiceTest {

    private static final Instant T0 = Instant.parse("2026-10-05T09:15:00Z");

    @Mock
    private IncidentRepository repository;

    private IncidentListService service;

    @BeforeEach
    void setUp() {
        service = new IncidentListService(repository);
    }

    @Test
    void returnsPageWithTotalFromRepository() {
        Incident fresh = new Incident("лента стоит", T0.plusSeconds(120), "duty-1");
        Incident old = new Incident("брокер молчит", T0, "duty-2");
        when(repository.findAllByOrderByDetectedAtDesc(PageRequest.of(0, 2)))
                .thenReturn(new PageImpl<>(List.of(fresh, old), PageRequest.of(0, 2), 3));

        PageBody<IncidentResponse> page = service.list(PageRequest.of(0, 2), false);

        assertThat(page.items()).containsExactly(
                new IncidentResponse(null, "лента стоит", T0.plusSeconds(120), null, "duty-1"),
                new IncidentResponse(null, "брокер молчит", T0, null, "duty-2"));
        assertThat(page.page()).isEqualTo(0);
        assertThat(page.size()).isEqualTo(2);
        assertThat(page.total()).isEqualTo(3);
    }

    @Test
    void openOnlyAsksForOpenIncidents() {
        when(repository.findByFixedAtIsNullOrderByDetectedAtDesc(PageRequest.of(2, 10)))
                .thenReturn(new PageImpl<>(List.of(), PageRequest.of(2, 10), 0));

        service.list(PageRequest.of(2, 10), true);

        verify(repository).findByFixedAtIsNullOrderByDetectedAtDesc(PageRequest.of(2, 10));
    }

    @Test
    void emptyJournalIsEmptyPage() {
        when(repository.findAllByOrderByDetectedAtDesc(PageRequest.of(0, 20)))
                .thenReturn(new PageImpl<>(List.of(), PageRequest.of(0, 20), 0));

        PageBody<IncidentResponse> page = service.list(PageRequest.of(0, 20), false);

        assertThat(page.items()).isEmpty();
        assertThat(page.total()).isEqualTo(0);
    }
}
```

```java
// src/test/java/example/gameday/journal/IncidentServiceTest.java
package example.gameday.journal;

import example.gameday.NoSuchEntryException;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class IncidentServiceTest {

    private static final UUID ID = UUID.fromString("7d1e3c52-9a4b-4f10-8c2d-1b2a3c4d5e6f");

    @Mock
    private IncidentRepository repository;

    @Test
    void getReturnsResponse() {
        IncidentService service = new IncidentService(repository);
        when(repository.findById(ID)).thenReturn(Optional.of(
                new Incident("стенд не отвечает", Instant.parse("2026-10-05T09:15:00Z"), "duty-1")));

        assertThat(service.get(ID).title()).isEqualTo("стенд не отвечает");
    }

    @Test
    void getThrowsWhenNotFound() {
        IncidentService service = new IncidentService(repository);
        when(repository.findById(ID)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.get(ID))
                .isInstanceOfSatisfying(NoSuchEntryException.class,
                        e -> assertThat(e.getCode()).isEqualTo("incident_not_found"));
    }
}
```

```java
// src/test/java/example/gameday/journal/IncidentLogTest.java
package example.gameday.journal;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class IncidentLogTest {

    private static final Instant T0 = Instant.parse("2026-10-05T09:15:00Z");

    @Mock
    private IncidentRepository incidents;

    @Mock
    private Notifier notifier;

    @Test
    void addNotifiesDutyWithDetectionTime() {
        when(incidents.save(any(Incident.class))).thenAnswer(call -> call.getArgument(0));
        IncidentLog log = new IncidentLog(new DutyRoster("duty-1"), notifier,
                Clock.fixed(T0, ZoneOffset.UTC), incidents);

        log.add("Брокер не отвечает");

        verify(notifier).send("duty-1", "Брокер не отвечает — замечено 2026-10-05T09:15:00Z");
    }
}
```

```java
// src/test/java/example/gameday/journal/IncidentPagesIT.java
package example.gameday.journal;

import example.gameday.TestcontainersConfiguration;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;

import java.time.Instant;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest
@Import(TestcontainersConfiguration.class)
class IncidentPagesIT {

    private static final Instant T0 = Instant.parse("2026-10-05T09:15:00Z");

    @Autowired
    private IncidentRepository incidents;

    @BeforeEach
    void fillJournal() {
        incidents.save(new Incident("брокер молчит", T0, "duty-1"));
        incidents.save(new Incident("лента стоит", T0.plusSeconds(120), "duty-2"));
        Incident fixed = new Incident("письма копятся", T0.plusSeconds(240), "duty-1");
        fixed.fix(T0.plusSeconds(600));
        incidents.save(fixed);
    }

    @AfterEach
    void cleanUp() {
        incidents.deleteAll();
    }

    @Test
    void allNewestFirst() {
        Page<Incident> page = incidents.findAllByOrderByDetectedAtDesc(PageRequest.of(0, 3));

        assertThat(page.getContent()).extracting(Incident::getTitle)
                .containsExactly("письма копятся", "лента стоит", "брокер молчит");
        assertThat(page.getTotalElements()).isEqualTo(3);
    }

    @Test
    void openOnlyNewestFirst() {
        Page<Incident> page = incidents.findByFixedAtIsNullOrderByDetectedAtDesc(PageRequest.of(0, 1));

        assertThat(page.getContent()).extracting(Incident::getTitle).containsExactly("лента стоит");
        assertThat(page.getTotalElements()).isEqualTo(2);
    }

    @Test
    void pageBeyondEndIsEmpty() {
        Page<Incident> page = incidents.findAllByOrderByDetectedAtDesc(PageRequest.of(5, 2));

        assertThat(page.getContent()).isEmpty();
        assertThat(page.getTotalElements()).isEqualTo(3);
    }
}
```

```java
// src/test/java/example/gameday/journal/IncidentListControllerTest.java
package example.gameday.journal;

import example.gameday.PageBody;
import example.gameday.SecurityConfig;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.assertj.MockMvcTester;
import org.springframework.test.web.servlet.request.RequestPostProcessor;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

@WebMvcTest(IncidentListController.class)
@Import(SecurityConfig.class)
class IncidentListControllerTest {

    private static final String PATH = "/game-day/incidents";
    private static final UUID ID = UUID.fromString("7d1e3c52-9a4b-4f10-8c2d-1b2a3c4d5e6f");
    private static final Instant T0 = Instant.parse("2026-10-05T09:15:00Z");
    private static final RequestPostProcessor ADMIN =
            SecurityMockMvcRequestPostProcessors.httpBasic("admin", "admin-local");
    private static final RequestPostProcessor VIEWER =
            SecurityMockMvcRequestPostProcessors.httpBasic("viewer", "viewer-local");

    @Autowired
    private MockMvcTester mvc;

    @MockitoBean
    private IncidentListService service;

    @Test
    void returnsPage() {
        when(service.list(PageRequest.of(0, 2), false)).thenReturn(new PageBody<>(
                List.of(new IncidentResponse(ID, "лента стоит", T0, null, "duty-1")), 0, 2, 3));

        assertThat(mvc.get().uri(PATH).param("page", "0").param("size", "2").with(ADMIN))
                .hasStatusOk()
                .bodyJson().isStrictlyEqualTo("""
                        {"items":[{"id":"7d1e3c52-9a4b-4f10-8c2d-1b2a3c4d5e6f","title":"лента стоит",
                                   "detectedAt":"2026-10-05T09:15:00Z","fixedAt":null,"dutyName":"duty-1"}],
                         "page":0,"size":2,"total":3}
                        """);
    }

    @Test
    void defaultsWhenNoParams() {
        when(service.list(PageRequest.of(0, 20), false))
                .thenReturn(new PageBody<>(List.of(), 0, 20, 0));

        assertThat(mvc.get().uri(PATH).with(ADMIN)).hasStatusOk();

        verify(service).list(PageRequest.of(0, 20), false);
    }

    @ParameterizedTest(name = "{0}={1} → 400 {2}")
    @CsvSource(delimiter = '|', textBlock = """
            page | -1 | page_number_invalid
            size | 0  | page_size_invalid
            size | 51 | page_size_invalid
            """)
    void rejectsBadPageParams(String name, String value, String code) {
        assertThat(mvc.get().uri(PATH).param(name, value).with(ADMIN))
                .hasStatus(HttpStatus.BAD_REQUEST)
                .bodyJson().extractingPath("$.code").isEqualTo(code);
        verifyNoInteractions(service);
    }

    @Test
    void rejectsWithoutLogin() {
        assertThat(mvc.get().uri(PATH)).hasStatus(HttpStatus.UNAUTHORIZED);
        verifyNoInteractions(service);
    }

    @Test
    void refusesViewer() {
        assertThat(mvc.get().uri(PATH).with(VIEWER)).hasStatus(HttpStatus.FORBIDDEN);
        verifyNoInteractions(service);
    }
}
```

```java
// src/test/java/example/gameday/journal/IncidentControllerTest.java
package example.gameday.journal;

import example.gameday.NoSuchEntryException;
import example.gameday.SecurityConfig;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpStatus;
import org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.assertj.MockMvcTester;
import org.springframework.test.web.servlet.request.RequestPostProcessor;

import java.time.Instant;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

@WebMvcTest(IncidentController.class)
@Import(SecurityConfig.class)
class IncidentControllerTest {

    private static final String PATH = "/game-day/incidents/{id}";
    private static final UUID ID = UUID.fromString("7d1e3c52-9a4b-4f10-8c2d-1b2a3c4d5e6f");
    private static final RequestPostProcessor ADMIN =
            SecurityMockMvcRequestPostProcessors.httpBasic("admin", "admin-local");
    private static final RequestPostProcessor VIEWER =
            SecurityMockMvcRequestPostProcessors.httpBasic("viewer", "viewer-local");

    @Autowired
    private MockMvcTester mvc;

    @MockitoBean
    private IncidentService service;

    @Test
    void returnsIncident() {
        when(service.get(ID)).thenReturn(new IncidentResponse(ID, "Брокер не отвечает",
                Instant.parse("2026-10-14T10:05:00Z"), null, "duty-1"));

        assertThat(mvc.get().uri(PATH, ID).with(ADMIN))
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

        assertThat(mvc.get().uri(PATH, ID).with(ADMIN))
                .hasStatus(HttpStatus.NOT_FOUND)
                .bodyJson().extractingPath("$.code").isEqualTo("incident_not_found");
    }

    @ParameterizedTest(name = "{0} → 400")
    @ValueSource(strings = {"abc", "1-1-1-1-1"})
    void badIdIs400(String badId) {
        assertThat(mvc.get().uri(PATH, badId).with(ADMIN))
                .hasStatus(HttpStatus.BAD_REQUEST)
                .bodyJson().extractingPath("$.code").isEqualTo("incident_id_invalid");
        verifyNoInteractions(service);
    }

    @Test
    void rejectsWithoutLogin() {
        assertThat(mvc.get().uri(PATH, ID)).hasStatus(HttpStatus.UNAUTHORIZED);
        verifyNoInteractions(service);
    }

    @Test
    void refusesViewer() {
        assertThat(mvc.get().uri(PATH, ID).with(VIEWER)).hasStatus(HttpStatus.FORBIDDEN);
        verifyNoInteractions(service);
    }
}
```

```java
// src/test/java/example/gameday/journal/IncidentListIT.java
package example.gameday.journal;

import example.gameday.TestcontainersConfiguration;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors;
import org.springframework.test.web.servlet.assertj.MockMvcTester;
import org.springframework.test.web.servlet.request.RequestPostProcessor;

import java.time.Instant;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest
@AutoConfigureMockMvc
@Import(TestcontainersConfiguration.class)
class IncidentListIT {

    private static final Instant T0 = Instant.parse("2026-10-05T09:15:00Z");
    private static final RequestPostProcessor ADMIN =
            SecurityMockMvcRequestPostProcessors.httpBasic("admin", "admin-local");

    @Autowired
    private MockMvcTester mvc;

    @Autowired
    private IncidentRepository incidents;

    @AfterEach
    void cleanUp() {
        incidents.deleteAll();
    }

    @Test
    void adminGetsOpenIncidentsNewestFirst() {
        Incident older = incidents.save(new Incident("брокер молчит", T0, "duty-1"));
        Incident newer = incidents.save(new Incident("лента стоит", T0.plusSeconds(120), "duty-2"));
        Incident fixed = new Incident("письма копятся", T0.plusSeconds(240), "duty-1");
        fixed.fix(T0.plusSeconds(600));
        incidents.save(fixed);

        assertThat(mvc.get().uri("/game-day/incidents").param("open", "true").with(ADMIN))
                .hasStatusOk()
                .bodyJson().isStrictlyEqualTo("""
                        {"items":[
                            {"id":"%s","title":"лента стоит","detectedAt":"2026-10-05T09:17:00Z",
                             "fixedAt":null,"dutyName":"duty-2"},
                            {"id":"%s","title":"брокер молчит","detectedAt":"2026-10-05T09:15:00Z",
                             "fixedAt":null,"dutyName":"duty-1"}],
                         "page":0,"size":20,"total":2}
                        """.formatted(newer.getId(), older.getId()));
    }
}
```
