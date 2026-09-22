rockspec_format = '3.0'

package = 'tnt-str'
version = 'scm-1'

source = {
    url = 'git+https://github.com/tnt-skein/tnt-str.git',
    branch = 'main',
}

description = {
    summary = 'Работа со строками, в которых кириллица',
    detailed = [[
        Строка в Lua — это байты: длина «Узел» равна восьми, `upper`
        оставляет кириллицу как была, срез разрубает букву пополам,
        а неразрывный пробел не снимается обрезкой, потому что шаблон `%s`
        его не видит. Пакет убирает ровно эти грабли: длина, срез, обрезка,
        дополнение до ширины и переворот считают знаки, а поиск и замена —
        байты, потому что в UTF-8 это безопасно и заметно быстрее.

        Сверх того, чего нет во встроенном `utf8`: транслитерация
        кириллицы для адресов («Список Узлов» → spisok-uzlov), русское
        согласование слова с числом (5 → «узлов») и ширина строки в ячейках
        терминала, по которой выравниваются столбцы вывода. Перекодировка
        cp1251 и прочих кодировок в UTF-8 и обратно — поверх встроенного
        iconv, с отказом парой вместо исключения. Регулярные выражения
        PCRE2 — с необязательным роком lrexlib-pcre2; без него пакет
        работает как прежде.

        Цепочка `str.of(text):trim():slug():value()` — тот же набор
        действий, записанный по порядку чтения.

        Зависимости: tnt-must (бросок без места и значение в тексте
        отказа) и tnt-external (подмена необязательного рока в проверках).
        Покрытие строк и убитых мутантов — 100 %.
    ]],
    homepage = 'https://github.com/tnt-skein/tnt-str',
    issues_url = 'https://github.com/tnt-skein/tnt-str/issues',
    maintainer = 'tnt-skein',
    license = 'MIT',
    labels = { 'tarantool', 'string', 'utf8', 'cyrillic', 'transliteration' },
}

dependencies = {
    'lua >= 5.1',
    -- Бросок без места: ошибка программиста читается текстом целиком,
    -- и NaN в нём назван одинаково на любой сборке.
    -- Пакет ядра и сам ни от чего не зависит — за собой ничего не тянет.
    'tnt-must',
    -- Внешние зависимости: через них подключается необязательный рок регулярных выражений.
    'tnt-external',
    -- Необязательно и здесь не объявлено: `lrexlib-pcre2` (модуль
    -- `rex_pcre2`) даёт `regex_*`, а без него пакет работает как прежде.
    -- Ставится целью `make deps-regex`.
}

build = {
    type = 'builtin',
    modules = {
        ['tnt.str'] = 'tnt/str.lua',
        ['tnt.str.chars'] = 'tnt/str/chars.lua',
        ['tnt.str.guard'] = 'tnt/str/guard.lua',
        ['tnt.str.json'] = 'tnt/str/json.lua',
        ['tnt.str.case'] = 'tnt/str/case.lua',
        ['tnt.str.edit'] = 'tnt/str/edit.lua',
        ['tnt.str.cut'] = 'tnt/str/cut.lua',
        ['tnt.str.checks'] = 'tnt/str/checks.lua',
        ['tnt.str.russian'] = 'tnt/str/russian.lua',
        ['tnt.str.convert'] = 'tnt/str/convert.lua',
        ['tnt.str.encoding'] = 'tnt/str/encoding.lua',
        ['tnt.str.regex'] = 'tnt/str/regex.lua',
        ['tnt.str.fluent'] = 'tnt/str/fluent.lua',
    },
}
