# Hammerhall Ledger

[![Примеры статей](https://github.com/Hammerhall/hammerhall-ledger/actions/workflows/examples.yml/badge.svg)](https://github.com/Hammerhall/hammerhall-ledger/actions/workflows/examples.yml)

Статьи для Java-джунов от Hammerhall: Stream API шаг за шагом,
алгоритмы на стримах, дорога к Spring Boot, тесты — и истории слов,
на которых говорят программисты.

**Читать удобнее на сайте → [hammerhall.io/ledger](https://hammerhall.io/ledger)**

Здесь лежат те же тексты в Markdown. Ссылки внутри статей ведут на сайт:
там соседние статьи и задачи для практики. Код из статей —
в [`examples/`](examples/): его собирает и запускает каждый прогон.

---

# Кузни

Теория к задачам кузницы Stream Forge. Пример во всех статьях —
кофейня «Наковальня» и её заказы.

## Стримы по шагам

Java Stream API от первого `filter` до своего коллектора. Сквозной пример —
заказы кофейни. Код каждого примера прогнан на JDK 25.

| № | Статья | Текст |
|---|---|---|
| 1 | [Стрим вместо цикла: конвейер для коллекций](https://hammerhall.io/ledger/streams/1-stream-instead-of-loop) | [md](streams/01-stream-instead-of-loop.md) |
| 2 | [`filter`, `map` и `Optional` без страха](https://hammerhall.io/ledger/streams/2-filter-map-optional) | [md](streams/02-filter-map-optional.md) |
| 3 | [Сортировка: компараторы и ловушка `reversed`](https://hammerhall.io/ledger/streams/3-sorting) | [md](streams/03-sorting.md) |
| 4 | [`flatMap`: списки внутри объектов](https://hammerhall.io/ledger/streams/4-flatmap) | [md](streams/04-flatmap.md) |
| 5 | [`groupingBy` и `toMap`: раскладываем по группам](https://hammerhall.io/ledger/streams/5-grouping) | [md](streams/05-grouping.md) |
| 6 | [Коллекторы внутри группы](https://hammerhall.io/ledger/streams/6-downstream-collectors) | [md](streams/06-downstream-collectors.md) |
| 7 | [Стрим по `Map`: сортировка по значению и «топ-N»](https://hammerhall.io/ledger/streams/7-streams-over-maps) | [md](streams/07-streams-over-maps.md) |
| 8 | [Числа: `IntStream`, суммы и переполнение](https://hammerhall.io/ledger/streams/8-number-streams) | [md](streams/08-number-streams.md) |
| 9 | [Две коллекции: индекс вместо стрима в стриме](https://hammerhall.io/ledger/streams/9-two-collections) | [md](streams/09-two-collections.md) |
| 10 | [Свой коллектор и когда цикл лучше](https://hammerhall.io/ledger/streams/10-own-collector) | [md](streams/10-own-collector.md) |

## Алгоритмы на стримах

Цикл «Сравнить коллекции»: множества, пары, сходство — и сколько стоит
каждое решение, когда данных становится вдвое больше. Пример — месяц
заказов кофейни «Наковальня». Код прогнан на JDK 25.

| № | Статья | Текст |
|---|---|---|
| 1 | [Множества как алгебра: пересечение, разность, подмножество](https://hammerhall.io/ledger/algorithms/1-set-algebra) | [md](algorithms/01-set-algebra.md) |
| 2 | [Множество как ключ карты: самые популярные комбо](https://hammerhall.io/ledger/algorithms/2-set-as-key) | [md](algorithms/02-set-as-key.md) |
| 3 | [Пары «все со всеми»: почему n² не взлетает](https://hammerhall.io/ledger/algorithms/3-all-pairs) | [md](algorithms/03-all-pairs.md) |
| 4 | [Пары внутри записи и обратный индекс](https://hammerhall.io/ledger/algorithms/4-inverted-index) | [md](algorithms/04-inverted-index.md) |
| 5 | [Сходство множеств: коэффициент Жаккара](https://hammerhall.io/ledger/algorithms/5-jaccard) | [md](algorithms/05-jaccard.md) |
| 6 | [Векторы: косинус, расстояние, ближайшие соседи](https://hammerhall.io/ledger/algorithms/6-vectors) | [md](algorithms/06-vectors.md) |

---

# Буткемп / Лаборатория

Как пишут код команды Hammerhall: буткемп работает в открытых
репозиториях, лаборатория — в закрытых. Серии «От … к …» — то, что
нужно новичку до первой задачи. Статьи идут по порядку, и пример у них
один, растущий от статьи к статье: учебный проект «Игровой день»,
со статьи 12 — учебная CRM спортивного клуба. У серии о тестах свой
пример — «зачёт по сроку».

## От Java к Spring Boot

Что нужно знать до Spring, зачем он вообще нужен, как устроен
Spring Boot 4, как приложение хранит данные и отвечает по HTTP.

| № | Статья | Текст | Код |
|---|---|---|---|
| 0 | [Что нужно знать до Spring](https://hammerhall.io/ledger/articles/0-before-spring) | [md](articles/00-before-spring.md) | [пример](examples/articles/00-before-spring) |
| 1 | [Зачем Spring](https://hammerhall.io/ledger/articles/1-why-spring) | [md](articles/01-why-spring.md) | [пример](examples/articles/01-why-spring) |
| 2 | [Spring Boot 4 для самых маленьких](https://hammerhall.io/ledger/articles/2-spring-boot-4) | [md](articles/02-spring-boot-4.md) | [пример](examples/articles/02-spring-boot-4) |
| 3а | [Данные, часть 1: таблица и миграция](https://hammerhall.io/ledger/articles/3a-table-and-migration) | [md](articles/03a-table-and-migration.md) | [пример](examples/articles/03a-table-and-migration) |
| 3б | [Данные, часть 2: сущность, хранилище, транзакция](https://hammerhall.io/ledger/articles/3b-entity-and-transaction) | [md](articles/03b-entity-and-transaction.md) | [пример](examples/articles/03b-entity-and-transaction) |
| 4 | [Первая ручка: как приложение отвечает по HTTP](https://hammerhall.io/ledger/articles/4-web) | [md](articles/04-web.md) | [пример](examples/articles/04-web) |
| 5 | [Ручка целиком: слои, доступ, страницы, тесты всех слоёв](https://hammerhall.io/ledger/articles/5-full-endpoint) | [md](articles/05-full-endpoint.md) | [пример](examples/articles/05-full-endpoint) |

## От Spring к системе

Следующий шаг: как приложение живёт среди других программ — стенд,
события, метрики и тесты, которые сторожат правила проекта.

| № | Статья | Текст | Код |
|---|---|---|---|
| 6 | [Стенд своими руками: Docker, образ, compose, `.env`, скрипты bash](https://hammerhall.io/ledger/articles/6-stand) | [md](articles/06-stand.md) | [пример](examples/articles/06-stand) |
| 7 | [События: JSON всерьёз — Jackson 3, `sealed`, `switch` по образцу, эталоны](https://hammerhall.io/ledger/articles/7-events-json) | [md](articles/07-events-json.md) | [пример](examples/articles/07-events-json) |
| 8 | [Объекты-значения: приведение, проверки, маскировка](https://hammerhall.io/ledger/articles/8-value-objects) | [md](articles/08-value-objects.md) | [пример](examples/articles/08-value-objects) |
| 9 | [Данные дальше: конвертеры JPA, JSON в столбце, выборки по времени, индексы](https://hammerhall.io/ledger/articles/9-data-further) | [md](articles/09-data-further.md) | [пример](examples/articles/09-data-further) |
| 10 | [Метрики: счётчик, датчик, таймер, теги — и дежурство в игровой день](https://hammerhall.io/ledger/articles/10-metrics) | [md](articles/10-metrics.md) | [пример](examples/articles/10-metrics) |
| 11 | [Тесты-сторожа: тесты, которые проверяют правила проекта](https://hammerhall.io/ledger/articles/11-guard-tests) | [md](articles/11-guard-tests.md) | [пример](examples/articles/11-guard-tests) |

## От системы к делу

Как правила дела — сроки, деньги, обещания людям — живут в коде.

| № | Статья | Текст | Код |
|---|---|---|---|
| 12 | [Что делает CRM: следующий шаг с датой](https://hammerhall.io/ledger/articles/12-what-crm-does) | [md](articles/12-what-crm-does.md) | [пример](examples/articles/12-what-crm-does) |
| 13 | [Статусы лида: какие ставит человек, а какой — только система](https://hammerhall.io/ledger/articles/13-lead-statuses) | [md](articles/13-lead-statuses.md) | [пример](examples/articles/13-lead-statuses) |
| 14 | [Деньги в коде: копейки, скидки, округление](https://hammerhall.io/ledger/articles/14-money-in-code) | [md](articles/14-money-in-code.md) | [пример](examples/articles/14-money-in-code) |
| 15 | [Правила продаж — в настройках](https://hammerhall.io/ledger/articles/15-sales-rules-in-settings) | [md](articles/15-sales-rules-in-settings.md) | [пример](examples/articles/15-sales-rules-in-settings) |
| 16 | [Оплата, о которой никто не сообщил](https://hammerhall.io/ledger/articles/16-unreported-payment) | [md](articles/16-unreported-payment.md) | [пример](examples/articles/16-unreported-payment) |
| 16а | [Задание без человека: почему ночной опрос получил бы `401`](https://hammerhall.io/ledger/articles/16a-job-without-a-person) | [md](articles/16a-job-without-a-person.md) | [пример](examples/articles/16a-job-without-a-person) |
| 17 | [Lombok и MapStruct: код, который пишут за тебя](https://hammerhall.io/ledger/articles/17-lombok-and-mapstruct) | [md](articles/17-lombok-and-mapstruct.md) | [пример](examples/articles/17-lombok-and-mapstruct) |
| 18 | [Миграции помнят решения](https://hammerhall.io/ledger/articles/18-migrations-remember) | [md](articles/18-migrations-remember.md) | [пример](examples/articles/18-migrations-remember) |

## От красного к зелёному

Как работать с тестами на проекте: писать их, читать красную сборку
и верить зелёному тесту, только если видел его красным.

| № | Статья | Текст | Код |
|---|---|---|---|
| 1 | [Зачем тесты и чего от тебя ждут на проекте](https://hammerhall.io/ledger/testing/1-why-tests) | [md](testing/01-why-tests.md) | [пример](examples/testing/01-why-tests) |
| 2 | [Первый модульный тест: от пустого файла до зелёного отчёта](https://hammerhall.io/ledger/testing/2-first-test) | [md](testing/02-first-test.md) | [пример](examples/testing/02-first-test) |
| 3 | [Тест покраснел: что делать](https://hammerhall.io/ledger/testing/3-red-test) | [md](testing/03-red-test.md) | [пример](examples/testing/03-red-test) |
| 4 | [Какие случаи проверять](https://hammerhall.io/ledger/testing/4-which-cases) | [md](testing/04-which-cases.md) | [пример](examples/testing/04-which-cases) |
| 5 | [Тест, который ничего не проверяет](https://hammerhall.io/ledger/testing/5-test-that-checks-nothing) | [md](testing/05-test-that-checks-nothing.md) | [пример](examples/testing/05-test-that-checks-nothing) |
| 6 | [Когда вокруг твоего кода другой код](https://hammerhall.io/ledger/testing/6-stubs) | [md](testing/06-stubs.md) | [пример](examples/testing/06-stubs) |
| 7 | [Тест с настоящей базой](https://hammerhall.io/ledger/testing/7-real-database) | [md](testing/07-real-database.md) | [пример](examples/testing/07-real-database) |

---

# Темы

## Истории слов

Откуда взялись слова, на которых говорит команда. Не определения,
а истории — минут на пять, читать в любом порядке. Для всех, не только
для программистов.

| № | История | Текст |
|---|---|---|
| 1 | [Кука: как забывчивому интернету выдали номерок](https://hammerhall.io/ledger/words/1-cookie) | [md](words/01-cookie.md) |
| 2 | [Ключ Bearer: «обещаю заплатить предъявителю»](https://hammerhall.io/ledger/words/2-bearer) | [md](words/02-bearer.md) |
| 3 | [Мёртвые письма: комната, где чужое письмо вскрывали по закону](https://hammerhall.io/ledger/words/3-dead-letters) | [md](words/03-dead-letters.md) |
| 4 | [Идемпотентность: слово, которого не было в словаре](https://hammerhall.io/ledger/words/4-idempotency) | [md](words/04-idempotency.md) |
| 5 | [Баг: первый настоящий жук](https://hammerhall.io/ledger/words/5-bug) | [md](words/05-bug.md) |
| 6 | [Пул-реквест: просьба втянуть](https://hammerhall.io/ledger/words/6-pull-request) | [md](words/06-pull-request.md) |
| 7 | [Канбан: вывеска, карточка, доска](https://hammerhall.io/ledger/words/7-kanban) | [md](words/07-kanban.md) |
| 8 | [Докер: ящик, которому всё равно, что внутри](https://hammerhall.io/ledger/words/8-docker) | [md](words/08-docker.md) |
| 9 | [Ментор: друг, которого сыграла богиня](https://hammerhall.io/ledger/words/9-mentor) | [md](words/09-mentor.md) |
| 10 | [Бэклог: бревно, которое держит огонь](https://hammerhall.io/ledger/words/10-backlog) | [md](words/10-backlog.md) |

---

## Прочитал — закрепи

К статьям о стримах есть задачи в кузнице **Stream Forge**, часть из них
бесплатная. Ссылки на задачи — в конце статей.
→ **[Начать бесплатно на hammerhall.io](https://hammerhall.io/register)**

Хочешь учиться в команде, на настоящем проекте, —
→ **[буткемп Hammerhall](https://hammerhall.io/bootcamp)**

## Новые статьи

Тексты появляются здесь в день выхода на сайте. Чтобы не пропустить
новые, поставь ⭐ и нажми Watch.

## Лицензия

Тексты — [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/deed.ru):
делись и переделывай с указанием автора, не для продажи, на тех же
условиях. Код из статей и примеров — [MIT](LICENSE-CODE). Подробно —
[LICENSE.md](LICENSE.md).
