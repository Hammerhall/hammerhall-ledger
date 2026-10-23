# Spring Boot 4 для самых маленьких

> «От Java к Spring Boot» · статья 2 · читать минут 25
>
> **Для кого.** Ты дочитал статьи 0 и 1 и завёл песочницу `game-day`
> со start.spring.io. Spring Boot пока не трогал.
>
> **Что будет.** Как Boot стартует и что делает за тебя; какие стартеры
> Boot 4 встретятся в рабочем проекте и где интернет называет их
> по-старому; как приложение получает настройки из файла, профиля
> и окружения и проверяет их при старте.
>
> **Откуда статья.** Раздел «Буткемп / Лаборатория» — о том, как пишут
> код команды Hammerhall: буткемп работает в открытых репозиториях,
> лаборатория — в закрытых. Серия «От Java к Spring Boot» — то, что
> нужно новичку до первой задачи на Spring Boot 4. Примеры — учебные:
> их можно повторить у себя.

---

## Зачем Spring Boot

В статье 1 контейнер для журнала игрового дня мы поднимали сами
в `GameDayApp`, а бины без `@Component` описывали в `GameDayConfig`.
Для четырёх бинов это терпимо.

Рабочему сервису нужно больше: веб-сервер, перевод записей в JSON, база, метрики,
настройки для стенда и для боевого — сервера, где работают настоящие
пользователи. За каждым пунктом — десятки бинов,
которые надо создать и правильно связать. Руками это сотни бинов
и неделя чтения документации — ещё до первой строки своего кода.

**Spring Boot** — это Spring с готовыми решениями по умолчанию. Как
квартира с мебелью: жить можно с первого дня, а не нравится шкаф —
ставишь свой, и старый уносят. Контейнер, бины, внедрение — всё то же,
что в статье 1.

В рабочем проекте на Boot стоит всё: часы из статьи 1, настройки,
веб и база. Эта статья — про этот фундамент.

Сквозной пример — тот же журнал в той же песочнице: переведём его
на Boot и дадим ему настройки игры — сколько она длится, какое
стоп-слово, сколько атакующих.

---

## Часть 1. Как Boot стартует

### Класс приложения

У Boot-приложения есть **класс приложения** с методом `main`. В песочнице
его создал Initializr — это `GameDayApplication`, который статья 1
просила не трогать. Теперь он главный. Допиши в `main` то же, что было
в `GameDayApp`:

```java
@SpringBootApplication                                             // «это приложение на Boot»
public class GameDayApplication {

    public static void main(String[] args) {
        var context = SpringApplication.run(GameDayApplication.class, args);   // поднять всё
        context.getBean(IncidentLog.class).add("Брокер не отвечает");          // заглянуть, как в статье 1
    }
}
```

В коротких примерах, как и в статье 0, нет строк `import` — они
в полном примере в конце.

`var` — «тип переменной выведи сам». `SpringApplication.run` делает то,
что в статье 1 делал `new AnnotationConfigApplicationContext(GameDayConfig.class)`,
и больше: читает настройки, включает автонастройку (о ней ниже)
и запускает веб-сервер, если он есть в проекте.

`@SpringBootApplication` говорит три вещи: этот класс — конфигурация, как
`GameDayConfig`; ищи классы с `@Component`, `@Service` и `@Configuration`
(она тоже считается компонентом) в пакете этого класса и во всех
пакетах ниже — как `@ComponentScan`; включи автонастройку.

Поэтому класс приложения кладут в **корень пакетов** — самый верхний
пакет проекта, внутри которого лежат все остальные. В песочнице корень —
`example.gameday`: там `GameDayApplication`, а журнал из статьи 1 —
в `example.gameday.journal`, внутри корня, и Boot найдёт его сам.
В рабочем проекте так же.

⚠️ Класс в пакете **рядом** с корнем, скажем `example.tools`,
сканирование не увидит. Просит его кто-то в конструкторе — старт упадёт
с ошибкой «нужен бин такого-то типа, а его нет». Не просит — он молча
не появится, хотя `@Component` на месте.

### Журнал на Boot

Что поменять в песочнице:

* в `example.gameday.journal` удали `GameDayApp` и `HandMadeApp`:
  контекст теперь поднимает `GameDayApplication`, и `main` пусть будет
  один;
* в `GameDayConfig` убери `@ComponentScan`: сканирует теперь
  `@SpringBootApplication`, и сам `GameDayConfig` он найдёт — тот
  внутри корня. Бины `DutyRoster` и `Clock` остаются.

Запусти `GameDayApplication` зелёным треугольником рядом с `main`.
Сначала побегут строки, которые Boot печатает о своей работе, — это
**лог**. Не путай с нашим журналом игрового дня: журнал — про
происшествия, лог — про само приложение. После лога — знакомое:

```
[оповещение] duty-1: Брокер не отвечает — замечено 2026-10-05T09:15:03.512704831Z
```

Журнал собран, только контекст поднял Boot. Потом приложение
завершится. Так и должно быть: веб-сервера в песочнице нет, ждать
запросов некому.

### Автонастройка

Откуда Boot знает, какие бины нужны, кроме твоих? Он смотрит, что
подключено к проекту.

**Автонастройка** (auto-configuration) — готовые `@Configuration`-классы
внутри Boot, только с условиями. Правило: **если в проекте есть стартер
технологии X и ты не сделал свой бин — Boot сделает свой.**

Пример из рабочего проекта. Подключишь стартер веба — с ним приедет модуль Boot
для Jackson (библиотеки для JSON из статьи 0). Boot сам создаст бин
`JsonMapper`, главный объект Jackson, и его можно просить
в конструкторе. Сам Jackson можно подключить и отдельной зависимостью,
как в `pom.xml` из статьи 0. Но без модуля Boot бин никто не создаст,
почему — в части 2.

Так же со стартером веба Boot поднимет Tomcat (веб-сервер, о нём ниже).
А со стартером Flyway применит при старте миграции: Flyway — библиотека,
которая меняет таблицы базы скриптами-миграциями.

🔑 **Свой бин побеждает.** Объявишь собственный бин `JsonMapper` — Boot
свой делать не станет. Это и есть «не нравится шкаф — ставишь свой».

⚠️ В интернете, чтобы заменить маппер, объявляют бин `ObjectMapper`
из `com.fasterxml.jackson.databind`. Это Boot 2–3 и Jackson 2. В Jackson 3
класс `ObjectMapper` тоже есть (`tools.jackson.databind.ObjectMapper`),
но бин этого типа Boot заменой уже не считает — нужен именно
`JsonMapper` из `tools.jackson.databind.json`.

### Встроенный веб-сервер

**Веб-сервер** — программа, которая слушает сетевой порт, принимает
запросы (из браузера или от другой программы) и передаёт их приложению.
Запросы подробно — в продолжении серии.

Раньше сервер ставили на машину отдельно и подкладывали приложение ему
внутрь: две программы, две версии — и вечное «у меня работает, а там
нет». Boot переворачивает это: **сервер внутри приложения, а не
приложение внутри сервера.** Сервер — ещё одна библиотека в `.jar`;
приложение само поднимает его и остаётся ждать запросов.

**Tomcat** — веб-сервер, который Boot встраивает по умолчанию.
В учебных проектах его нет: программы там консольные. На работе сервис
отвечает по сети, и сервер нужен всегда. Ставить Tomcat не надо: он
приезжает со стартером `spring-boot-starter-webmvc` и запускается сам,
внутри `SpringApplication.run`. В логе старта
будет строка о нём с номером порта.

`./mvnw package` собирает один `.jar`: код, библиотеки и, если есть,
Tomcat. **Выкатка** — положить этот файл на машину и запустить
`java -jar`; так сервис и запускают на стенде. В песочнице:

```bash
./mvnw package
java -jar target/game-day-0.0.1-SNAPSHOT.jar      # имя — из artifactId и version в pom.xml
```

---

## Часть 2. Стартеры Boot 4

### Почему стартеры стали мельче

Именно стартер (помнишь, набор библиотек одним пакетом) и включает
автонастройку. В Boot 4 сам Boot разрезан на мелкие **модули** — по
одному на технологию. Автонастройка технологии лежит в её модуле,
модуль приносит стартер `spring-boot-starter-<технология>`; нет
стартера — настраивать нечего. Отсюда две перемены, о которые
спотыкаются: технологиям, которым раньше хватало сторонней библиотеки,
теперь нужен стартер; а тестовые инструменты разъехались по стартерам
`spring-boot-starter-<технология>-test`.

### Стартеры, которые встретятся в рабочем проекте

**Тестовый срез** — тест, который поднимает не всё приложение, а один
слой; о срезах — в продолжении серии. Срез базы (`@DataJpaTest`)
в рабочем проекте не пишут: хранилища проверяют на настоящей базе.

**Actuator** — служебные адреса, по которым приложение рассказывает
о себе. Программу из курса запускаешь сам и видишь, что она работает;
сервис на стенде крутится без тебя, и кто-то должен регулярно
спрашивать «ты жив?». **Пробы** — две такие проверки: «процесс жив»
(liveness) и «готов принимать запросы» (readiness). Actuator приезжает
со стартером `spring-boot-starter-actuator`; в песочнице его нет.
В приложении с Actuator и стартером веба открой
`http://localhost:8080/actuator/health`: `"status":"UP"` в ответе
значит «жив».

| стартер | что приносит | ⚠️ в интернете (Boot 2–3) → в Boot 4 |
|---|---|---|
| `spring-boot-starter-webmvc` | веб: Spring MVC, Tomcat, Jackson | `spring-boot-starter-web` → устарел |
| `spring-boot-starter-validation` | проверки (часть 3); в `webmvc` не входит | — |
| `spring-boot-starter-actuator` | Actuator | пробы включают настройкой → включены сами |
| `spring-boot-starter-data-jpa` | работа с базой | — |
| `spring-boot-starter-flyway` **и** `org.flywaydb:flyway-database-postgresql` | миграции; Postgres для Flyway | один `flyway-core` → миграции **молча** не идут |
| `spring-boot-starter-<технология>-test` | тестовые срезы | «всё в `spring-boot-starter-test`» → у каждой технологии свой |

У всех `groupId` — `org.springframework.boot`, кроме Flyway для Postgres;
версии подставляет `<parent>`, как в статье 0.

В рабочем проекте зависимости добавляет мидл (статья 0), в песочнице — ты сам.
Советует стартер туториал или LLM — сверь имя с таблицей.

---

## Часть 3. Настройки

### Зачем настройки вне кода

Стоп-слово меняют к каждой игре. Атакующих на стенде четверо, а у тебя
на машине хватит и двоих. Зашьёшь значения в код — на каждую перемену
нужна новая сборка. Поэтому они живут вне кода, в **настройках**:
именованных значениях, которые приложение читает при старте. Одна
сборка — разные значения на разных машинах.

### application.yml и формат YAML

Настройки лежат в `src/main/resources` — папке для файлов, которые
не код, но едут в `.jar`. Initializr положил туда `application.properties`:
удали его и создай `application.yml`. В рабочем проекте — YAML, а два формата
в одном проекте только путают.

**YAML** — текстовый формат «ключ: значение», где вложенность
показывают отступами:

```yaml
hammerhall:                      # уровень 1
  game-day:                      # уровень 2 — на два пробела глубже
    stop-word: test-stop-word
    attackers: 4                 # ключ целиком: hammerhall.game-day.attackers
```

* отступ — только пробелы; у ключей одного уровня — одинаковый;
* после `#` — комментарий, как `//` в Java;
* полное имя настройки — путь через точки: `hammerhall.game-day.attackers`.
  Так её называют в задачах и в тестах: `hammerhall.game-day.attackers=4`;
* в YAML имена пишут через дефис (`stop-word`), в Java — верблюжьим
  регистром (`stopWord`); Boot сопоставляет их сам.

⚠️ Отступ — часть смысла. Сдвинь последнюю строку, `attackers`, на два
пробела левее — и она станет `hammerhall.attackers`, настройкой, которую
никто не читает. Ошибки не будет: Boot молча возьмёт умолчание.

### Профили: свой набор для каждой машины

**Профиль** — именованный набор настроек для одного окружения. Рядом
с `application.yml` кладут файлы `application-<профиль>.yml`. При
включённом профиле Boot читает оба файла, и где ключ есть в обоих,
побеждает профильный.

```yaml
# application.yml — для всех
hammerhall:
  game-day:
    stop-word: test-stop-word    # чтобы запустить у себя
```

```yaml
# application-stand.yml — только с профилем stand
hammerhall:
  game-day:
    attackers: 4                 # на стенде атакуют вчетвером
```

Без профиля атакующих двое (это умолчание, о нём ниже), с профилем
`stand` — четверо. Профиль включают настройкой `spring.profiles.active`,
обычно — аргументом запуска (в IDE — поле Program arguments в настройках
запуска):

```bash
java -jar target/game-day-0.0.1-SNAPSHOT.jar --spring.profiles.active=stand
```

Внутри профильного файла `spring.profiles.active` задавать нельзя.
В рабочем проекте три файла: `application.yml` для всех, `application-stand.yml`
для стенда и `application-prod.yml` для боевого.

### Переменные окружения поверх файла

Настоящее стоп-слово в репозиторий класть незачем: смена слова —
не повод для сборки.

**Переменная окружения** — именованное значение, которое система
передаёт программе при запуске; живёт на машине, а не в репозитории.
Задают её перед запуском: в консоли и Git Bash —
`export GAME_DAY_STOP_WORD=…`, в IDE — поле Environment variables
в настройках запуска. В настройки её берут двумя способами.

**Ссылкой в файле** — `${ИМЯ}` Spring заменит значением переменной:

```yaml
# application-stand.yml
hammerhall:
  game-day:
    attackers: 4
    stop-word: ${GAME_DAY_STOP_WORD}   # на стенде — из окружения
```

Теперь профиль `stand` без этой переменной не поднимется — так и
задумано, это защита из «Ловушки» ниже.

Так в рабочем проекте устроены все секреты: в `application-prod.yml`
у паролей, ключей и токенов только `${ИМЯ}`. 🔴 У ссылки бывает умолчание
после двоеточия — `${ИМЯ:значение}`, но у секретов его нет никогда:
забудут переменную — и боевой тихо поднимется с паролем из репозитория.
Это правило стережёт отдельный тест.

**Без ссылки** — переменная, которая соответствует ключу, перекрывает
значение из обоих файлов. Имя строится так: точки заменить на `_`,
дефисы убрать, всё заглавными: `hammerhall.game-day.attackers` →
`HAMMERHALL_GAMEDAY_ATTACKERS`. Так можно включить и профиль:
переменная `SPRING_PROFILES_ACTIVE=stand` делает то же, что аргумент
`--spring.profiles.active=stand`.

### Настройки — в запись: @ConfigurationProperties

Читать настройки поштучно, по имени-строке, в каждом классе — значит
рассыпать имена по коду и ловить опечатки на игре. Boot предлагает
иначе: все настройки игры — в одной записи, и Boot заполнит её при
старте.

```java
@ConfigurationProperties("hammerhall.game-day")    // префикс: где лежат настройки игры
public record GameDayProperties(
        @DefaultValue("3h") Duration length,        // не задано — 3 часа
        String stopWord,                            // умолчания нет: оно своё к каждой игре
        @DefaultValue("2") int attackers) {         // не задано — двое
}
```

* `"hammerhall.game-day"` — **префикс**: для каждого поля записи Boot
  ищет настройку `hammerhall.game-day.<имя поля>`;
* Boot сам вызывает конструктор записи и передаёт значения, переведённые
  в нужный тип: строку `4` — в `int`, `3h` — в `Duration`. Это
  **привязка через конструктор**: сеттеров нет, после старта настройки
  не меняются;
* `Duration` — тип Java для длительности: `3h` — три часа, `90m` —
  девяносто минут, `30s` — тридцать секунд. ⚠️ Число без буквы —
  миллисекунды: `length: 3` — три тысячных секунды;
* `@DefaultValue("3h")` — **умолчание**, если настройку не задали вовсе.
  Оно стоит рядом с правилом, и тест без единой настройки видит то же,
  что приложение.

⚠️ В интернете ты увидишь над такой записью `@ConstructorBinding`. Это
Boot 2. У записи с одним конструктором он не нужен.

**Как Boot находит запись.** Поставь рядом с `@SpringBootApplication`
аннотацию `@ConfigurationPropertiesScan` — «найди все записи настроек
и заполни их». Ищет она, как сканирование, от пакета класса приложения
и ниже. Запись положи в `example.gameday`, рядом с `GameDayApplication`:
это настройки всего приложения. В рабочем проекте аннотация стоит
на классе приложения.

⚠️ Не ставь на запись `@Component`. Spring создаст её как обычный бин
и станет искать бины типа `Duration` и `int` для конструктора — и
не найдёт. Из настроек запись заполняется, только если её нашёл
`@ConfigurationPropertiesScan` или `@EnableConfigurationProperties`
(встретится в тесте).

Запись настроек — тоже бин: другой бин просит её параметром
конструктора, как любую зависимость. Заглянем в неё из `main`:

```java
var gameDay = context.getBean(GameDayProperties.class);
System.out.println("игра " + gameDay.length() + ", атакующих " + gameDay.attackers());
```

Без профиля — `игра PT3H, атакующих 2` (`PT3H` — так Java пишет три
часа). С профилем `stand` и переменной `GAME_DAY_STOP_WORD` —
`атакующих 4`; добавь `HAMMERHALL_GAMEDAY_ATTACKERS=6` — будет 6.
Стоп-слово не печатаем: что пришло из окружения, в лог не пишут.

💡 Упражнение: перенеси в настройки имя дежурного — `"duty-1"`
из `GameDayConfig`. Подсказка: метод с `@Bean` тоже может просить бины
параметрами.

### Проверка при старте: @Validated

Кто-то поставил `attackers: 0` — игра без атакующих. Или `length: 5m` —
игра кончится, не начавшись. Приложение поднимется, а ошибку заметят
в разгар игрового дня.

🔑 **Негодная настройка останавливает старт, а не игру.** Узнать о ней
при запуске, с именем настройки, дешевле, чем через три часа.

Проверкам нужна библиотека. Добавь в `pom.xml` песочницы стартер
(на start.spring.io он называется Validation):

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-validation</artifactId>
</dependency>
```

```java
@ConfigurationProperties("hammerhall.game-day")
@Validated                                                               // включить проверку
public record GameDayProperties(
        @DefaultValue("3h") @DurationMin(minutes = 30) Duration length,  // не короче 30 минут
        @NotBlank String stopWord,                                       // задано и не из одних пробелов
        @DefaultValue("2") @Min(1) int attackers) {                      // хотя бы один
}
```

* `@Validated` велит Boot проверить аннотации на полях заполненной
  записи. ⚠️ Без неё `@Min` и `@NotBlank` — украшения: их никто
  не проверит.
* `@NotBlank` и `@Min(1)` — из Jakarta Validation, стандарта проверок
  для Java; пакет `jakarta.validation.constraints`.
* ⚠️ `@DurationMin` в стандарте нет: она из Hibernate Validator, пакет
  `org.hibernate.validator.constraints.time`. Импорт из `jakarta`
  не найдётся.
* ⚠️ В старых туториалах те же аннотации — из `javax.validation`. Это
  Boot 2. В Boot 4 `javax.*` не поддерживается — только `jakarta.*`.

**Hibernate Validator** — библиотека, которая выполняет эти проверки:
аннотации только описывают правило. В учебных проектах проверки пишут
`if`-ами; на работе правил десятки, и их удобнее объявить аннотацией
рядом с полем. Библиотека приезжает со стартером выше, а вызывает её
Boot при старте для каждой записи с `@Validated`. Поставь
`attackers: 0` — приложение не стартует, а в логе будет примерно так:

```
APPLICATION FAILED TO START
…
    Property: hammerhall.game-day.attackers
    Value: "0"
    Reason: …
```

Для `stop-word` в такой строке будет `stopWord` — имя поля в Java.

💡 В юнит-тесте запись создают обычным `new`. Тогда работает только
компактный конструктор (он ниже), а аннотации проверяет и умолчания
подставляет Boot при старте. Поэтому в `new` передают все три значения.

### ⚠️ Ловушка: переменная окружения не подставилась

На стенде `stop-word: ${GAME_DAY_STOP_WORD}`, а переменную перед игрой
забыли задать. Кажется, `@NotBlank` поймает. Не поймает.

Заполняя запись настроек, Spring оставляет неподставленную ссылку как
есть: в `stopWord` придёт буквальная строка `${GAME_DAY_STOP_WORD}`. Она
не пустая — `@NotBlank` её пропустит. Тимлид скажет стоп-слово — и игра
не остановится: «правильное» стоп-слово теперь `${GAME_DAY_STOP_WORD}`.

Лечится компактным конструктором из статьи 0. Он пишется внутри записи
`GameDayProperties`, после заголовка — как в `TaskKey`:

```java
public GameDayProperties {
    if (stopWord != null && stopWord.contains("${")) {          // ссылка так и осталась ссылкой
        throw new IllegalArgumentException(
                "hammerhall.game-day.stop-word: стоп-слово не задано: переменная окружения не подставилась");
    }
}
```

* В тексте ошибки — имя настройки и причина: человек на стенде сразу
  поймёт, что задать.
* `stopWord != null &&` — потому что конструктор выполняется **раньше**
  проверок `@Validated`. Не задали стоп-слово вовсе — придёт `null`,
  и без этой проверки `stopWord.contains` бросит `NullPointerException`
  без слова о настройке. С ней `null` проходит дальше, и отказ даёт
  `@NotBlank` — с именем настройки.

Проверь: запусти с профилем `stand` без переменной — приложение
не поднимется, а в логе будет наш текст.

💡 Компактный конструктор — тот же единственный конструктор записи,
а не второй. `@ConstructorBinding` по-прежнему не нужен.

🔴 В рабочем проекте так защищены все секреты в записях настроек:
пароли, ключи, токены.

### Как проверить настройки тестом

**`ApplicationContextRunner`** — инструмент для тестов, который собирает
маленький контекст Spring прямо в тесте, только из названных классов
и настроек. Поднимать ради проверки настроек всё приложение долго,
а раннер отвечает за доли секунды: поднимется ли контекст и что
в бинах. Приезжает с `spring-boot-starter-test`; запуск — как у любого
JUnit-теста. В рабочем проекте так проверяют каждую запись настроек.

`application.yml` раннер не читает: тест видит только
`withPropertyValues` и `@DefaultValue`. Поэтому умолчания и живут
в записи.

```java
class GameDayPropertiesTest {

    @Configuration                                             // конфигурация только для теста
    @EnableConfigurationProperties(GameDayProperties.class)    // «создай и заполни эту запись»
    static class Config {
    }

    private final ApplicationContextRunner runner = new ApplicationContextRunner()
            .withUserConfiguration(Config.class);              // контекст — только из Config

    @Test
    void appliesDefaults() {
        runner.withPropertyValues("hammerhall.game-day.stop-word=test-stop-word")
                .run(context -> {                              // контекст собран — проверяем
                    GameDayProperties gameDay = context.getBean(GameDayProperties.class);
                    assertThat(gameDay.length()).isEqualTo(Duration.ofHours(3));
                    assertThat(gameDay.attackers()).isEqualTo(2);
                });
    }

    @Test
    void rejectsUnresolvedStopWord() {
        // имя, которого точно нет в окружении: иначе Spring подставит настоящее значение
        runner.withPropertyValues("hammerhall.game-day.stop-word=${GAME_DAY_TEST_UNSET_STOP_WORD}")
                .run(context -> {
                    assertThat(context).hasFailed();           // контекст не поднялся
                    assertThat(context.getStartupFailure())
                            .hasStackTraceContaining("переменная окружения не подставилась");
                });
    }
}
```

* `Config` — класс внутри класса теста, нужен только ему. В приложении
  запись находит `@ConfigurationPropertiesScan`, а здесь `Config` говорит
  то же явно;
* `run(context -> …)` — лямбда из статьи 0: в неё приходит контекст,
  собранный или нет. `getBean` в тесте можно — так заглядывают
  в контекст; в коде продукта — только конструктор;
* `hasFailed()` — «контекст не поднялся»; `hasStackTraceContaining` ищет
  текст в ошибке старта и во всех её причинах: Spring заворачивает
  ошибку в несколько слоёв. Прежде чем писать такую проверку, один раз
  выведи `context.getStartupFailure()` и прочитай целиком.

Это техника: один тест «поднялся», один — «не поднялся». Сколько тестов
и каких — решает таблица задачи.

---

## Проверь себя

Ответь своими словами — вслух или на бумаге. Не получается — перечитай
раздел.

1. Почему на запись настроек нельзя ставить `@Component` и как Boot её
   находит?
2. Почему класс приложения лежит в корне пакетов? Что будет с классом,
   который лежит рядом с корнем?
3. Объясни автонастройку. Почему без стартера веба бина `JsonMapper`
   нет, хотя Jackson в `pom.xml` есть? Как заменить бин, который сделал
   Boot?
4. «Сервер внутри приложения, а не приложение внутри сервера» — что это
   значит и что даёт при выкатке?
5. Туториал велит подключить `flyway-core` и `spring-boot-starter-web`.
   Что не так в Boot 4 и кто в рабочем проекте добавляет зависимости?
6. Ключ `attackers` есть в `application.yml`, в `application-stand.yml`
   и в окружении. Какое значение получит приложение с профилем `stand`?
7. Зачем `@Validated`, если `@Min` и `@NotBlank` уже стоят? Почему
   `@DurationMin` импортируется не из `jakarta`?
8. На стенде забыли переменную со стоп-словом. Почему `@NotBlank`
   не спасёт, что спасёт — и зачем там `stopWord != null`?

---

## Что дальше

Настройки есть, приложение стартует — пора хранить данные. Об этом
две следующие статьи: сначала таблица, миграция Flyway и проверка
на настоящей базе, потом сущность, хранилище и транзакция.

## Первоисточники

* [Spring Boot: Externalized Configuration](https://docs.spring.io/spring-boot/reference/features/external-config.html) —
  YAML, порядок источников, имена переменных окружения, записи
  с `@ConfigurationProperties`, проверки, запись `Duration`;
* [Spring Boot: Profiles](https://docs.spring.io/spring-boot/reference/features/profiles.html) —
  как включать профили;
* [Spring Boot 4.0 Migration Guide](https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-4.0-Migration-Guide) —
  модули, новые имена стартеров, что куда переехало: лучший ответ на
  «почему туториал не собирается».

---

## Пример целиком — с импортами

Учебный пример. Запускай в песочнице `game-day` из статьи 1.
В `example.gameday.journal` `DutyRoster`, `Notifier`, `ConsoleNotifier`,
`IncidentLog` — из статьи 1 без изменений; `GameDayApp`, `HandMadeApp`
и `application.properties` удалены; в `pom.xml` — стартер Validation.
Тест `GameDayApplicationTests` от Initializr поднимает всё приложение
с `application.yml` — поэтому стоп-слово в общем файле нужно и ему.

```java
// src/main/java/example/gameday/GameDayApplication.java
package example.gameday;

import example.gameday.journal.IncidentLog;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;

@SpringBootApplication
@ConfigurationPropertiesScan
public class GameDayApplication {

    public static void main(String[] args) {
        var context = SpringApplication.run(GameDayApplication.class, args);
        context.getBean(IncidentLog.class).add("Брокер не отвечает");

        var gameDay = context.getBean(GameDayProperties.class);
        System.out.println("игра " + gameDay.length() + ", атакующих " + gameDay.attackers());
    }
}
```

```java
// src/main/java/example/gameday/journal/GameDayConfig.java
package example.gameday.journal;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.time.Clock;

@Configuration
public class GameDayConfig {

    @Bean
    public DutyRoster dutyRoster() {
        return new DutyRoster("duty-1");
    }

    @Bean
    public Clock clock() {
        return Clock.systemUTC();
    }
}
```

```java
// src/main/java/example/gameday/GameDayProperties.java
package example.gameday;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import org.hibernate.validator.constraints.time.DurationMin;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;
import org.springframework.validation.annotation.Validated;

import java.time.Duration;

@ConfigurationProperties("hammerhall.game-day")
@Validated
public record GameDayProperties(
        @DefaultValue("3h") @DurationMin(minutes = 30) Duration length,
        @NotBlank String stopWord,
        @DefaultValue("2") @Min(1) int attackers) {

    public GameDayProperties {
        if (stopWord != null && stopWord.contains("${")) {
            throw new IllegalArgumentException(
                    "hammerhall.game-day.stop-word: стоп-слово не задано: переменная окружения не подставилась");
        }
    }
}
```

```yaml
# src/main/resources/application.yml
hammerhall:
  game-day:
    stop-word: test-stop-word
```

```yaml
# src/main/resources/application-stand.yml
hammerhall:
  game-day:
    attackers: 4
    stop-word: ${GAME_DAY_STOP_WORD}
```

```java
// src/test/java/example/gameday/GameDayPropertiesTest.java
package example.gameday;

import org.junit.jupiter.api.Test;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.context.annotation.Configuration;

import java.time.Duration;

import static org.assertj.core.api.Assertions.assertThat;

class GameDayPropertiesTest {

    @Configuration
    @EnableConfigurationProperties(GameDayProperties.class)
    static class Config {
    }

    private final ApplicationContextRunner runner = new ApplicationContextRunner()
            .withUserConfiguration(Config.class);

    @Test
    void appliesDefaults() {
        runner.withPropertyValues("hammerhall.game-day.stop-word=test-stop-word")
                .run(context -> {
                    GameDayProperties gameDay = context.getBean(GameDayProperties.class);
                    assertThat(gameDay.length()).isEqualTo(Duration.ofHours(3));
                    assertThat(gameDay.attackers()).isEqualTo(2);
                });
    }

    @Test
    void rejectsUnresolvedStopWord() {
        // имя, которого точно нет в окружении: иначе Spring подставит настоящее значение
        runner.withPropertyValues("hammerhall.game-day.stop-word=${GAME_DAY_TEST_UNSET_STOP_WORD}")
                .run(context -> {
                    assertThat(context).hasFailed();
                    assertThat(context.getStartupFailure())
                            .hasStackTraceContaining("переменная окружения не подставилась");
                });
    }
}
```
