# Стенд своими руками: Docker, образ, compose, `.env`, скрипты bash

> «От Spring к системе» · статья 6 · читать минут 35
>
> **Для кого.** Ты прочитал статьи 0–5, и у тебя есть песочница
> `game-day` после статьи 5: Postgres в контейнере, ручки журнала, вход
> по Basic. Docker стоит со статьи 3а. Bash знаешь на уровне `cd` и `ls`.
>
> **Что будет.** Как устроены образ и контейнер; Dockerfile и compose
> для песочницы с базой — с причиной каждой строки; почему проверку
> здоровья охрана пускает без пароля; два скрипта bash, которые не врут,
> когда что-то сломалось.
>
> **Откуда статья.** Раздел «Буткемп / Лаборатория» — о том, как пишут
> код команды Hammerhall: буткемп работает в открытых репозиториях,
> лаборатория — в закрытых. Серия «От Spring к системе» — следующий шаг
> после «От Java к Spring Boot»: как приложение живёт среди других
> программ. Примеры — учебные: их можно повторить у себя.

---

## Зачем стенд в контейнерах

Сейчас песочница поднимается в два приёма (статьи 3а–5). База — длинной
командой `docker run`. Приложение — `java -jar` с тремя переменными
`SPRING_DATASOURCE_*`, а с профилем `stand` ещё и с
`GAME_DAY_STOP_WORD` (статья 2). Забыл переменную — приложение
не поднялось. У коллеги JDK 21, а порт 5432 занят его собственным
Postgres — и вот «у меня работает, а у тебя нет».

Стенд рабочего сервиса — обычно несколько программ: база данных, брокер
сообщений, двойники соседних сервисов (программы вроде WireMock, которые
отвечают вместо настоящих записанными ответами) и сам сервис. Ставить
их руками — день работы, и через месяц версии у всех разные. Поэтому
стенд описан **файлами в репозитории**, и Docker поднимает его по ним
одной командой — одинаково у всех.

В рабочем проекте такие файлы пишут сами джуны, по задачам с кодом
и шагами. Здесь — как это устроено и что сломается, если сделать иначе.
Учимся на стенде для песочницы `game-day`: программ в нём две — база
и приложение, зато у каждой строки есть причина. Журнал игрового дня —
учебный пример.

---

## Часть 1. Docker: образ, контейнер, слой

### Docker

Docker Desktop ты поставил в статье 3а ради базы и до сих пор
запускал чужой образ, `postgres:17-alpine`. Теперь соберёшь свой. Перед
работой запусти Docker Desktop и проверь `docker version`, как в статье 3а.

### Образ и контейнер

В статье 3а об этом было в двух словах, теперь подробнее.

**Образ** (image) — неизменный снимок программы со всем, что ей нужно
для запуска: маленькая основа Linux, Java, твой `.jar`. **Контейнер** —
программа, запущенная из образа в изолированной коробке: свои файлы,
своя сеть, свои процессы.

Образ относится к контейнеру как класс к объекту: из одного образа —
сколько угодно контейнеров.

### Слой

Образ собран из **слоёв**, стопкой. Слой — набор изменений файлов: что
добавили, поменяли, удалили. Созданный слой больше не меняется. Поэтому
при пересборке Docker берёт из кэша каждый слой, для которого ничего
не изменилось. В выводе такие шаги помечены `CACHED`.

Контейнеру поверх слоёв образа дают свой слой для записи. Всё, что
программа записала в файлы, ложится туда и удаляется вместе
с контейнером.

🔑 Образ неизменный, контейнер одноразовый. Одинаковое у всех — в образе
и файлах репозитория; данные, которые должны пережить контейнер, —
в томе (часть 3).

### Реестр и тег

**Реестр** (registry) — хранилище, откуда скачивают образы; по
умолчанию — Docker Hub. Полное имя образа:

```
docker.io/library/eclipse-temurin:25-jre-alpine
│         │       │               └─ тег: Java 25, только среда запуска, основа alpine
│         │       └─ имя
│         └─ пространство: library — официальные образы
└─ реестр
```

Реестр и пространство обычно не пишут. **Тег** — метка после
двоеточия, обычно версия. Нет тега — Docker подставит `latest`.
`postgres:17-alpine` из статьи 3а читается так же: Postgres 17 на основе
alpine.

⚠️ `latest` — не «самая свежая версия», а тег по умолчанию, который
издатель двигает куда хочет: сейчас `eclipse-temurin:latest` — JDK 25
на Ubuntu, а не alpine. Сдвинет — и стенд завтра поднимется с другой
Java без правки в репозитории. Поэтому
в рабочем проекте у каждого образа тег с версией, и в `compose.yaml`,
и в `Dockerfile` это сторожит тест.

---

## Часть 2. Образ песочницы

### Actuator: «ты жив?»

Стенду нужно приложение, которое отвечает на «ты жив?», — Actuator
из статьи 2. Веб в песочнице уже есть (статья 4), добавь в `pom.xml`
один стартер:

```xml
<dependency>                                   <!-- служебные адреса, среди них /actuator/health -->
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>
```

Java-код пока не трогаем. Собери и запусти песочницу, как в статье 5: база —
`docker run` из статьи 3а, три переменные `SPRING_DATASOURCE_*`, затем
`./mvnw package` и `java -jar target/game-day-0.0.1-SNAPSHOT.jar`.
Спроси здоровье — в другом окне консоли:

```bash
curl -i http://127.0.0.1:8080/actuator/health
```

```
HTTP/1.1 401
WWW-Authenticate: Basic realm="Realm", charset="UTF-8"
…

{"timestamp":"…","status":401,"error":"Unauthorized","path":"/actuator/health"}
```

Не вошёл — `401`. Охрана из статьи 5 сработала как задумано: адреса
`/actuator/health` в её правилах нет, и его закрыл
`anyRequest().denyAll()`.

### 🔴 Здоровье — без входа, остальное — со входом

Кто спрашивает «ты жив?»? Docker — проверкой здоровья (часть 3), скрипт
стенда (часть 4), а на боевом сервере ещё программа, которая следит
за сервисами и перезапускает упавшие. Пароля ни у кого из них нет, и раздавать его
незачем: ответ health — одно слово, `UP` или `DOWN`, без данных журнала.
Поэтому health открывают без входа. Одна строка в `SecurityConfig`
из статьи 5:

```java
http.authorizeHttpRequests(access -> access
        .dispatcherTypeMatchers(DispatcherType.ERROR).permitAll()
        .requestMatchers(HttpMethod.GET, "/actuator/health").permitAll()        // здоровье — без входа
        .requestMatchers(HttpMethod.GET, "/game-day/incidents").hasRole("admin")
        …
```

`permitAll()` — пускать всех, даже не вошедших. Охрана читает правила
по порядку (статья 5), так что новое правило стоит выше `denyAll`. Файл
целиком — в «Пример целиком». Пересобери, запусти и спроси снова, теперь
без `-i`:

```
{"groups":["liveness","readiness"],"status":"UP"}
```

`"status":"UP"` — «жив»; `groups` — пробы из статьи 2, в Boot 4 они
включены сами. Больное приложение ответит `"status":"DOWN"` со статусом
`503` — например, когда не может достучаться до базы: health спрашивает
и её. Это увидишь в части 4.

Открыт ровно один адрес: стенду хватит общего health. Пробы из `groups`,
`/actuator/health/liveness` и `…/readiness`, без входа ответят `401`.
Так же ответит и сам `/actuator`, список адресов Actuator.
Адреса Actuator рассказывают о приложении изнутри — настройки, бины,
метрики. По вебу Boot сейчас открывает только health, но завтра кто-то
включит ещё один адрес, и правило на весь `/actuator/**` открыло бы его
без входа.

Забудешь эту строку — стенд не поднимется: Docker спросит здоровье без
пароля и получит `401`. Как это выглядит — в части 4.

💡 Тест периметра из статьи 5 health не видит: он сверяет ручки наших
контроллеров, а health — адрес Actuator. Адрес, открытый без входа,
сверяет ревьюер — по `SecurityConfig`.

### Dockerfile — рецепт образа

**Dockerfile** — текстовый файл в корне проекта: инструкции, по которым
Docker собирает образ, сверху вниз.

```dockerfile
# ── ступень 1: сборка ──
FROM eclipse-temurin:25-jdk-alpine AS build
WORKDIR /src
COPY .mvn/ .mvn/
COPY mvnw pom.xml ./
RUN ./mvnw -B -q dependency:go-offline
COPY src/ src/
RUN ./mvnw -B -q -DskipTests package && cp target/game-day-*.jar app.jar

# ── ступень 2: запуск ──
FROM eclipse-temurin:25-jre-alpine
RUN addgroup -S gameday && adduser -S gameday -G gameday
WORKDIR /app
COPY --from=build /src/app.jar app.jar
USER gameday
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
```

`FROM` — основа; `WORKDIR` — папка внутри образа (её создадут), дальше
всё в ней; `COPY откуда куда` — из проекта в образ; `RUN` — команда при
сборке, её результат ляжет слоем.

⚠️ Комментарий в Dockerfile — только целой строкой: `#` в конце
инструкции Docker примет за её аргумент.

### Две ступени

Собрать `.jar` — это JDK, Maven, исходники и сотни мегабайт библиотек;
запустить — только Java и `.jar`. Образ в одну ступень потащил бы всё
на стенд, а лишняя программа внутри — инструмент для взломщика.

**Многоступенчатая сборка** (multi-stage build): каждый `FROM` начинает
новую ступень. Первая (`AS build` — её имя) собирает `.jar`, вторая
забирает из неё один файл (`COPY --from=build`). В готовый образ идёт
только последняя ступень.

**JDK против JRE.** JDK — Java для разработчика: компилятор `javac`,
инструменты и среда запуска. JRE — только среда запуска. Поэтому
в первой ступени `25-jdk-alpine`, во второй — `25-jre-alpine`. `alpine` —
маленькая основа Linux.

### Порядок строк — это кэш

`dependency:go-offline` скачивает все библиотеки из `pom.xml` заранее,
ещё без кода. Зависимости меняются редко, код — постоянно: пока
`pom.xml` прежний, этот слой берётся из кэша. Поставь `COPY src/` выше
`pom.xml` — и каждая правка в коде будет качать библиотеки заново.

`-B`, `-q` — без цветов и лишнего вывода. `-D` задаёт настройку,
и `-DskipTests` значит «тесты не запускать». Тесты прошли
в `./mvnw verify` перед пул-реквестом, а тестам с базой в контейнере
нужен Docker, которого внутри сборки образа нет. `a && b` — выполнить `b`,
только если `a` удалась, как `&&` в Java. `cp … app.jar` даёт постоянное
имя, независимое от версии.

### Не от root

По умолчанию процесс в контейнере работает от `root` — главного
пользователя Linux. Найдут в приложении уязвимость — и чужая команда
выполнится с правами `root`, которому в контейнере можно всё. Поэтому
вторая ступень заводит системного
пользователя (`addgroup -S`, `adduser -S` — запись alpine), а
`USER gameday` переключает на него всё дальнейшее, включая запуск.
Документация Docker советует так для любой программы, которой не нужны
особые права.

### ENTRYPOINT — списком

`ENTRYPOINT` — что запустить при старте контейнера: списком, как у нас,
или строкой. Строку Docker запускает через **оболочку** `/bin/sh -c` —
программу, которая читает строку команды и запускает её. `docker stop`
шлёт главному процессу контейнера `SIGTERM` — «закройся», и Boot дал бы
текущим запросам закончиться. Дойдёт ли сигнал до Java, зависит
от строки.

Если команда в строке одна, `sh` в alpine не запускает её рядом с собой,
а заменяет себя ею. Главным процессом станет Java, и сигнал дойдёт.
Но допиши что-нибудь после команды, например так:
`java -jar /app/app.jar; echo stopped`. Тогда главной останется
оболочка, а она сигналов дальше не передаёт. Через 10 секунд Docker
пошлёт `SIGKILL` и убьёт Java на полуслове. Со списком гадать
не нужно: главный процесс — сама Java.

`EXPOSE 8080` — лишь пометка «слушаю 8080»; порт открывают `-p`
и compose.

В рабочем проекте в `ENTRYPOINT` бывают ещё флаги памяти JVM — их
подбирает мидл. Проверки здоровья в образе нет: в `eclipse-temurin`
нет `curl`. Песочнице мы зададим её в compose (о нём — ниже).

### .dockerignore

`docker build` отправляет сборщику **контекст сборки** — все файлы
папки. `.dockerignore` — что не отправлять, как `.gitignore` для git:

```
target/
.git/
.idea/
*.iml
.env*
stand/
```

`target/` — локальные сборки: лишние мегабайты и риск старого `.jar`
в образе; остальное образу не нужно.

🔴 `.env*` — файл с паролями (часть 3). Сейчас Dockerfile копирует
только нужное, но однажды кто-то напишет `COPY . .` — и пароль ляжет
в слой. А слой не меняется: `RUN rm .env` в следующем слое лишь
запишет «удалено» поверх, файл останется в прежнем и уедет с образом
ко всем, кто его скачает.

### Собрать и запустить руками

Из папки песочницы:

```bash
docker build -t game-day:local .
```

`-t` задаёт имя и тег: `local` значит «собран у меня». Точка — контекст,
текущая папка. Первая сборка идёт минуты, вторая — секунды.

Запусти контейнер так же, как в статье 5 запускал `java -jar`: те же три
переменные, только флагами `-e`. База из статьи 5 пусть работает:

```bash
docker run -d --name game-day-try -p 127.0.0.1:8088:8080 \
    -e SPRING_DATASOURCE_URL=jdbc:postgresql://127.0.0.1:5432/postgres \
    -e SPRING_DATASOURCE_USERNAME=postgres -e SPRING_DATASOURCE_PASSWORD=game-day-local \
    game-day:local
```

`-d`, `--name` и `-e` ты знаешь по статье 3а; `\` в конце строки —
команда продолжается на следующей. `-p 127.0.0.1:8088:8080` —
**публикация порта**: порт 8088 у тебя ведёт в порт 8080 контейнера.
`--rm` нет нарочно — зачем, увидишь через минуту.

```bash
docker ps
```

`docker ps` — запущенные контейнеры. Сразу после запуска `game-day-try`
в списке есть, а через несколько секунд — нет. `docker ps -a` показывает все, вместе
с остановленными: у `game-day-try` в столбце `STATUS` — `Exited (1)`,
приложение завершилось с ошибкой. Почему — в его логе:

```bash
docker logs game-day-try
```

`docker logs` — **лог** приложения, не журнал игрового дня. В нём
длинный стек ошибок, а среди них —
`Connection to 127.0.0.1:5432 refused`: подключение отклонено.

База работает, у `java -jar` этот адрес работал — а контейнер базу
не нашёл. У контейнера своя сеть (часть 1), и `127.0.0.1` в нём — сам
контейнер. База слушает порт 5432 твоей машины, а в контейнере на 5432
никого нет.

Убери контейнер:

```bash
docker rm game-day-try
```

С `--rm` он удалился бы сам — сразу после падения, вместе с логом,
и смотреть было бы нечего.

⚠️ Сборка падает на `./mvnw: not found` — у `mvnw` концы строк Windows
(CRLF), переключи в IDE на `LF`. `Permission denied` — пропал **бит
исполнения**, право запускать файл как программу: `chmod +x mvnw`,
а в git `mvnw` уже есть — `git update-index --chmod=+x mvnw`.

Свести два контейнера руками можно: своя сеть, имена, порядок запуска.
Но флагов станет вдвое больше. Стенд из нескольких программ описывают
файлом — это работа compose.

---

## Часть 3. compose: стенд одним файлом

### Docker Compose

**Docker Compose** — инструмент, который поднимает контейнеры по
описанию в файле `compose.yaml`: вместо длинных `docker run` — файл
в репозитории, один на всех. Compose входит в Docker Desktop.

⚠️ В интернете ты увидишь `docker-compose` через дефис и строку
`version: "3.8"` в начале файла. Это Compose первой версии. Сейчас —
`docker compose` через пробел, без `version`.

**Служба** compose (service) — один вид контейнера в файле. Со службой
`@Service` из статьи 1 совпало только слово.

### compose.yaml песочницы

Файл лежит в корне песочницы, рядом с `Dockerfile`. Служб две: база
и приложение.

```yaml
name: game-day                                    # имя проекта: приставка к именам контейнеров, сети, томов

services:
  db:                                             # служба базы; её имя — адрес внутри сети
    image: postgres:17-alpine                     # тот же образ, что в статье 3а
    environment:
      POSTGRES_PASSWORD: ${GAME_DAY_DB_PASSWORD}  # пароль базы — из .env
    volumes:
      - db-data:/var/lib/postgresql/data          # данные базы — в томе db-data
    healthcheck:                                  # проверка здоровья: принимает ли база подключения
      test: ["CMD", "pg_isready", "-h", "127.0.0.1", "-U", "postgres"]
      interval: 5s
      timeout: 3s
      retries: 5

  game-day:                                       # служба приложения
    build: .                                      # собрать образ по Dockerfile из этой папки
    image: game-day:local                         # …и назвать его так
    environment:                                  # переменные окружения внутри контейнера
      SPRING_PROFILES_ACTIVE: stand               # профиль stand из статьи 2
      GAME_DAY_STOP_WORD: ${GAME_DAY_STOP_WORD}   # значение подставит Compose из .env
      SPRING_DATASOURCE_URL: jdbc:postgresql://db:5432/postgres   # база — по имени службы
      SPRING_DATASOURCE_USERNAME: postgres
      SPRING_DATASOURCE_PASSWORD: ${GAME_DAY_DB_PASSWORD}
    ports:
      - "127.0.0.1:8088:8080"                     # у тебя 8088 → в контейнере 8080
    depends_on:
      db: { condition: service_healthy }          # стартовать, когда база здорова
    healthcheck:                                  # проверка здоровья: отвечает ли health
      test: ["CMD", "wget", "-qO-", "http://127.0.0.1:8080/actuator/health"]
      interval: 5s
      timeout: 3s
      retries: 3
      start_period: 30s

volumes:                                          # тома проекта
  db-data:
```

Без `name` Compose взял бы имя папки; зачем явное имя — в разделе
о томах. Служба `db` — тот же Postgres, что ты поднимал `docker run`
в статье 3а: образ и пароль переменной `POSTGRES_PASSWORD`. Служба
`game-day` — образ из части 2 с профилем `stand` (статья 2): атакующих
четверо, стоп-слово — из `GAME_DAY_STOP_WORD`. Дальше — по разделам.

### Порты — только на 127.0.0.1

`"127.0.0.1:8088:8080"` читается как `-p`: слева адрес и порт у тебя,
справа — порт в контейнере. 8088 — чтобы не спорить с песочницей
из IDE на 8080.

🔴 Без адреса, как в `"8088:8080"`, Docker откроет порт на **всех**
сетевых интерфейсах машины. Тогда приложение увидит любой в той же сети:
в офисе, в Wi-Fi кафе. Для базы стенда с учебным паролем это открытая дверь.
На фаервол не надейся: по документации Docker на Linux порт откроется,
даже если фаервол (UFW) его закрыл. Поэтому в рабочем проекте у каждого
порта стенда `127.0.0.1:` — и это тоже сторожит тест.

Порт базы мы не публикуем вовсе. Приложение ходит к ней внутри сети
compose (следующий раздел), а `psql` есть в самом контейнере базы —
до него дотянется `docker compose exec` (ниже). Понадобится база в окне
IDE — открой порт так же, на `127.0.0.1`. Слева возьми другой номер,
чтобы не спорить с базой из статьи 3а: `"127.0.0.1:5433:5432"`.

### Сеть: внутри — имя службы

Compose заводит проекту свою сеть со всеми службами — `game-day_default`.
Внутри неё служба доступна **по имени и внутреннему порту**: база
по адресу `db:5432`, приложение — `game-day:8080`.

Отсюда адрес базы в `SPRING_DATASOURCE_URL`: строка та же, что в статье
3а, только вместо `127.0.0.1` — имя службы, `db`. Это и чинит падение
из части 2: там приложение искало базу у себя в контейнере.

Порт 8088 есть только снаружи, а `127.0.0.1` внутри контейнера — это сам
контейнер. Поэтому проверка здоровья, которая идёт изнутри, спрашивает
`127.0.0.1:8080`. Увидишь это сам ниже, когда поднимешь стенд.

### Тома

Данные базы не должны пропадать вместе с контейнером. **Том** (volume) —
хранилище данных вне контейнера, которым управляет Docker; его
подключают к папке внутри, и данные переживают пересоздание контейнера.
У базы стенда так:

```yaml
    volumes:
      - db-data:/var/lib/postgresql/data   # подключить том к папке данных Postgres
volumes:                                   # в конце файла, на одном уровне с services
  db-data:                                 # завести том
```

Служба только подключает том, а заводит его раздел `volumes:` в конце
файла — без него Compose файл не примет:
`service "db" refers to undefined volume db-data`. К имени тома Compose
приставит имя проекта: выйдет `game-day_db-data`. Два проекта с одним
именем делят тома: снёс один — потерял данные другого. Отсюда и явный
`name`.

Бывает и так: слева в `volumes:` не том, а путь —
`./stubs:/home/wiremock:ro`. Это папка твоей машины, видная внутри
контейнера: файлы одни и те же. Так двойнику соседнего сервиса отдают
записанные ответы. Путь считается от папки `compose.yaml`, `:ro` —
контейнер только читает. `down -v` такие папки не трогает.

`docker compose down` удаляет контейнеры и сеть, тома оставляет.
🔴 `down -v` удаляет и тома — это «стереть данные стенда». И никаких
`prune`: `docker system prune` удалит остановленные контейнеры
и неиспользуемые сети **всех** проектов на машине. А
`docker volume prune -a` удалит все тома, к которым не подключён ни один
контейнер, в том числе данные чужого стенда, снесённого через `down`.
Своё стирай только `docker compose down -v` своего проекта.

### .env: пароли — не в файле

В `compose.yaml` стоят `${GAME_DAY_STOP_WORD}` и
`${GAME_DAY_DB_PASSWORD}`, а не сами значения. Значения Compose
**подставит** из файла `.env` рядом с `compose.yaml`. В репозитории
лежит образец `.env.example` с явно фальшивыми значениями:

```
# Скопируй в .env и поставь свои значения; .env в git не попадает.
GAME_DAY_STOP_WORD=change-me-local
GAME_DAY_DB_PASSWORD=change-me-db-local
```

Каждый копирует его (`cp .env.example .env`) и ставит своё. `.env`
в git не идёт — добавь его в `.gitignore` песочницы (в рабочем проекте
так уже есть).

Пароль базы нужен двоим: базе он приходит как `POSTGRES_PASSWORD`,
приложению — как `SPRING_DATASOURCE_PASSWORD`. Одна переменная на обоих —
и пароли не разойдутся.

🔴 Пароль, попавший в коммит, остаётся в истории git: коммит «убрал
пароль» его оттуда не достаёт. Такой пароль считают утёкшим и меняют.

`.env` нужен самому Compose для подстановки `${…}`, в контейнер он не
попадает: туда переменная приходит только строкой в `environment`.

⚠️ Переменная оболочки сильнее `.env`. Задал в статье 2
`export GAME_DAY_STOP_WORD=…` в той же консоли — Compose возьмёт её.

Нет переменной нигде — Compose предупредит
`The "GAME_DAY_STOP_WORD" variable is not set. Defaulting to a blank string.`
и подставит пустую строку. Приложение не поднимется: пустое стоп-слово
не пройдёт `@NotBlank` из статьи 2.

Документация Docker советует передавать пароли не переменными,
а секретами. На боевых серверах так и делают; на локальном стенде
пароли фальшивые.

### Проверка здоровья

«Контейнер запущен» — ещё не «приложение готово». **Проверка здоровья**
(healthcheck) — команда, которую Docker регулярно выполняет внутри
контейнера: код выхода 0 — здоров. Состояние видно в `docker compose ps`:
сначала `starting`, после удачи `healthy`, после нескольких неудач
подряд `unhealthy`.

У приложения:

* `test` — команда списком: `CMD` значит «запустить без оболочки»,
  `CMD-SHELL` — «строкой через оболочку». `wget -qO-` спрашивает
  `/actuator/health` — тот самый адрес, который охрана пускает без входа
  (часть 2): пароля у Docker нет. `-q` значит «молча», `-O-` — «ответ
  в вывод, а не в файл». На `503` и `401` `wget` выйдет с ошибкой;
* `wget`, а не `curl`: `curl` в образе нет, а `wget` из основы alpine
  есть;
* `interval` — как часто спрашивать, по умолчанию раз в 30 секунд;
* `timeout` — сколько ждать ответа;
* `retries` — сколько провалов подряд до `unhealthy`;
* `start_period` — время на старт: провалы в нём не считаются, а первая
  удача сразу даёт `healthy`.

У базы — `pg_isready`, программа из образа Postgres: «принимает ли база
подключения». `-U postgres` — от чьего имени спрашивать. `-h 127.0.0.1` —
стучаться по сети, как будет стучаться приложение. Без `-h` `pg_isready`
спрашивает базу в обход сети, а при первом запуске Postgres ненадолго
поднимается именно так, без сети, — чтобы создать базу. Проверка сказала
бы «готов» раньше, чем база откроет порт.

### depends_on: ждать не запуска, а здоровья

Приложение без базы не поднимается (часть 2), поэтому служба `game-day`
ждёт `db`:

```yaml
    depends_on:
      db: { condition: service_healthy }   # ждать, пока база здорова
```

Фигурные скобки — та же вложенность YAML в одну строку: то же, что
`condition:` строкой ниже с отступом. `service_healthy` — ждать, пока
проверка не скажет `healthy`. Без `depends_on` Compose запустит обе
службы разом, и успеет ли база проснуться раньше Flyway — вопрос удачи.
Бывает и `service_started` — ждать только запуска контейнера: так ждут
службу без проверки здоровья, например двойника.

Живость и готовность — тема глубже, чем «есть адрес здоровья»;
в рабочем проекте её решает мидл.

### Поднять, посмотреть, снести

Из папки песочницы, по одной команде:

```bash
cp .env.example .env
```

```bash
docker compose up -d --build
```

```bash
docker compose ps
```

```bash
docker compose logs game-day
```

`up -d --build` — пересобрать образ и поднять в фоне; `compose.yaml`
и `.env` Compose нашёл в текущей папке. Первой поднимается база,
приложение — когда она станет `healthy`. Немного погодя в `ps` у обеих
служб — `(healthy)`. В логе приложения — `атакующих 4` и строка Flyway
`Successfully applied 1 migration`: база новая.

Охрана на стенде та же, что в статье 5:

```bash
curl -i http://127.0.0.1:8088/game-day/incidents
```

```bash
curl -u admin:admin-local http://127.0.0.1:8088/game-day/incidents
```

Без входа — `401`. Под `admin` — страница журнала с `"total":1` и одним
происшествием, «Брокер не отвечает»: его записал запуск приложения.
Теперь сеть изнутри:

```bash
docker compose exec -T game-day wget -qO- http://game-day:8080/actuator/health
```

`docker compose exec <служба> <команда>` — выполнить команду внутри
работающего контейнера службы. `-T` — не подключать к ней консоль как
живое окно: иначе Git Bash иногда молчит или пишет
`the input device is not a TTY`. Ответ — `"status":"UP"`
по имени службы; с `http://127.0.0.1:8088/…` изнутри — ошибка
подключения.

```bash
docker compose down
```

`down` останавливает и удаляет контейнеры и сеть, том оставляет.
Приложение закрывается за секунды: `SIGTERM` дошёл до Java, потому что
`ENTRYPOINT` записан списком (часть 2). Если `compose.yaml` лежит не в текущей
папке, путь к нему дают флагом `-f`, а к `.env` — флагом `--env-file`.
Так сделает скрипт в части 4: его можно запускать из любой папки.

### Том помнит

Подними стенд снова:

```bash
docker compose up -d
```

Дождись `(healthy)` в `docker compose ps` и посчитай происшествия прямо
в базе — `psql` внутри контейнера службы `db`:

```bash
docker compose exec -T db psql -U postgres -c "SELECT count(*) FROM game_day.incident"
```

`-c` — выполнить одну команду и выйти (статья 4). Ответ:

```
 count
-------
     2
(1 row)
```

Два «Брокера»: с прошлого подъёма и с этого. Контейнер базы `down`
удалил, а том `game-day_db-data` остался, его видно
в `docker volume ls`. Новый контейнер взял данные из него. Flyway
в логе приложения на этот раз пишет
`Schema "game_day" is up to date. No migration necessary.`: эту базу
он уже видел.

```bash
docker compose down -v
```

Снова `up -d` — и `count` равен `1`, а Flyway опять применяет миграцию:
том создан заново, база пустая.

⚠️ Том помнит и пароль. Postgres берёт `POSTGRES_PASSWORD`, только когда
том пуст, — при первом запуске; дальше пароль живёт в томе. Поменяй
`GAME_DAY_DB_PASSWORD` в `.env` и снова `docker compose up -d`:
приложение получит новый пароль, а база помнит старый. В
`docker compose logs game-day` —
`password authentication failed for user "postgres"`. Выхода два:
вернуть в `.env` прежний пароль — или снести том, `down -v`, если
данных не жалко.

---

## Часть 4. bash: скрипт, который не врёт

### Зачем скрипт

Поднять стенд — это проверить `.env`, собрать, поднять, дождаться
здоровья обеих служб и спросить приложение снаружи.

**bash** — оболочка, как `/bin/sh` из части 2, только удобнее; есть
в Git Bash, на Linux и macOS. **Скрипт** — файл с командами, которые
bash выполняет по порядку, как если бы ты вводил их сам. В рабочем
проекте у стенда их обычно несколько: поднять, проверить, снести
начисто. У песочницы — два, в папке `stand/`:
`game-up.sh` поднимает стенд, `game-alive.sh` спрашивает здоровье.

### game-up.sh

```bash
#!/usr/bin/env bash
# Поднять стенд песочницы game-day и убедиться, что игра отвечает.
set -euo pipefail

SANDBOX_DIR="$(cd "$(dirname "$0")/.." && pwd)"   # папка песочницы — на уровень выше stand/
ENV_FILE="$SANDBOX_DIR/.env"

if [[ ! -f "$ENV_FILE" ]]; then                    # условие: файла .env нет
  echo "нет $ENV_FILE — скопируй: cp .env.example .env" >&2
  exit 1
fi

docker compose -f "$SANDBOX_DIR/compose.yaml" --env-file "$ENV_FILE" up -d --build --wait --wait-timeout 120
"$SANDBOX_DIR/stand/game-alive.sh"                 # последняя команда: её код станет кодом скрипта
```

**Первая строка — shebang** (`#!`): чем выполнять файл.
`/usr/bin/env bash` — «найди bash, где бы он ни лежал».

**`set -euo pipefail`** — три страховки; без них bash на ошибке идёт
дальше как ни в чём не бывало:

* `-e` — выйти на первой команде, вернувшей ошибку. Иначе упавший
  `docker compose up` не остановил бы скрипт, и тот спрашивал бы
  здоровье у стенда, которого нет;
* `-u` — незаданная переменная считается ошибкой. Опечатка `$SANDBOX_DRI` без
  `-u` даст пустую строку, с `-u` — сразу `SANDBOX_DRI: unbound variable`;
* `-o pipefail` — про **конвейер** `a | b`, где вывод одной команды идёт
  на вход другой. Без него код конвейера — код последней команды:
  в `curl … | tee health.json` (`tee` пишет вывод в файл) упавший
  `curl` спрячется за успешным `tee`.

🔑 Скрипт, который молча прошёл наполовину, хуже упавшего: упавший
хотя бы говорит, где сломалось.

**Переменные и кавычки.** `ENV_FILE="…"` — присвоить, без пробелов
вокруг `=`; `$ENV_FILE` — подставить значение. Подстановку берут
в двойные кавычки: без них значение с пробелом развалится на два слова,
и для песочницы в `/c/Users/duty-1/Мои проекты/game-day` Compose
получит два обрывка пути. В одинарных кавычках подстановки нет:
`'$ENV_FILE'` останется долларом с буквами.

`"$(команда)"` — подставить вывод команды. Внутри: `$0` — путь
к скрипту, `dirname` — его папка, `cd …/..` — на уровень выше, `pwd` —
текущая папка полным путём; `&&` — как в Dockerfile. `cd` внутри
`$( … )` работает в отдельной копии оболочки, папка самого скрипта
не меняется. Так скрипт работает из любой папки.

**Код выхода.** Каждая команда возвращает число: `0` — успех,
остальное — ошибка; сразу после команды оно в `$?`. `if` проверяет
именно код. Условие `[[ ! -f "$ENV_FILE" ]]` читается «не (`!`) есть
файл (`-f`)» и даёт `0`, если файла нет. `exit 1` — закончить с ошибкой: тот, кто
запустил скрипт, узнает, что не вышло. `>&2` — печатать в поток
ошибок, отдельный канал для таких сообщений; в консоли видны оба.

`--wait` велит Compose ждать здоровья всех служб: и базы,
и приложения. Нет здоровья через `--wait-timeout` секунд — Compose вернёт
ошибку. Служба заболела раньше — Compose не ждёт до конца и называет
контейнер.

Убери из `SecurityConfig` правило для health (часть 2)
и запусти скрипт: после `start_period` и трёх провалов подряд он упадёт
со словами `container game-day-game-day-1 is unhealthy`. Приложение
при этом работает — просто Docker спрашивает здоровье без пароля
и получает `401`. Посмотрел — верни правило на место.

### game-alive.sh

```bash
#!/usr/bin/env bash
# Жива ли игра: спросить /actuator/health через порт на 127.0.0.1.
set -euo pipefail

HEALTH_URL="http://127.0.0.1:8088/actuator/health"

if curl -fsS "$HEALTH_URL"; then
  echo                                             # curl не ставит перевод строки после ответа
  echo "игра жива"
else
  echo "игра не отвечает на $HEALTH_URL — смотри из папки песочницы: docker compose logs game-day" >&2
  exit 1
fi
```

Проверка здоровья в compose идёт изнутри контейнера, а скрипт —
**снаружи**, как ты и браузер; заодно видно, что порт опубликован.

* `-f` (fail) — ответ `400` и выше считать ошибкой: код выхода `22`.
  Без `-f` `curl` доволен любым ответом — и `503`, и `404`;
* `-s` (silent) — без полоски загрузки и сообщений;
* `-S` (show-error) — но ошибку показать: одно `-s` глушит и её.

Бывает, что `-f` не ставят намеренно: когда код ответа скрипт
разбирает сам.

Команда в условии `if` не обрывает скрипт даже при `-e`: её код
разбирает сам `if`.

```
$ stand/game-alive.sh                       # стенд поднят — код выхода 0
{"groups":["liveness","readiness"],"status":"UP"}
игра жива
```

Теперь сделай приложению больно: останови базу командой
`docker compose stop db` и спроси снова.

```
$ stand/game-alive.sh                       # база остановлена — код 1
curl: (22) The requested URL returned error: 503
игра не отвечает на http://127.0.0.1:8088/actuator/health — смотри из папки песочницы: docker compose logs game-day
```

Ответ придёт не сразу: health спрашивает и базу, а приложение сперва
ждёт подключения к ней. Не дождалось — `DOWN`, `503`, а `-f` превратил
его в код `22`. Верни базу командой `docker compose start db` и подожди:
приложение переподключится само, без перезапуска, и скрипт снова скажет
«игра жива».

Стенд не поднят — вместо `(22)` будет `curl: (7) Failed to connect…`.
Код `7` значит «не подключился», а `22` — «подключился, но ответ
с ошибкой».

💡 В скрипте, который прогоняет много проверок подряд, `-e` иногда
не ставят намеренно: одна упавшая проверка не должна прятать остальные.

### Проверить и запустить

```bash
bash -n stand/game-up.sh
```

`-n` — прочитать скрипт, не выполняя: пустой вывод — синтаксис
в порядке. Ловит непарные кавычки и `if` без `fi`, но не опечатку
в имени команды.

Запуск — из папки песочницы: `stand/game-up.sh`. Не запускается:

* `Permission denied` — нет бита исполнения (часть 2):
  `chmod +x stand/*.sh`. Бит нужен обоим: `game-up.sh` сам запускает
  `game-alive.sh`, поэтому `bash stand/game-up.sh` не спасёт. В git
  новый файл добавляют `git add --chmod=+x`, а уже добавленному дают
  бит `git update-index --chmod=+x`;
* `/usr/bin/env: 'bash\r': No such file or directory`,
  `$'\r': command not found` или `set: pipefail: invalid option name` —
  концы строк Windows (CRLF): в IDE переключи на `LF`. Чтобы git держал
  их сам, в «Пример целиком» есть `.gitattributes`, как в рабочем проекте.

---

## Проверь себя

Ответь своими словами — вслух или на бумаге. Не получается — перечитай
раздел.

1. Чем образ отличается от контейнера? Что пропадёт, если удалить
   контейнер, и где хранят то, что должно остаться?
2. Почему в Dockerfile `pom.xml` копируют раньше `src/`?
3. Зачем образу две ступени и почему во второй JRE, а не JDK?
4. Когда `ENTRYPOINT` строкой не даст Java закрыться по `docker stop`
   и почему список надёжнее?
5. Почему `/actuator/health` открыт без входа, а `/actuator/health/liveness`
   и остальной Actuator — нет? Что будет со стендом, если правило
   для health забыть?
6. Чем опасен порт `"8088:8080"` без адреса и почему не стоит надеяться
   на фаервол?
7. Контейнер из части 2 получил адрес базы `127.0.0.1:5432`, тот самый,
   с которым работал `java -jar`, и упал. Почему, и какой адрес
   правильный на стенде compose?
8. В `.env` одно стоп-слово, а приложение получило другое — или не видит
   переменную вовсе. Что могло случиться? А если после смены пароля базы
   в `.env` приложение перестало входить в базу?
9. Что делает каждая часть `set -euo pipefail` и зачем `curl` флаги
   `-fsS`?

---

## Что дальше

Дальше в серии — события игры в JSON: атакующий присылает их текстом,
а журнал должен понять, что пришло. Jackson 3, `sealed`, `switch`
по образцу и эталоны.

## Первоисточники

* [Dockerfile reference](https://docs.docker.com/reference/dockerfile/) —
  `ENTRYPOINT`, `HEALTHCHECK` и остальные инструкции;
* [Docker: Building best practices](https://docs.docker.com/build/building/best-practices/) —
  ступени, версии основы, `USER`, `.dockerignore`, кэш;
* [Compose file reference: Services](https://docs.docker.com/reference/compose-file/services/) —
  `ports`, `volumes`, `healthcheck`, `depends_on`;
* [Compose: Variable interpolation](https://docs.docker.com/compose/how-tos/environment-variables/variable-interpolation/) —
  `.env`, `--env-file`, кто кого сильнее;
* [Docker Official Image: postgres](https://hub.docker.com/_/postgres) —
  `POSTGRES_PASSWORD` и предупреждение: переменные образа действуют
  только на пустой папке данных;
* [Spring Boot: Actuator Endpoints](https://docs.spring.io/spring-boot/reference/actuator/endpoints.html) —
  что открыто по вебу, проверка `db` в health, `DOWN` → `503`;
* [GNU Bash: The Set Builtin](https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html) —
  `-e` и где он молчит, `-u`, `pipefail`, `-n`.

---

## Пример целиком

Учебный пример. Запускай в песочнице `game-day` после статьи 5.
Java-код, тесты, `application.yml`, `application-stand.yml` и миграция —
из статей 1–5 без изменений, кроме `SecurityConfig`: он ниже целиком.
Нужны запущенный Docker Desktop и Git Bash (на Linux и macOS — обычная
консоль); JDK для стенда не нужен — приложение собирается внутри образа.

```
game-day/
├── .dockerignore
├── .env               ← твоя копия .env.example, в git не идёт
├── .env.example
├── .gitattributes     ← .sh и mvnw — в LF
├── .gitignore         ← + строка .env
├── Dockerfile
├── compose.yaml
├── mvnw, .mvn/        ← от Initializr
├── pom.xml            ← + actuator
├── stand/
│   ├── game-alive.sh
│   └── game-up.sh
└── src/               ← из статей 1–5; в SecurityConfig — health без входа
```

Путь к файлу — комментарием в первой строке; у скриптов первая строка —
shebang, поэтому путь — во второй.

```xml
<!-- pom.xml: в <dependencies>, рядом с тем, что уже есть -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>
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

/** Охрана песочницы: вход по Basic, пользователи в памяти; журнал — только admin, health — всем. */
@Configuration
public class SecurityConfig {

    @Bean
    public SecurityFilterChain security(HttpSecurity http) {
        http.authorizeHttpRequests(access -> access
                        .dispatcherTypeMatchers(DispatcherType.ERROR).permitAll()
                        .requestMatchers(HttpMethod.GET, "/actuator/health").permitAll()
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

```dockerfile
# Dockerfile
# ── ступень 1: сборка ──
FROM eclipse-temurin:25-jdk-alpine AS build
WORKDIR /src
COPY .mvn/ .mvn/
COPY mvnw pom.xml ./
RUN ./mvnw -B -q dependency:go-offline
COPY src/ src/
RUN ./mvnw -B -q -DskipTests package && cp target/game-day-*.jar app.jar

# ── ступень 2: запуск ──
FROM eclipse-temurin:25-jre-alpine
RUN addgroup -S gameday && adduser -S gameday -G gameday
WORKDIR /app
COPY --from=build /src/app.jar app.jar
USER gameday
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
```

```
# .dockerignore
target/
.git/
.idea/
*.iml
.env*
stand/
```

```yaml
# compose.yaml
name: game-day

services:
  db:
    image: postgres:17-alpine
    environment:
      POSTGRES_PASSWORD: ${GAME_DAY_DB_PASSWORD}
    volumes:
      - db-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD", "pg_isready", "-h", "127.0.0.1", "-U", "postgres"]
      interval: 5s
      timeout: 3s
      retries: 5

  game-day:
    build: .
    image: game-day:local
    environment:
      SPRING_PROFILES_ACTIVE: stand
      GAME_DAY_STOP_WORD: ${GAME_DAY_STOP_WORD}
      SPRING_DATASOURCE_URL: jdbc:postgresql://db:5432/postgres
      SPRING_DATASOURCE_USERNAME: postgres
      SPRING_DATASOURCE_PASSWORD: ${GAME_DAY_DB_PASSWORD}
    ports:
      - "127.0.0.1:8088:8080"
    depends_on:
      db: { condition: service_healthy }
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://127.0.0.1:8080/actuator/health"]
      interval: 5s
      timeout: 3s
      retries: 3
      start_period: 30s

volumes:
  db-data:
```

```
# .env.example
# Скопируй в .env и поставь свои значения; .env в git не попадает.
GAME_DAY_STOP_WORD=change-me-local
GAME_DAY_DB_PASSWORD=change-me-db-local
```

```
# .gitignore — дописать в конец
.env
```

```
# .gitattributes — концы строк LF для скриптов, как в рабочем проекте
*.sh text eol=lf
mvnw text eol=lf
```

```bash
#!/usr/bin/env bash
# stand/game-up.sh — поднять стенд песочницы game-day и убедиться, что игра отвечает.
set -euo pipefail

SANDBOX_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$SANDBOX_DIR/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "нет $ENV_FILE — скопируй: cp .env.example .env" >&2
  exit 1
fi

docker compose -f "$SANDBOX_DIR/compose.yaml" --env-file "$ENV_FILE" up -d --build --wait --wait-timeout 120
"$SANDBOX_DIR/stand/game-alive.sh"
```

```bash
#!/usr/bin/env bash
# stand/game-alive.sh — жива ли игра: спросить /actuator/health через порт на 127.0.0.1.
set -euo pipefail

HEALTH_URL="http://127.0.0.1:8088/actuator/health"

if curl -fsS "$HEALTH_URL"; then
  echo
  echo "игра жива"
else
  echo "игра не отвечает на $HEALTH_URL — смотри из папки песочницы: docker compose logs game-day" >&2
  exit 1
fi
```

**Порядок проверки** — из папки песочницы, по одной команде:

1. `curl -i http://127.0.0.1:8080/actuator/health` у песочницы
   из IDE или `java -jar`: до правила в `SecurityConfig` — `401`, после —
   `{"groups":["liveness","readiness"],"status":"UP"}`;
2. `docker build -t game-day:local .`, затем `docker run` из части 2 —
   `docker ps -a` показывает `Exited (1)`, в `docker logs game-day-try` —
   `Connection to 127.0.0.1:5432 refused`; `docker rm game-day-try`;
3. `cp .env.example .env` — и свои значения в `.env`;
4. `chmod +x stand/*.sh`, затем `bash -n stand/game-up.sh` и
   `bash -n stand/game-alive.sh` — пустой вывод;
5. `stand/game-up.sh` — строки Compose (зависят от версии), потом
   ответ `health` и `игра жива`; `echo $?` — `0`;
6. `docker compose ps` — у `db` и `game-day` `(healthy)`;
   `docker compose logs game-day` — `атакующих 4`;
7. `curl -i http://127.0.0.1:8088/game-day/incidents` — `401`;
   с `-u admin:admin-local` — «Брокер не отвечает» и `"total":1`;
8. `docker compose exec -T game-day wget -qO- http://game-day:8080/actuator/health` —
   `"status":"UP"` по имени службы;
9. `docker compose stop db`, затем `stand/game-alive.sh` — не сразу,
   `curl: (22)` с `503` и код `1`; `docker compose start db` — немного
   погодя снова `игра жива`;
10. `docker compose down`, затем `stand/game-alive.sh` — `curl: (7)`
    и код `1`; в `docker volume ls` — `game-day_db-data`;
11. `stand/game-up.sh`, затем
    `docker compose exec -T db psql -U postgres -c "SELECT count(*) FROM game_day.incident"` —
    `2`; `docker compose down -v`, снова `stand/game-up.sh` — `1`;
12. пароль: поменяй `GAME_DAY_DB_PASSWORD` в `.env`, `docker compose up -d` —
    в `docker compose logs game-day` `password authentication failed`;
    верни прежний пароль и `docker compose up -d`;
13. без стоп-слова: поставь `#` в начало строки `GAME_DAY_STOP_WORD`
    в `.env`, `docker compose up -d` — предупреждение `variable is not set`;
    `docker compose logs game-day` — `APPLICATION FAILED TO START`
    и `stopWord`; убери `#` и `docker compose down`.
