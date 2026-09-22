--- Живые проверки регулярных выражений: настоящий `rex_pcre2`.
---
--- Двойник в `regex_test.lua` показывает, что обвязка разговаривает
--- с движком правильно; здесь — что сам движок на 3.8 отвечает так, как
--- обещает документ: видит знаки, а не байты, знает кириллицу, держит
--- строгий `$` и отказывает на выражении с вложенными повторами за доли
--- секунды, а не вешает узел. Без рока проверки пропускаются.

local clock = require('clock')
local t = require('luatest')

local helper = dofile('test/helper.lua')

local g = t.group('tnt.str.regex.live')

---@return any
local function regex()
    return helper.part('tnt.str.regex')
end

g.before_all(function()
    t.skip_if(not regex().available(), 'рок lrexlib-pcre2 не поставлен: make deps-regex')
end)

g.test_the_expression_sees_letters_not_bytes = function()
    -- «Узел» — восемь байтов и четыре знака: точка считает знаки.
    t.assert_equals(regex().is('Узел', '^.{4}$'), true)
    t.assert_equals(regex().is('Узел', '^.{8}$'), false)
    t.assert_equals(regex().replace('Узел', '.', '*'), '****')
end

g.test_the_classes_and_the_case_know_cyrillic = function()
    t.assert_equals(regex().is('Узел', '^\\w+$'), true)
    t.assert_equals(regex().is('ж', '^\\p{Cyrillic}$'), true)
    t.assert_equals(regex().is('УЗЕЛ', '(?i)^узел$'), true)
    t.assert_equals(regex().is('ЁЖ', '(?i)^ёж$'), true)
    t.assert_equals(regex().is('УЗЕЛ', '^узел$'), false)
end

g.test_the_end_of_the_string_is_strict_unless_asked_otherwise = function()
    -- В Perl `$` совпадает и перед последним переводом строки, и правило
    -- `^\d+$` пропустило бы «12\n»; здесь — нет. `(?m)` — просили сами.
    t.assert_equals(regex().is('12\n', '^\\d+$'), false)
    t.assert_equals(regex().is('12', '^\\d+$'), true)
    t.assert_equals(regex().is('a\nb', '(?m)^a$'), true)
end

g.test_what_lua_patterns_cannot_say_is_said_in_one_line = function()
    local uuid = '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'

    t.assert_equals(regex().is('5f8a1c2e-3b4d-4e5f-8a9b-0c1d2e3f4a5b', uuid), true)
    t.assert_equals(regex().is('5f8a1c2e-3b4d-4e5f-8a9b-0c1d2e3f4a5', uuid), false)
    t.assert_equals(regex().match('storage-001', '^(?:storage|router)-(\\d+)$'), '001')
    t.assert_equals(regex().match_all('k=v;x=y', '(\\w)=(\\w)'), { { 'k', 'v' }, { 'x', 'y' } })
    t.assert_equals(regex().split('a, b ,c', '\\s*,\\s*'), { 'a', 'b', 'c' })
    t.assert_equals(regex().replace('a1b22', '(\\d+)', '<%1>'), 'a<1>b<22>')
end

g.test_a_capture_outside_the_match_is_false = function()
    t.assert_equals({ regex().match('x', '(y)?(x)') }, { false, 'x' })
end

g.test_a_bad_expression_falls_with_the_place_named = function()
    t.assert_error_msg_equals(
        'регулярное выражение «(» негодно: missing closing parenthesis (pattern offset: 2)',
        regex().is,
        'Узел',
        '('
    )
end

g.test_nested_repeats_hit_the_limit_in_a_moment_instead_of_hanging = function()
    -- Проверено на 3.8: `(a+)+$` на тридцати знаках упирается в предел
    -- PCRE2 в десять миллионов шагов за доли секунды. Срок здесь — чтобы
    -- поломка предела была видна как поломка, а не как повисший прогон.
    -- Меряется время процессора своего потока, а не стены: движок считает
    -- в нём же, а стену растягивают соседние прогоны — в полном прогоне
    -- рядом с чужими три вызова заняли по ней больше двух секунд.
    local subject = ('a'):rep(30) .. 'b'
    local expected =
        'регулярное выражение «(a+)+$» не справилось со строкой: error PCRE2_ERROR_MATCHLIMIT'
    local started = clock.thread()

    t.assert_error_msg_equals(expected, regex().is, subject, '(a+)+$')
    t.assert_error_msg_equals(expected, regex().match_all, subject, '(a+)+$')
    t.assert_error_msg_equals(expected, regex().split, subject, '(a+)+$')
    t.assert_lt(clock.thread() - started, 2)
end
