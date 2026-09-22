--- Тесты обвязки регулярных выражений: аргументы, порядок проверок, вид ответа.
---
--- Движок здесь — двойник из помощника пакета поверх шаблонов Lua с теми
--- же вызовами, что у `rex_pcre2`: проверяется обвязка, а не PCRE2. Сам
--- движок — кириллица, флаги, предел откатов — проверяется живым роком
--- в `regex_live_test.lua`.

local t = require('luatest')

local helper = dofile('test/helper.lua')

local g = t.group('tnt.str.regex')

---@return any
local function regex()
    return helper.part('tnt.str.regex')
end

g.after_each(function()
    regex()._set_source(nil)
end)

g.test_availability_is_the_presence_of_the_rock = function()
    local seen = helper.install_fake_regex(regex())

    t.assert_equals(regex().available(), true)
    t.assert_equals(seen.asked, 'rex_pcre2')

    helper.uninstall_regex(regex())
    t.assert_equals(regex().available(), false)
end

g.test_without_a_double_the_rock_comes_from_require = function()
    -- Настоящее подключение — `require`, и проверяется оно подстановкой
    -- модуля в package.loaded: так проверка не зависит от того, поставлен
    -- ли рок на машине, а пакет идёт своим путём, без подмены внешней зависимости.
    local seen = {}
    local remembered = package.loaded['rex_pcre2']

    package.loaded['rex_pcre2'] = helper.fake_regex_engine(seen)
    regex()._set_source(nil)

    local ok, answer = pcall(regex().is, 'a1', '%d')

    package.loaded['rex_pcre2'] = remembered

    t.assert_equals({ ok, answer }, { true, true })
    t.assert_equals(seen.pattern, '%d')
end

g.test_without_the_rock_the_action_falls_on_the_spot = function()
    -- Выражение пишет программист, и звать его на узле без движка —
    -- ошибка сборки узла, а не случай из жизни: исключение, а не пара.
    helper.uninstall_regex(regex())

    for _, name in ipairs({ 'is', 'match', 'match_all', 'split' }) do
        t.assert_error_msg_equals(
            'регулярные выражения недоступны: поставьте рок lrexlib-pcre2 (модуль rex_pcre2)',
            regex()[name],
            'Узел',
            'a'
        )
    end

    t.assert_error_msg_equals(
        'регулярные выражения недоступны: поставьте рок lrexlib-pcre2 (модуль rex_pcre2)',
        regex().replace,
        'Узел',
        'a',
        'b'
    )
end

g.test_the_expression_is_compiled_with_utf8_unicode_and_a_strict_end = function()
    local seen = helper.install_fake_regex(regex())

    regex().is('Узел', '^У')

    local flags = helper.FAKE_REGEX_FLAGS

    t.assert_equals(seen.pattern, '^У')
    t.assert_equals(seen.options, flags.UTF + flags.UCP + flags.DOLLAR_ENDONLY)
end

g.test_the_flags_are_asked_once_per_engine = function()
    -- `flags()` собирает таблицу на полторы сотни записей: спрашивать её
    -- на каждом вызове значит платить за неё на каждом вызове.
    local seen = helper.install_fake_regex(regex())

    regex().is('Узел', '^У')
    regex().is('Узел', '^З')

    t.assert_equals(seen.flags_asked, 1)
end

g.test_is_answers_whether_the_expression_matches = function()
    helper.install_fake_regex(regex())

    t.assert_equals(regex().is('storage-001', '%-%d+$'), true)
    t.assert_equals(regex().is('storage-abc', '%-%d+$'), false)
end

g.test_match_gives_captures_or_the_whole_match = function()
    helper.install_fake_regex(regex())

    t.assert_equals({ regex().match('storage-001', '%d+') }, { '001' })
    t.assert_equals({ regex().match('storage-001', '(%a+)%-(%d+)') }, { 'storage', '001' })
    t.assert_equals({ regex().match('storage', '%d+') }, {})
end

g.test_match_all_gives_what_gmatch_would_give_per_step = function()
    helper.install_fake_regex(regex())

    t.assert_equals(regex().match_all('a1b22c333', '%d+'), { '1', '22', '333' })
    t.assert_equals(regex().match_all('a1b22', '(%d+)'), { '1', '22' })
    t.assert_equals(regex().match_all('k=v;x=y', '(%w)=(%w)'), { { 'k', 'v' }, { 'x', 'y' } })
    t.assert_equals(regex().match_all('abc', '%d'), {})
end

g.test_replace_takes_a_template_a_function_or_a_table = function()
    helper.install_fake_regex(regex())

    t.assert_equals(regex().replace('a1b22', '(%d+)', '<%1>'), 'a<1>b<22>')
    t.assert_equals(
        regex().replace('a1b22', '%d+', function(found)
            return '#' .. #found
        end),
        'a#1b#2'
    )
    t.assert_equals(regex().replace('a1b22', '%d+', { ['1'] = 'one' }), 'aoneb22')
end

g.test_replace_answers_with_the_string_alone = function()
    -- `gsub` отдаёт ещё и число замен; цепочке оно ни к чему.
    helper.install_fake_regex(regex())

    t.assert_equals({ regex().replace('a1b22', '%d+', '#') }, { 'a#b#' })
end

g.test_replace_refuses_a_replacement_of_the_wrong_kind = function()
    helper.install_fake_regex(regex())

    t.assert_error_msg_equals(
        'замена: нужна строка, функция или таблица, а не number',
        regex().replace,
        'a1',
        '%d',
        7
    )
    t.assert_error_msg_equals(
        'замена: нужна строка, функция или таблица, а не nil',
        regex().replace,
        'a1',
        '%d'
    )
end

g.test_split_gives_one_piece_more_than_there_are_separators = function()
    helper.install_fake_regex(regex())

    t.assert_equals(regex().split('a, b ,c', '%s*,%s*'), { 'a', 'b', 'c' })
    t.assert_equals(regex().split('', ','), { '' })
    t.assert_equals(regex().split('a,', ','), { 'a', '' })
    t.assert_equals(regex().split('abc', ','), { 'abc' })
end

g.test_a_string_outside_utf8_is_refused_as_a_pair = function()
    -- Сверять байты со знаками нельзя, и такая строка — случай из жизни:
    -- отказ парой, как у `encode`.
    helper.install_fake_regex(regex())

    t.assert_equals({ regex().is('a\255b', 'b') }, { nil, 'байт 2 — не UTF-8' })
    t.assert_equals({ regex().match('a\255b', 'b') }, { nil, 'байт 2 — не UTF-8' })
    t.assert_equals({ regex().match_all('a\255b', 'b') }, { nil, 'байт 2 — не UTF-8' })
    t.assert_equals({ regex().replace('a\255b', 'b', 'c') }, { nil, 'байт 2 — не UTF-8' })
    t.assert_equals({ regex().split('a\255b', 'b') }, { nil, 'байт 2 — не UTF-8' })
end

g.test_a_bad_expression_falls_with_the_reason_from_the_engine = function()
    helper.install_fake_regex(regex())

    t.assert_error_msg_equals(
        "регулярное выражение «%» негодно: malformed pattern (ends with '%')",
        regex().is,
        'Узел',
        '%'
    )
end

g.test_a_bad_expression_is_found_before_the_string_is_looked_at = function()
    -- Негодное выражение — ошибка программиста независимо от строки:
    -- она роняет вызов и на строке не в UTF-8, а не прячется за отказом.
    helper.install_fake_regex(regex())

    t.assert_error_msg_equals(
        "регулярное выражение «%» негодно: malformed pattern (ends with '%')",
        regex().is,
        'a\255b',
        '%'
    )
end

g.test_the_engine_giving_up_on_a_string_names_the_expression = function()
    -- Так PCRE2 отказывает на выражении с вложенными повторами: это плохое
    -- выражение, а не плохая строка, и чинят его в коде.
    helper.install_fake_regex(regex(), 'error PCRE2_ERROR_MATCHLIMIT')

    local expected =
        'регулярное выражение «a» не справилось со строкой: error PCRE2_ERROR_MATCHLIMIT'

    t.assert_error_msg_equals(expected, regex().is, 'a', 'a')
    t.assert_error_msg_equals(expected, regex().match, 'a', 'a')
    t.assert_error_msg_equals(expected, regex().match_all, 'a', 'a')
    t.assert_error_msg_equals(expected, regex().replace, 'a', 'a', 'b')
    t.assert_error_msg_equals(expected, regex().split, 'a', 'a')
end

g.test_a_foreign_error_from_the_replacement_goes_through_as_it_is = function()
    helper.install_fake_regex(regex())

    t.assert_error_msg_equals('своя ошибка', regex().replace, 'a1', '%d', function()
        error('своя ошибка', 0)
    end)
end

g.test_a_wrong_argument_falls_before_the_engine_is_asked = function()
    -- Не строка вместо строки — ошибка программиста, и видна она обязана
    -- быть на любом узле, с роком и без.
    helper.uninstall_regex(regex())

    t.assert_error_msg_equals('значение: нужна строка, а не number', regex().is, 42, 'a')
    t.assert_error_msg_equals('выражение: нужна строка, а не nil', regex().is, 'Узел')
end

g.test_the_facade_and_the_chain_know_the_expressions = function()
    -- Фасад собирается заново: каждый файл проверок перезагружает исходники,
    -- и внешние зависимости, найденные у части, должны быть зависимостями этого же фасада.
    local str = helper.load()

    helper.install_fake_regex(regex())

    -- Проверка состава: действие, забытое в фасаде, работает во всех
    -- проверках своего модуля и не работает у того, кто подключил пакет.
    t.assert_equals(str.regex_available(), true)
    t.assert_equals(str.regex_is('storage-001', '%d+$'), true)
    t.assert_equals(str.regex_match('storage-001', '%d+'), '001')
    t.assert_equals(str.regex_match_all('a1b22', '%d+'), { '1', '22' })
    t.assert_equals(str.regex_replace('a1b22', '%d+', '#'), 'a#b#')
    t.assert_equals(str.regex_split('a,b', ','), { 'a', 'b' })

    t.assert_equals(str.of('a1b22'):regex_replace('%d+', '#'):upper():value(), 'A#B#')
    t.assert_equals(str.of('storage-001'):regex_match('%d+'):length(), 3)
    t.assert_equals(str.of('a1b22'):regex_match_all('%d+'), { '1', '22' })
    t.assert_equals(str.of('a1'):regex_is('%d'), true)
end
