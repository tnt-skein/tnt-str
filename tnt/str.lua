--- Строки: то, чего не хватает, когда в строках кириллица.
---
--- Строка в Lua — это байты. `#'Узел'` равно восьми, `('Узел'):upper()`
--- возвращает «Узел», `('Кластер'):sub(1, 3)` отдаёт «К» и половину
--- буквы, а `('  Узел\194\160'):gsub('%s+$', '')` не снимает неразрывный
--- пробел, потому что не видит его. На латинице ничего этого не заметно;
--- у нас заметно каждый раз. Пакет убирает ровно эти грабли.
---
---     local str = require('tnt.str')
---
---     str.upper('узел')                    --> УЗЕЛ
---     str.length('Узел')                   --> 4
---     str.limit('Список узлов кластера', 12) --> Список узло…
---     str.slug('Список Узлов')             --> spisok-uzlov
---     str.plural(5, { 'узел', 'узла', 'узлов' }) --> узлов
---
---     str.of('  Список Узлов '):trim():slug():value()  --> spisok-uzlov
---
--- Настроек у пакета нет, и потому нет ни `configure`, ни `new`,
--- ни `default`, ни `status`: настраивать здесь нечего, внешних средств
--- пакет не берёт, состояния не держит. Он основание — его берут строки
--- в каждом слое приложения, и лишняя зависимость расползлась бы вместе
--- с ним. Из внешнего только встроенные `utf8`, `string`, `table` и `iconv`,
--- бросок без места из `tnt-must` да внешние зависимости `tnt-external` —
--- ради одной необязательной зависимости: рок `lrexlib-pcre2` даёт
--- `regex_*`, а без него пакет работает как прежде и `regex_available()`
--- отвечает «нет».
---
--- Чего в пакете намеренно нет и почему — в `docs/str.md`, раздел «Чем
--- пришлось поступиться». Коротко: английской морфологии (`plural`/
--- `singular`) нет, зато есть русское согласование с числом; `swap`
--- переворачивает регистр, а не заменяет по словарю; случайных строк
--- нет — случайность не дело строк.
---
--- Отказ возвращается парой `nil, err` там, где отказ вообще бывает:
--- `to_number('двенадцать')`, `between` без второй границы, `excerpt`
--- без искомого, `decode` на битом файле. Негодный аргумент — число вместо
--- строки, пустой список форм — роняет вызов: это ошибка программиста,
--- а не случай из жизни.

local case = require('tnt.str.case')
local checks = require('tnt.str.checks')
local convert = require('tnt.str.convert')
local cut = require('tnt.str.cut')
local edit = require('tnt.str.edit')
local encoding = require('tnt.str.encoding')
local fluent = require('tnt.str.fluent')
local regex = require('tnt.str.regex')
local russian = require('tnt.str.russian')

local Module = {}

-- Регистр.
Module.upper = case.upper
Module.lower = case.lower
Module.ucfirst = case.ucfirst
Module.lcfirst = case.lcfirst
Module.swap = case.swap
Module.camel = case.camel
Module.studly = case.studly
Module.pascal = case.pascal
Module.snake = case.snake
Module.kebab = case.kebab
Module.title = case.title
Module.headline = case.headline
Module.words_of = case.words_of

-- Вырезка.
Module.limit = cut.limit
Module.words = cut.words
Module.before = cut.before
Module.before_last = cut.before_last
Module.after = cut.after
Module.after_last = cut.after_last
Module.between = cut.between
Module.between_first = cut.between_first
Module.take = cut.take
Module.excerpt = cut.excerpt

-- Проверки.
Module.contains = checks.contains
Module.contains_all = checks.contains_all
Module.starts_with = checks.starts_with
Module.ends_with = checks.ends_with
Module.is = checks.is
Module.is_match = checks.is_match
Module.is_empty = checks.is_empty
Module.is_ascii = checks.is_ascii
Module.is_json = checks.is_json
Module.is_url = checks.is_url
Module.is_uuid = checks.is_uuid

-- Правка.
Module.replace = edit.replace
Module.replace_first = edit.replace_first
Module.replace_last = edit.replace_last
Module.replace_array = edit.replace_array
Module.remove = edit.remove
Module.substr_count = edit.substr_count
Module.squish = edit.squish
Module.trim = edit.trim
Module.ltrim = edit.ltrim
Module.rtrim = edit.rtrim
Module.pad_left = edit.pad_left
Module.pad_right = edit.pad_right
Module.pad_both = edit.pad_both
Module.repeat_times = edit.repeat_times
Module.reverse = edit.reverse
Module.wrap = edit.wrap
Module.unwrap = edit.unwrap
Module.word_wrap = edit.word_wrap
Module.word_count = edit.word_count
Module.start = edit.start
Module.finish = edit.finish

-- Преобразование.
Module.slug = convert.slug
Module.mask = convert.mask
Module.chunk = convert.chunk
Module.split = convert.split
Module.lines = convert.lines
Module.to_number = convert.to_number
Module.to_boolean = convert.to_boolean
Module.length = convert.length
Module.width = convert.width
Module.position = convert.position

-- Перекодировка.
Module.decode = encoding.decode
Module.encode = encoding.encode

-- Регулярные выражения: только с роком lrexlib-pcre2.
Module.regex_available = regex.available
Module.regex_is = regex.is
Module.regex_match = regex.match
Module.regex_match_all = regex.match_all
Module.regex_replace = regex.replace
Module.regex_split = regex.split

--- Кириллица латиницей; `ascii` — то же самое под привычным именем.
Module.transliterate = russian.transliterate
Module.ascii = russian.transliterate

-- Русский язык.
Module.plural = russian.plural
Module.plural_form = russian.plural_form
Module.counted = russian.counted

--- Действия цепочки — это всё, что умеет фасад.
---
--- Список снимается копией, а не ссылкой: `of` попадёт в `Module` следующей
--- строкой, и по ссылке оно оказалось бы и действием цепочки тоже.
local actions = {}

for name, action in pairs(Module) do
    actions[name] = action
end

local of = fluent.factory(actions)

--- Начало цепочки: `str.of(text):trim():slug():value()`.
---@param text string
---@return TntStrFluent
function Module.of(text)
    return of(text)
end

return Module
