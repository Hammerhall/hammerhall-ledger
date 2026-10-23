# Деньги в коде: копейки, скидки, округление

> «От системы к делу» · статья 14 · читать минут 30
>
> **Для кого.** Ты прочитал статьи 0–13, и у тебя есть песочница
> `game-day` после статьи 13. Особенно пригодятся `CHECK` и Postgres
> на минуту (статья 3а), `Locale.ROOT` (статья 8), `Comparator`
> (статья 12) и доля в `double` (статья 13).
>
> **Что будет.** Почему деньги считают целыми копейками, а не `double`;
> как посчитать цену со скидками — в каком порядке и куда девать
> полкопейки; как правило «ровно одно из двух» держат и база, и код.
>
> **Откуда статья.** Раздел «Буткемп / Лаборатория» — о том, как пишут
> код команды Hammerhall: буткемп работает в открытых репозиториях,
> лаборатория — в закрытых. Серия «От системы к делу» — следующий шаг
> после «От Spring к системе»: как правила дела — сроки, деньги,
> обещания людям — живут в коде. Примеры — учебные: их можно повторить
> у себя.

---

## Зачем считать деньги отдельно

Деньги отличаются от других чисел тем, что ошибку в копейку видят.
Человек сверяет сумму в сообщении с суммой в банке. Менеджер называет
цену вслух, когда дорога человека из статьи 12 доходит до остановки
«**сколько он заплатит**». Разбор «цена минус скидки» обязан сходиться
до копейки, иначе это не разбор, а повод для спора. Поэтому сумму
округляют только по правилу, которое кто-то принял и записал.

Деление целых и округление встречаются не только в деньгах: сколько
страниц нужно, чтобы показать 41 строку по 20, сколько групп по
12 человек наберётся из записавшихся. То, что ниже, пригодится и там.

Куски учебной CRM клуба из статей 12–13 — для чтения, выброшенное
в них помечено `// …`. Главное держит свой код — маленькая модель
на чистой Java в пакете `example.crm`: скидка `Discount`, разбор цены
`PriceBreakdown`, расчёт `Checkout`, показ суммы `Rubles` и тесты
`CheckoutTest` и `RublesTest`.

В коротких примерах нет строк `import` — полные файлы своего кода
в конце статьи.

---

## Часть 1. Копейки в long

### Почему не double

Сложи в Java десять копеек и двадцать:

```java
System.out.println(0.1 + 0.2);            // 0.30000000000000004
System.out.println(0.1 + 0.2 == 0.3);     // false
```

Это не ошибка Java. `double` хранит число **двоичной дробью** — суммой
половинок, четвертей, восьмых и так далее. Одну десятую так точно
не записать, как одну треть десятичной дробью: 0,333… где-то
обрывается. В `double` лежит ближайшее представимое число, и при
вычислениях хвосты всплывают.

В статье 13 доля на панели считалась в `double`, и его точности
хватало: 1 из 3 — это `33.333333333333336` %, но после округления
до десятых на панели всё равно 33,3. Для денег беда не в семнадцатом
знаке, а в копейке:

```java
double price = 1.15;                      // цена в рублях
long kopecks = (long) (price * 100);      // 114 — копейка пропала
```

`1.15 * 100` в `double` — это `114.99999999999999`, а приведение
`(long)` просто отбрасывает дробную часть. Сумма в базе на копейку
разошлась с суммой в счёте. То же со скидкой: месяц за 3 500 ₽
со скидкой 30 % — ровно 2 450 ₽, а `(long) (350_000 * 0.7)` в копейках
даст 244 999: 0,7 в двоичной дроби чуть меньше семи десятых. Десять
платежей по 10 копеек, сложенные в `double`, дают `0.9999999999999999`
рубля.

Документация Postgres о своих дробных типах говорит прямо: для точного
хранения и вычислений, «such as for monetary amounts», бери `numeric` —
точную десятичную дробь. Учебная CRM пойдёт другим точным путём —
целыми копейками.

### Целые копейки

Решение старое и простое: считать в **младших единицах** валюты
и хранить целым числом. У рубля это копейки, и 1,15 ₽ — это 115 копеек.
Сложение, вычитание и сравнение целых в Java точны, пока число
помещается в тип.

В учебной модели так везде, и это видно по именам: `baseMinor`,
`amountMinor`, `finalMinor`. **Minor** — «младшая единица» (minor
unit): так её зовёт стандарт кодов валют ISO 4217. В базе — `BIGINT`.
Так выглядела бы цена в таблице тарифов системы клуба:

```sql
-- учебная система клуба: таблица тарифов, кусок
price_minor   BIGINT      NOT NULL,
currency      CHAR(3)     NOT NULL DEFAULT 'RUB',
```

`BIGINT` в Postgres и `long` в Java — одно и то же: целое в восемь
байт. Почему не `int`: его потолок — 2 147 483 647 копеек, около
21,5 миллиона рублей. На цену абонемента хватит, а выручка клуба
за год складывается из многих оплат — на неё может уже не хватить.
При этом переполнение `int` исключения не бросает: сумма молча
превращается в мусор. Потолок `long` — больше 9·10¹⁸ копеек.

### Валюта — часть суммы

Число копеек без валюты — полсуммы: 3 000 000 — это тридцать тысяч
рублей или три миллиона иен? Поэтому рядом с суммой стоит
`currency CHAR(3)` — трёхбуквенный код по ISO 4217: `RUB`, `EUR`,
`JPY`. От валюты зависит и сама «копейка»: у рубля и евро младших
единиц сто, а у иены дробной части нет вовсе. Java это знает:

```java
Currency.getInstance("RUB").getDefaultFractionDigits();   // 2
Currency.getInstance("JPY").getDefaultFractionDigits();   // 0
```

Цену тарифа учебная CRM у себя не хранит — часть 2 объяснит почему.
Она спрашивает её у системы клуба при каждом расчёте и получает вместе
с кодом валюты. Правило то же: сумма без известной валюты не ходит.
Клуб продаёт в рублях, и скидка суммой считается в той же валюте, что
и цена.

### Копейки — в коде, рубли — на экране

Человеку копейки не показывают. Менеджер видит цену в тексте задачи,
человек — в сообщении. Печатает её свой класс `Rubles`:

```java
public static String format(long minor) {
    if (minor < 0) {
        throw new IllegalArgumentException("сумма меньше нуля: " + minor);
    }
    String whole = String.format(Locale.ROOT, "%,d", minor / 100).replace(',', ' ');
    long kopecks = minor % 100;
    return kopecks == 0 ? whole + " ₽" : String.format(Locale.ROOT, "%s,%02d ₽", whole, kopecks);
}
```

* `String.format(локаль, шаблон, …)` — подставить значения в шаблон
  на места `%…`; `%s` — значение как есть, строкой;
* `minor / 100` — целые рубли; `% 100` — остаток, копейки;
* `%,d` — целое с разделителем тысяч. Каким — решает локаль.
  С `Locale.ROOT` это запятая, `30,000`, и `replace` меняет её
  на пробел;
* `%02d` — две цифры, ноль впереди: 5 копеек станут `,05`;
* `условие ? это : то` — выбор из двух значений: копеек нет — рубли
  без хвоста;
* сумма меньше нуля — исключение. Расчёт ниже в минус не уводит.
  Отрицательная «цена» на экране значит ошибку где-то раньше — пусть
  она будет громкой.

`Rubles.format(3_000_000)` даёт `30 000 ₽`, `Rubles.format(2_650_050)`
даёт `26 500,50 ₽`, а пять копеек — `0,05 ₽`. Так и проверяет
`RublesTest`.

⚠️ Частая ошибка — `String.format("%,d", n)` без локали. Такой вызов
берёт локаль машины, а она у всех разная (статья 8): для `30000`
немецкая даст `30.000`, швейцарская `de-CH` — `30’000`. А русская, хоть
текст и русский, поставит неразрывный пробел U+00A0 — на вид как
обычный, но строка уже другая: сравнение с `"30 000"` даст `false`.
С `Locale.ROOT` строка одна на любой машине.

Проверь сам: замени в `Rubles` первый `Locale.ROOT`
на `Locale.of("ru")` — локаль по коду языка. `RublesTest` покраснеет
на двух строках, а в сообщении
`expected` и `but was` будут на вид одинаковые.

Форматирование — последний шаг. В коде, в базе, в ответе системы
клуба — копейки в `long`; «30 000 ₽» живёт только в тексте для
человека, и обратно из такой строки сумму не разбирают.

### BigDecimal — когда копеек мало

В Java есть и точная десятичная дробь — **`BigDecimal`** из пакета
`java.math`. Она хранит число как целое плюс «сколько знаков после
запятой», поэтому `0.1` в ней — ровно одна десятая. Нужна она там, где
доля копейки — часть правила: ставка по вкладу, курс валюты, налог,
сумма, поделённая на троих.

Две вещи о ней надо знать сразу.

⚠️ Создают её из строки, а не из `double`. `new BigDecimal(0.1)` честно
перенесёт двоичный хвост:
`0.1000000000000000055511151231257827021181583404541015625`.
`new BigDecimal("0.1")` — ровно `0.1`. Документация Java советует
именно конструктор из строки.

⚠️ Деление без указания округления падает, если дробь бесконечна:
`new BigDecimal("100").divide(new BigDecimal("3"))` бросит
`ArithmeticException: Non-terminating decimal expansion…`. Сколько
знаков оставить и как округлить (`RoundingMode`), указывают явно:
`divide(new BigDecimal("3"), 2, RoundingMode.HALF_EVEN)` даст `33.33`
(`HALF_EVEN` округляет к ближайшему, а ровную половину — к чётной цифре).
`BigDecimal` не решает за тебя — заставляет решить.

Учебной модели хватает целых: все суммы — целые копейки. Дробь
возникает в одном месте, в проценте скидки, и округляется сразу, одной
строкой. Какой — в части 3.

---

## Часть 2. Цена тарифа и скидки человека

### Кто за что отвечает

За ценой два вопроса, и отвечают на них разные программы. «Сколько
стоит этот тариф» — разовое занятие, месяц, год? Это свойство тарифа.
«Сколько заплатит этот человек» — со скидкой за годовой, по акции,
с личной скидкой от менеджера? Это предмет CRM: скидки рождаются
в разговоре, а разговор — её хозяйство (статья 12).

Цену тарифа сайт клуба и касса показывают без CRM: продажа обязана
работать, даже когда CRM недоступна. Значит, цена живёт в системе
клуба. Копия в CRM стала бы второй правдой (статья 12): в системе клуба
годовой подорожал, в CRM висит старая цена, и менеджер называет человеку
не ту сумму. Поэтому CRM спрашивает цену у системы клуба при каждом
расчёте и не хранит её.

💡 В рабочем проекте команды копию цены однажды так и убрали — новой
миграцией: применённую не правят (статья 3а). В миграции оставили
комментарий: цена здесь больше не хранится, она приходит при каждом
расчёте. Решение записано там, где его увидит следующий читатель схемы.

Вход службы расчёта в учебной CRM:

```java
// учебная служба цен: вход и порядок скидок — сокращено
public interface PriceService {
    // Порядок: сначала общие скидки тарифа — проценты, потом суммы; процент каждой
    // следующей считается от цены после предыдущих. Личные скидки лида — потом, поверх.
    PriceBreakdown quote(long baseMinor, UUID leadId, String tariff);
}
```

Читается так: дай цену тарифа в копейках, лида и тариф — получишь
разбор цены. Цену CRM только что спросила у системы клуба. Порядок
скидок записан комментарием рядом с методом: кто откроет службу,
увидит правило раньше кода. Почему порядок вообще важен — часть 3.

Разбор — своя запись `PriceBreakdown`, на чистой Java:

```java
public record PriceBreakdown(long baseMinor, long finalMinor, List<Applied> applied) {

    public record Applied(String code, long discountMinor) {      // что дала каждая скидка
    }
    // … компактный конструктор проверяет, что разбор сходится, — часть 3
}
```

`Applied` — запись внутри записи; снаружи её зовут
`PriceBreakdown.Applied`. Заметь, что она хранит: не «скидка −10 %»,
а **сколько копеек скидка дала**. Менеджеру, который объясняет человеку
цену, нужно именно это: «30 000, минус 3 000 за годовой, минус 500
за друга — 26 500».

Общие скидки тарифа учебная CRM держит в таблице скидок (она ниже),
личные — отдельно, у лида; как их хранят, серия не разбирает. Своя
модель держит одну группу, как общие скидки тарифа: личных в ней нет.

### Правило: процент или сумма — ровно одно

Скидка задаётся одним из двух способов: «−10 %» или «−500 ₽». Оба поля
живут в одной строке таблицы:

```sql
-- учебная CRM клуба: общие скидки тарифов
CREATE TABLE sales.discount (
    code          VARCHAR(50)  PRIMARY KEY,
    tariff        VARCHAR(20)  NOT NULL,
    percent       SMALLINT,
    amount_minor  BIGINT,
    valid_from    DATE,
    valid_to      DATE,
    CONSTRAINT discount_percent_or_amount CHECK (
        (percent IS NOT NULL AND amount_minor IS NULL) OR
        (percent IS NULL AND amount_minor IS NOT NULL)),
    CONSTRAINT discount_percent_range CHECK (
        percent IS NULL OR percent BETWEEN 1 AND 100)
);
```

Первая проверка — **ровно одно** из двух полей: процент без суммы или
сумма без процента. Вторая — процент от 1 до 100. `SMALLINT` — короткое
целое в два байта. `DATE` — дата без времени, в Java это `LocalDate`
из статьи 12. Обе проверки названы через `CONSTRAINT`, как в статье 3а, —
и база назовёт имя в ошибке.

В сущности учебной CRM (статья 3б) этим столбцам соответствовали бы
поля `Short percent` и `Long amountMinor`. Это обёртки, как `Boolean`
из статьи 4, а не `short` и `long`: у каждой строки одно из полей
пусто, а примитив пустым не бывает.

Попробуй в `psql` — в Postgres на минуту из статьи 3а. Схему создай
руками, `CREATE SCHEMA sales;`, потом `CREATE TABLE` целиком и строка
с обеими скидками:

```sql
INSERT INTO sales.discount (code, tariff, percent, amount_minor)
VALUES ('both', 'year', 10, 50000);
```

```
ERROR:  new row for relation "discount" violates check constraint "discount_percent_or_amount"
DETAIL:  Failing row contains (both, year, 10, 50000, null, null).
```

Строка без обоих полей получает ту же ошибку, процент 0 или 101 —
`discount_percent_range`, а 100 проходит. `UPDATE`, который допишет
сумму к процентной скидке, — тоже отказ.

🔑 Правило дела, записанное в базе, держится при любом коде. Строку
может завести служба, скрипт переноса данных или человек руками
в `psql`. Всё равно «и процент, и сумма» в таблицу не попадёт. Проверка
в таблице — последний рубеж (статья 3а). Здесь он стережёт
не опечатку, а правило дела: скидки «−10 % и −500 ₽ одной
строкой» не бывает, и как её считать, не знает никто.

### То же правило в Java: Discount

А в Java? Тоже нужно. Скидка своей модели — запись с проверками
в компактном конструкторе (статья 0):

```java
public record Discount(String code, Integer percent, Long amountMinor) {

    public Discount {
        // … код скидки не пустой
        if ((percent == null) == (amountMinor == null)) {          // оба пусты или оба заданы
            throw new IllegalArgumentException("скидка " + code + ": процент или сумма — ровно одно");
        }
        if (percent != null && (percent < 1 || percent > 100)) {
            throw new IllegalArgumentException("скидка " + code + ": процент — от 1 до 100");
        }
    }

    public static Discount percent(String code, int percent) {
        return new Discount(code, percent, null);
    }

    public static Discount amount(String code, long amountMinor) {
        return new Discount(code, null, amountMinor);
    }

    // … isPercent() и from(price) — в части 3
}
```

`(percent == null) == (amountMinor == null)` — то же «ровно одно», что
в `CHECK`, только короче: если оба `null` или оба нет, левая и правая
части равны — значит, ошибка. Неверная скидка не создастся вовсе —
главная мысль статьи 0. `Integer` и `Long` — снова обёртки: у скидки
процентом сумма — `null`.

`percent` и `amount` — фабричные методы из статьи 0. Скидка «−10 %
за годовой» в виде `Discount.percent("year-10", 10)` читается лучше,
чем `new Discount("year-10", 10, null)`. И `null` руками никто
не пишет.

Код ловит ошибку раньше и с понятным текстом, база — наверняка. Одно
другого не заменяет.

💡 Попробуй сам: `Discount.amount("minus", -50_000)` модель примет.
Такая «скидка» поднимала бы цену на 500 ₽; расчёт её молча пропустит
(где — увидишь в части 3), и о мусоре в данных никто не узнает. Какую
проверку ты добавил бы в компактный конструктор — и какой `CHECK`
рядом в таблицу?

### Действует по датам

У скидки в таблице есть `valid_from` и `valid_to`, обе необязательны:
осенняя акция живёт неделю, скидка за годовой — всегда. Проверка
в учебной службе — одно условие:

```java
// учебная служба цен: действует ли скидка в день расчёта
LocalDate today = LocalDate.now(clock);                  // какой сегодня день — по часам, как в статье 12
boolean active = (validFrom == null || !today.isBefore(validFrom))
        && (validTo == null || !today.isAfter(validTo));
```

`validFrom` и `validTo` — `valid_from` и `valid_to` этой скидки,
`LocalDate` или `null`. Прочитай вслух: «начала нет или сегодня
не раньше начала — и конца нет или сегодня не позже конца». Двойное
«не» здесь ради одного: **обе границы включительно**.

Акция «с 1 по 7 октября» действует и 1-го, и 7-го. Напиши
`today.isAfter(validFrom)` — и первый день акции выпадет. Пустая
граница — «без ограничения».

«Сегодня» берётся из часов `Clock` через `LocalDate.now(clock)`, как
в статье 12.
С остановленными часами тест проверит и 7 октября, и 8-е в любой день
года.

---

## Часть 3. Порядок и округление

### Каскад: каждая скидка — от остатка

Скидки применяются по одной, и каждая считается от цены **после**
предыдущих — **каскадом**. Так считает `Checkout` своей модели:

```java
static final Comparator<Discount> ORDER =
        Comparator.comparing((Discount discount) -> !discount.isPercent())   // сначала проценты
                .thenComparing(Discount::code);                              // потом по коду

public static PriceBreakdown price(long baseMinor, List<Discount> discounts) {
    return cascade(baseMinor, discounts.stream().sorted(ORDER).toList());
}

static PriceBreakdown cascade(long baseMinor, List<Discount> inOrder) {      // как пришли, без сортировки
    long price = baseMinor;
    List<PriceBreakdown.Applied> applied = new ArrayList<>();
    for (Discount discount : inOrder) {
        long given = discount.from(price);                                   // сколько снимет — ниже
        if (given > 0) {
            price -= given;
            applied.add(new PriceBreakdown.Applied(discount.code(), given));
        }
    }
    return new PriceBreakdown(baseMinor, price, applied);
}
```

`price` сортирует скидки и зовёт `cascade`. Шаги `stream()`, `sorted`
и `toList()` знакомы по статье 11, `Comparator.comparing(ключ)` — по
статье 12. Новое — `thenComparing`: при равных ключах сравнить ещё
по второму.

Ключ здесь — `!discount.isPercent()`: у процентной скидки это `false`,
у скидки суммой — `true`, а `false` при сравнении идёт раньше `true`.
Значит, сначала проценты. Второй ключ — `Discount::code`: код скидки,
по алфавиту.

Тип параметра в лямбде `(Discount discount)` написан явно. Обычно
Java выводит его сама, но не в начале цепочки
`comparing(…).thenComparing(…)`: без подсказки она решит, что
`discount` — просто `Object`, не найдёт у него `isPercent()`, и код
не соберётся.

`if (given > 0)` — скидка, которая ничего не дала (цена уже ноль),
в разбор не попадает. Не попадёт и «скидка» меньше нуля из 💡
части 2: она отброшена здесь же, молча.

У `ORDER` и `cascade` нет `public`: они видны только своему пакету.
`cascade` нужен тесту — показать, как порядок меняет итог.

### Почему порядок важен

Годовой абонемент — 30 000 ₽, две скидки: −10 % за годовой и −500 ₽
по акции «приведи друга».

| порядок | шаг 1 | шаг 2 | итог |
|---|---|---|---|
| процент → сумма | −10 % от 30 000 = −3 000 | −500 | **26 500 ₽** |
| сумма → процент | −500 | −10 % от 29 500 = −2 950 | **26 550 ₽** |

Разница — 50 ₽, десять процентов от тех самых 500. Процент от меньшего
числа меньше — поэтому «сначала проценты» выгоднее человеку. Порядок
задают продажи. Учебная CRM выбрала «сначала проценты» и записала это
комментарием у службы. Код обязан исполнять выбранный порядок каждый
раз одинаково.

Отсюда вторая половина сортировки, по коду. Без неё скидки шли бы
в том порядке, в каком их вернула база. А без `ORDER BY` Postgres
порядка строк не обещает: документация говорит «must not be relied
on». Хватит правки одной строки — и при следующем чтении она может
оказаться последней. Проверь в `psql`: заведи четыре скидки, поправь
первую `UPDATE` — и `SELECT` без `ORDER BY` отдаст её последней.

А даже два процента от перестановки могут разойтись на копейку, потому
что округление идёт на каждом шаге: 2 718,28 ₽ с −10 % и −15 % — это
2 079,48 ₽ в одном порядке и 2 079,47 ₽ в другом. Цена, которая
меняется между двумя нажатиями кнопки, — это жалоба, а не расчёт.

### Складываются ли скидки

Две процентные, 10 % и 15 %, дают не −25 %, а меньше: 30 000 → 27 000 →
22 950 ₽, всего −7 050 ₽, то есть 23,5 %. Так устроен каскад.
Складывать ли скидки вообще — и все ли со всеми: «за годовой»
с осенней акцией, акцию с личной скидкой — решают продажи и владелец
продукта. Код только считает каскадом.

Личные скидки лида учебная служба применяет после общих — поверх, как
сказано в комментарии к `quote`.

### Округление: вниз итог, а не скидку

Процент от целых копеек — не всегда целое. 50 % от 101 копейки —
50,5. Полкопейки не бывает: её кому-то отдают. Вот методы `Discount`,
которые это решают:

```java
public boolean isPercent() {
    return percent != null;
}

/** Сколько скидка снимет с цены price, в копейках. */
public long from(long price) {
    // Вниз округляем ИТОГ, а не скидку: полкопейки — человеку (101 коп. и −50% — итог 50, не 51).
    long discount = isPercent()
            ? price - Math.floorDiv(price * (100 - percent), 100)
            : amountMinor;
    return Math.min(discount, price);                          // скидка не больше цены: итог не в минус
}
```

`price * (100 - percent)` — сколько останется, в сотых долях копейки;
`Math.floorDiv(…, 100)` — вниз до целой копейки; скидка — разность
цены и того, что осталось. На 101 копейке и −50 %:

| что округляем вниз | скидка | итог |
|---|---|---|
| скидку: 50,5 → 50 | 50 | 51 |
| итог (так в модели): 50,5 → 50 | 51 | 50 |

Округляя вниз итог, полкопейки отдают человеку.

🔑 Куда деть полкопейки, решает не математика, а дело: в чью пользу.
Хороший код делает это в одном месте, одной строкой — и пишет рядом,
почему. Без комментария следующий читатель «упростит» формулу до
`price * percent / 100` и тихо поднимет цену на копейку.

**floorDiv против `/`.** `/` на целых округляет к нулю,
`Math.floorDiv` — всегда вниз. На положительных числах это одно и то
же; разница — на отрицательных: `-7 / 2` даёт `-3`,
а `Math.floorDiv(-7, 2)` — `-4`. Имя метода само
говорит, куда идёт округление, — и читателю не надо гадать, подумал ли
ты о знаке.

### Скидка не больше цены

`Math.min(discount, price)` — последняя строка `from`: скидка
не выходит за цену. Такую строку называют clamp — «зажим». «Приведи
друга» −500 ₽ на разовое занятие за 400 ₽ даст 400, итог — 0. В разбор
попадает то, что скидка дала на самом деле, — 400 ₽, а не запрошенные
500: так и проверяет тест `breakdownShowsWhatWasReallyGiven`.

### Разбор сходится до копейки

Разбор сам проверяет, что сходится, — в компактном конструкторе:

```java
public PriceBreakdown {
    applied = List.copyOf(applied);                            // своя неизменяемая копия
    long given = applied.stream().mapToLong(Applied::discountMinor).sum();   // сумма всех скидок
    if (baseMinor - given != finalMinor) {
        throw new IllegalArgumentException("разбор не сходится с итогом");
    }
}
```

`List.copyOf` — неизменяемая копия списка, как `Map.copyOf` в статье 9:
снаружи разбор не поправят. `mapToLong(Applied::discountMinor)` берёт
у каждой записи число копеек, `sum()` их складывает.

Возьми неровные цены (1, 7, 101, 250 000, 333 333 и 999 999 копеек)
и скидки −17 % и −25 ₽: сумма скидок из разбора плюс итог равны
исходной цене. На целых это так по построению: из цены вычитается ровно
то число, что записано в разбор. На `double` хвосты из части 1
копились бы на каждом шаге, и равенство пришлось бы проверять
«примерно». Здесь «скидки плюс итог равны цене» — правило самого
разбора: несходящийся разбор не создастся.

---

## Часть 4. Тест: правило в таблице

### Тест по таблице

Лучший способ проверить, что понял правило, — прогнать его тестом.
Случаи — строками `@CsvSource`, как в статье 0. Скидки в ячейке идут
через `;`: `10%` значит процент, `50000` — сумму в копейках. Разбирает
их маленький помощник `parse` в самом тесте.

```java
@ParameterizedTest(name = "{0} коп., скидки {1} → итог {2}")
@CsvSource(delimiter = '|', textBlock = """
        101     | 50%        | 50
        40000   | 50000      | 0
        3000000 | 10%;50000  | 2650000
        3000000 | 50000;10%  | 2650000
        3000000 | 10%;15%    | 2295000
        350000  | 30%        | 245000
        350000  | 100%;10000 | 0
        """)
void pricesByRule(long baseMinor, String discounts, long expectedMinor) {
    assertThat(Checkout.price(baseMinor, parse(discounts)).finalMinor()).isEqualTo(expectedMinor);
}

@Test
void orderChangesTheTotal() {
    Discount yearTen = Discount.percent("year-10", 10);
    Discount friend = Discount.amount("friend-500", 50_000);
    assertThat(Checkout.cascade(YEAR, List.of(yearTen, friend)).finalMinor()).isEqualTo(2_650_000);
    assertThat(Checkout.cascade(YEAR, List.of(friend, yearTen)).finalMinor()).isEqualTo(2_655_000);
}
```

`YEAR` — константа теста, годовой абонемент: `3_000_000` копеек.
Строки таблицы — по одной на мысль статьи: 101 копейка и −50 % дают 50;
скидка больше цены — 0; процент и сумма в любом порядке на входе дают
26 500 ₽, потому что `price` сортирует; два процента — каскад,
22 950 ₽; месяц за 3 500 ₽ с −30 % — ровно 2 450 ₽, без пропавшей
копейки из части 1; после 100 % следующей скидке нечего снимать.
`orderChangesTheTotal` зовёт `cascade` без сортировки и показывает
26 500 против 26 550.

В полном тесте — ещё три проверки: округление на 101 копейке,
«что скидка дала на самом деле» и «ровно одно» в конструкторе. Рядом —
`RublesTest`: четыре суммы и как они выглядят для человека.

### Тест умеет краснеть

Теперь сломай правило нарочно (статья 11). Каждая из трёх поломок
даёт свой красный:

* «вниз скидку»: замени в `from` формулу на
  `Math.floorDiv(price * percent, 100)`. Покраснеют первая строка
  таблицы с `expected: 50L but was: 51L` и `roundsTotalDownNotDiscount`;
* без сортировки: пусть `price` зовёт `cascade(baseMinor, discounts)`.
  Покраснеет строка `50000;10%`: `expected: 2650000L but was: 2655000L`;
* процент в `double`, как его часто пишут:
  `price - (long) (price * (1 - percent / 100.0))`. Покраснеет строка
  с −30 %: `expected: 245000L but was: 244999L`. Та же копейка, что
  у 1,15 в части 1: 0,7 в `double` чуть меньше семи десятых, и
  приведение `(long)` её отбросило.

`L` в сообщении — так AssertJ печатает `long`, как литерал в Java.
Верни всё как было.

---

## Проверь себя

Ответь своими словами — вслух или на бумаге. Не получается — перечитай
раздел.

1. Почему `(long) (1.15 * 100)` даёт 114? Что хранить вместо рублей
   в `double`?
2. Зачем рядом с суммой код валюты? Почему «две цифры после запятой» —
   не закон для всех валют?
3. Когда нужен `BigDecimal` и почему учебной модели хватает `long`?
   Чем опасен `new BigDecimal(0.1)` и чего `BigDecimal` требует при
   делении?
4. Почему цену тарифа CRM не хранит, а скидки хранит? Объясни через
   два вопроса: «сколько стоит тариф» и «сколько заплатит этот человек».
5. Что сторожит `discount_percent_or_amount`? Зачем проверка в базе,
   если такую же держит компактный конструктор `Discount`?
6. Годовой — 30 000 ₽, скидки −10 % и −500 ₽. Посчитай итог в обоих
   порядках. Какой порядок выбрала модель и зачем ей ещё сортировка
   по коду?
7. 101 копейка, −50 %. Что выйдет, если округлить вниз скидку, а что —
   если итог? Что выбрала модель и где это записано?
8. Почему `Rubles` форматирует тысячи с `Locale.ROOT`, а не с русской
   локалью, хотя текст русский?

---

## Что дальше

Дальше в серии — правила продаж: когда напомнить о продлении и кому
что предложить. Продажи меняют их чаще, чем выходит код, — почему тогда
им место в настройках, а не в константах.

## Первоисточники

* [Java SE 25: Math](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/lang/Math.html) —
  `floorDiv` и чем округление вниз отличается от деления к нулю;
* [Java SE 25: BigDecimal](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/math/BigDecimal.html) —
  почему конструктор из `double` «somewhat unpredictable» и как задают
  округление;
* [Java SE 25: Currency](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/Currency.html) —
  коды валют ISO 4217 и `getDefaultFractionDigits`: сколько у валюты
  младших единиц;
* [PostgreSQL: Numeric Types](https://www.postgresql.org/docs/current/datatype-numeric.html) —
  точные и неточные числа, что брать для денег;
* [PostgreSQL: Constraints](https://www.postgresql.org/docs/current/ddl-constraints.html) —
  `CHECK` на несколько столбцов и именованные ограничения.

---

## Пример целиком — с импортами

Учебный пример. Запускай в песочнице `game-day` после статьи 13: журнал
в `example.gameday.journal` со всем, что накопили статьи 1–10, сторожа
статьи 11, модель статей 12–13 в `example.crm` и её тесты, Postgres
в контейнере, охрана, Actuator и стенд — всё остаётся, менять ничего
не нужно. В `pom.xml` ничего не добавляй: коду статьи Spring не нужен,
JUnit и AssertJ — со `spring-boot-starter-test`.

Что добавить: в `src/main/java/example/crm/` — `Discount` (скидка),
`PriceBreakdown` (разбор цены), `Checkout` (расчёт) и `Rubles` (сумма
для человека), в `src/test/java/example/crm/` — `CheckoutTest`
и `RublesTest`. Пакет `example.crm` — рядом с `example.gameday`,
не внутри: сканирование Spring его не видит, а сторож статьи 11
смотрит только в папку журнала. Таблицу скидок из части 2 в песочницу
не клади: это SQL для `psql`, а не миграция журнала.

Запуск: треугольником у класса в IDE или
`./mvnw test -Dtest=CheckoutTest,RublesTest`; весь `./mvnw verify`
гоняет и `*IT` — нужен запущенный Docker. Путь к файлу — комментарием
в первой строке.

```java
// src/main/java/example/crm/Discount.java
package example.crm;

/**
 * Скидка: процент или фиксированная сумма в копейках — ровно одно. Учебная модель.
 *
 * @param code        код скидки: year-10 — за годовой, friend-500 — «приведи друга»
 * @param percent     процент от 1 до 100; у скидки суммой — null
 * @param amountMinor сумма в копейках; у скидки процентом — null
 */
public record Discount(String code, Integer percent, Long amountMinor) {

    public Discount {
        if (code == null || code.isBlank()) {
            throw new IllegalArgumentException("у скидки нет кода");
        }
        if ((percent == null) == (amountMinor == null)) {          // оба пусты или оба заданы
            throw new IllegalArgumentException("скидка " + code + ": процент или сумма — ровно одно");
        }
        if (percent != null && (percent < 1 || percent > 100)) {
            throw new IllegalArgumentException("скидка " + code + ": процент — от 1 до 100");
        }
    }

    public static Discount percent(String code, int percent) {
        return new Discount(code, percent, null);
    }

    public static Discount amount(String code, long amountMinor) {
        return new Discount(code, null, amountMinor);
    }

    public boolean isPercent() {
        return percent != null;
    }

    /** Сколько скидка снимет с цены price, в копейках. */
    public long from(long price) {
        // Вниз округляем ИТОГ, а не скидку: полкопейки — человеку (101 коп. и −50% — итог 50, не 51).
        long discount = isPercent()
                ? price - Math.floorDiv(price * (100 - percent), 100)
                : amountMinor;
        return Math.min(discount, price);                          // скидка не больше цены: итог не в минус
    }
}
```

```java
// src/main/java/example/crm/PriceBreakdown.java
package example.crm;

import java.util.List;

/** Разбор цены: с чего начали, чем кончили и какая скидка сколько дала. Учебная модель. */
public record PriceBreakdown(long baseMinor, long finalMinor, List<Applied> applied) {

    /** Применённая скидка: код и сколько копеек она дала на самом деле. */
    public record Applied(String code, long discountMinor) {
    }

    public PriceBreakdown {
        applied = List.copyOf(applied);                            // своя неизменяемая копия
        long given = applied.stream().mapToLong(Applied::discountMinor).sum();
        if (baseMinor - given != finalMinor) {
            throw new IllegalArgumentException("разбор не сходится с итогом");
        }
    }
}
```

```java
// src/main/java/example/crm/Checkout.java
package example.crm;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/** Расчёт цены: сначала проценты, потом суммы, по коду; каждая скидка — от остатка. Учебная модель. */
public final class Checkout {

    static final Comparator<Discount> ORDER =
            Comparator.comparing((Discount discount) -> !discount.isPercent())   // сначала проценты
                    .thenComparing(Discount::code);                              // потом по коду

    private Checkout() {
    }

    public static PriceBreakdown price(long baseMinor, List<Discount> discounts) {
        return cascade(baseMinor, discounts.stream().sorted(ORDER).toList());
    }

    /** Каскад в том порядке, в каком пришли скидки, — без сортировки. */
    static PriceBreakdown cascade(long baseMinor, List<Discount> inOrder) {
        long price = baseMinor;
        List<PriceBreakdown.Applied> applied = new ArrayList<>();
        for (Discount discount : inOrder) {
            long given = discount.from(price);
            if (given > 0) {                                                     // ноль — не в разбор
                price -= given;
                applied.add(new PriceBreakdown.Applied(discount.code(), given));
            }
        }
        return new PriceBreakdown(baseMinor, price, applied);
    }
}
```

```java
// src/main/java/example/crm/Rubles.java
package example.crm;

import java.util.Locale;

/** Сумма для человека: копейки — в коде, рубли — на экране. Учебная модель. */
public final class Rubles {

    private Rubles() {
    }

    /** 3 000 000 коп. — «30 000 ₽», 2 650 050 — «26 500,50 ₽»: копейки — только если они есть. */
    public static String format(long minor) {
        if (minor < 0) {
            throw new IllegalArgumentException("сумма меньше нуля: " + minor);
        }
        String whole = String.format(Locale.ROOT, "%,d", minor / 100).replace(',', ' ');
        long kopecks = minor % 100;
        return kopecks == 0 ? whole + " ₽" : String.format(Locale.ROOT, "%s,%02d ₽", whole, kopecks);
    }
}
```

```java
// src/test/java/example/crm/CheckoutTest.java
package example.crm;

import java.util.Arrays;
import java.util.List;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class CheckoutTest {

    // тарифы учебного клуба, в копейках
    private static final long VISIT = 40_000;        // разовое занятие — 400 ₽
    private static final long YEAR = 3_000_000;      // годовой абонемент — 30 000 ₽

    @ParameterizedTest(name = "{0} коп., скидки {1} → итог {2}")
    @CsvSource(delimiter = '|', textBlock = """
            101     | 50%        | 50
            40000   | 50000      | 0
            3000000 | 10%;50000  | 2650000
            3000000 | 50000;10%  | 2650000
            3000000 | 10%;15%    | 2295000
            350000  | 30%        | 245000
            350000  | 100%;10000 | 0
            """)
    void pricesByRule(long baseMinor, String discounts, long expectedMinor) {
        assertThat(Checkout.price(baseMinor, parse(discounts)).finalMinor()).isEqualTo(expectedMinor);
    }

    @Test
    void orderChangesTheTotal() {
        Discount yearTen = Discount.percent("year-10", 10);
        Discount friend = Discount.amount("friend-500", 50_000);
        assertThat(Checkout.cascade(YEAR, List.of(yearTen, friend)).finalMinor()).isEqualTo(2_650_000);
        assertThat(Checkout.cascade(YEAR, List.of(friend, yearTen)).finalMinor()).isEqualTo(2_655_000);
    }

    @Test
    void roundsTotalDownNotDiscount() {
        PriceBreakdown breakdown = Checkout.price(101, List.of(Discount.percent("half", 50)));
        assertThat(breakdown.applied()).containsExactly(new PriceBreakdown.Applied("half", 51));
        assertThat(breakdown.finalMinor()).isEqualTo(50);
    }

    @Test
    void breakdownShowsWhatWasReallyGiven() {
        PriceBreakdown breakdown = Checkout.price(VISIT, List.of(Discount.amount("friend-500", 50_000)));
        assertThat(breakdown.applied()).containsExactly(new PriceBreakdown.Applied("friend-500", 40_000));
    }

    @Test
    void discountIsPercentOrAmountNotBoth() {
        assertThatThrownBy(() -> new Discount("both", 10, 50_000L))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("ровно одно");
        assertThatThrownBy(() -> new Discount("none", null, null))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("ровно одно");
    }

    /** «10%» — скидка процентом, «50000» — суммой в копейках; несколько — через «;»; код — сам текст. */
    private static List<Discount> parse(String cell) {
        return Arrays.stream(cell.split(";"))
                .map(text -> text.endsWith("%")
                        ? Discount.percent(text, Integer.parseInt(text.substring(0, text.length() - 1)))
                        : Discount.amount(text, Long.parseLong(text)))
                .toList();
    }
}
```

```java
// src/test/java/example/crm/RublesTest.java
package example.crm;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class RublesTest {

    @ParameterizedTest(name = "{0} коп. → {1}")
    @CsvSource(delimiter = '|', textBlock = """
            3000000 | 30 000 ₽
            2650050 | 26 500,50 ₽
            40000   | 400 ₽
            5       | 0,05 ₽
            """)
    void showsKopecksOnlyIfAny(long minor, String expected) {
        assertThat(Rubles.format(minor)).isEqualTo(expected);
    }

    @Test
    void negativeSumIsNotShown() {
        assertThatThrownBy(() -> Rubles.format(-1))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("меньше нуля");
    }
}
```

**Порядок проверки** — из папки песочницы:

1. `./mvnw test -Dtest=CheckoutTest,RublesTest` — все зелёные:
   у `CheckoutTest` 11 запусков — семь строк таблицы и четыре теста,
   у `RublesTest` 5 — четыре строки и один тест; `./mvnw verify` —
   зелёный вместе с тестами прошлых статей, `TodayListTest`
   и `FunnelNumbersTest`, у сторожа статьи 11 по-прежнему 43 запуска:
   в папку журнала новые классы не попали, миграций не прибавилось;
2. что будет, если: «вниз скидку» — `Math.floorDiv(price * percent, 100)`
   в `from` — красные строка «101, 50%» и `roundsTotalDownNotDiscount`;
   без сортировки в `price` — красная строка `50000;10%`, `2655000`
   вместо `2650000`; процент в `double` — красная строка с −30 %,
   `244999` вместо `245000`; без `Math.min` — красные строки «скидка
   больше цены» и «после 100 %», итог `-10000`, и
   `breakdownShowsWhatWasReallyGiven`; без проверки «ровно одно»
   в конструкторе — красный `discountIsPercentOrAmountNotBoth`;
   `Locale.of("ru")` вместо первого `Locale.ROOT` в `Rubles` — красные
   строки `RublesTest` с тысячами, «30 000 ₽» и «26 500,50 ₽»;
   без `(Discount discount)` в лямбде `ORDER` — `Checkout`
   не собирается;
3. 💡 без `if (given > 0)` в `cascade` — все зелёные. После 100 % скидка
   суммой даёт ноль, и в разбор попадает строка «0 копеек», а ни один
   тест в разбор этой строки таблицы не смотрит. Хочешь, чтобы смотрел, —
   допиши проверку `applied()` сам;
4. таблица скидок из части 2 — в `psql`, в Postgres на минуту
   из статьи 3а: `CREATE SCHEMA sales;`, `CREATE TABLE` целиком,
   `INSERT` с обеими скидками — ошибка `discount_percent_or_amount`.
