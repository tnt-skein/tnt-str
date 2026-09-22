# tnt-str

Строки для Tarantool, в которых кириллица: длина, срез, обрезка
и дополнение считают знаки, а не байты; транслитерация даёт адрес
из русского заголовка, согласование с числом — «5 узлов» вместо «5 узел».

```lua
local str = require('tnt.str')

str.length('Узел')                          --> 4, а не 8
str.upper('узел')                           --> 'УЗЕЛ'
str.limit('Список узлов кластера', 12)      --> 'Список узлов…'
str.slug('Список Узлов')                    --> 'spisok-uzlov'
str.plural(5, { 'узел', 'узла', 'узлов' })  --> 'узлов'
str.trim('Узел\194\160')                    --> 'Узел' — неразрывный пробел снят

str.of('  Список Узлов '):trim():slug():value()  --> 'spisok-uzlov'
```

Зависимости: `tnt-must` (бросок без места) и `tnt-external` (подмена
необязательного рока в проверках). Регулярные выражения PCRE2 — с роком
`lrexlib-pcre2`, который ставится отдельно; без него пакет работает
как прежде.

## Зачем

Строка в Lua — это байты, и вся стандартная библиотека считает байты:
`#'Узел'` равно восьми, `('узел'):upper()` оставляет строку как была,
`sub(1, 3)` разрубает букву пополам, а шаблон `%s` не видит неразрывный
пробел. На латинице этого не заметно, на кириллице — каждый раз. Пакет:

- **считает знаки там, где число видно снаружи** — длина, срез, обрезка,
  дополнение, переворот; а ищет и заменяет байтами, потому что в UTF-8
  это безопасно и быстрее;
- **снимает все пробельные знаки Unicode**, включая неразрывный пробел,
  который приезжает из текста, набранного человеком;
- **знает русский**: транслитерация для адресов («Юрия» → `Yuriya`,
  а не `Iuriia`), три формы слова при числе с ловушкой одиннадцати–
  четырнадцати, ширина строки в ячейках терминала для ровных столбцов;
- **перекодирует** cp1251, koi8-r и прочее в UTF-8 и обратно поверх
  встроенного `iconv`, отвечая отказом парой `nil, err`, а не исключением.

## Установка

```sh
tt rocks install tnt-str --server=https://tnt-skein.github.io/rocks
```

Или из исходников:

```sh
git clone https://github.com/tnt-skein/tnt-str.git
cd tnt-str && tt rocks make
```

Зависимости `tnt-must` и `tnt-external` ставятся с того же сервера.

### Регулярные выражения PCRE2

Рок `lrexlib-pcre2` необязателен и в зависимостях не объявлен: это модуль
на C поверх системной библиотеки pcre2. Нужны сама библиотека
с заголовками, компилятор C и заголовки Tarantool:

```sh
# macOS с Homebrew
brew install pcre2
tt rocks install --server=https://luarocks.org lrexlib-pcre2 2.9.4-1 PCRE2_DIR=$(brew --prefix pcre2)

# Debian и Ubuntu
apt-get install -y libpcre2-dev gcc tarantool-dev
tt rocks install --server=https://luarocks.org lrexlib-pcre2 2.9.4-1 \
    PCRE2_DIR=/usr LUA_INCDIR=/usr/include/tarantool
```

Без рока `str.regex_available()` отвечает `false`, а `regex_*` роняют
вызов с подсказкой, что поставить. В каталоге пакета то же делает
`make deps-regex`.

## Как пользоваться

| Группа | Действия |
|---|---|
| Регистр | `upper`, `lower`, `ucfirst`, `lcfirst`, `swap`, `camel`, `studly`, `pascal`, `snake`, `kebab`, `title`, `headline`, `words_of` |
| Вырезка | `limit`, `words`, `before`, `before_last`, `after`, `after_last`, `between`, `between_first`, `take`, `excerpt` |
| Проверки | `contains`, `contains_all`, `starts_with`, `ends_with`, `is`, `is_match`, `is_empty`, `is_ascii`, `is_json`, `is_url`, `is_uuid` |
| Правка | `replace`, `replace_first`, `replace_last`, `replace_array`, `remove`, `substr_count`, `squish`, `trim`, `ltrim`, `rtrim`, `pad_left`, `pad_right`, `pad_both`, `repeat_times`, `reverse`, `wrap`, `unwrap`, `word_wrap`, `word_count`, `start`, `finish` |
| Преобразование | `slug`, `mask`, `chunk`, `split`, `lines`, `to_number`, `to_boolean`, `length`, `width`, `position` |
| Русский язык | `transliterate` (он же `ascii`), `plural`, `plural_form`, `counted` |
| Перекодировка | `decode`, `encode` |
| Регулярные выражения | `regex_available`, `regex_is`, `regex_match`, `regex_match_all`, `regex_replace`, `regex_split` — только с роком `lrexlib-pcre2` |
| Цепочка | `of` |

```lua
str.pad_left('7', 3, '0')                     --> '007'
str.mask('taylor@example.com', '*', 4, 3)     --> 'tay***@example.com'
str.snake('HTTPСервер')                       --> 'http_сервер'
str.counted(11, { 'узел', 'узла', 'узлов' })  --> '11 узлов'
str.width('日本')                             --> 4: две ячейки на иероглиф
str.decode('\207\240\232\226\229\242', 'cp1251')  --> 'Привет'
str.regex_match('storage-001', '^(\\w+)-(\\d+)$') --> 'storage', '001'
```

Цепочка `str.of(text)` зовёт те же действия по порядку чтения: строка
продолжает цепочку, всё прочее — число, список, `true` — из неё выходит.
Опечатка в имени действия роняет вызов на месте, а не возвращает тихий
`nil`.

Отказ — пара `nil, err` там, где отказ бывает: `to_number('двенадцать')`,
`between` без второй границы, `decode` на битом файле. Негодный аргумент —
число вместо строки, NaN или бесконечность вместо ширины, дробь вместо
счёта знаков, пустой список форм — роняет вызов: это ошибка программиста,
а не случай из жизни.

## Проверки

```sh
make deps          # luatest, luacheck, luacov с cluacov и зависимости пакета в .rocks
make deps-regex    # необязательный рок lrexlib-pcre2 — для живых проверок регулярных выражений
make check         # форматирование, линт, проверки, покрытие с порогом 100 %
make mutants-all   # мутационное тестирование утилитой tnt-mutants из PATH, порог 100 % убитых
```

Покрытие строк — 100 %, убитых мутантов — 100 % (226 проверок, 1050 мутантов
в тринадцати модулях). Обвязка регулярных выражений проверяется на двойнике
движка, сам движок — семью живыми проверками с настоящим роком; без рока
они пропускаются.

## Документ

Полное описание с обоснованием решений: [docs/str.md](docs/str.md).

## Лицензия

MIT.
