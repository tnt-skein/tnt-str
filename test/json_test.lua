--- Тесты проверки формы JSON: что считается JSON, а что нет.

local t = require('luatest')

local helper = dofile('test/helper.lua')

local g = t.group('tnt.str.json')

---@return any
local function json()
    return helper.part('tnt.str.json')
end

--- Утверждение «это JSON» списком: проверок тут много, и каждая — строка.
---@param expected boolean
---@param samples string[]
local function all_are(expected, samples)
    for _, sample in ipairs(samples) do
        t.assert_equals(json().valid(sample), expected, sample)
    end
end

g.test_values_of_every_kind_are_json = function()
    all_are(true, { '{}', '[]', '"узел"', 'true', 'false', 'null', '0', '-0', '12', '-12' })
end

g.test_numbers_follow_the_rfc = function()
    all_are(true, { '1.5', '-1.5', '1e3', '1E+3', '1.5e-3', '0.5' })
end

g.test_a_number_of_another_kind_is_not_json = function()
    -- cjson принял бы и `nan`, и `inf`: «похоже на JSON» и «разбирается
    -- нашим разбором» — разные утверждения.
    all_are(false, { '01', '+1', '.5', '1.', 'nan', 'inf', '0x10', '-', '1e', '1e+' })
end

g.test_structures_nest = function()
    all_are(true, {
        '{"а": [1, 2, {"б": null}]}',
        '[[[]]]',
        ' \t\n\r {"а" : 1 , "б" : [ ] } \n',
    })
end

g.test_structures_without_a_single_space_are_json_too = function()
    -- Тело запроса приходит без пробелов чаще, чем с ними.
    all_are(true, { '[1,2]', '{"a":1,"b":2}', '[[1],[2]]' })
end

g.test_strings_take_escapes = function()
    all_are(true, {
        '"\\""',
        '"\\\\"',
        '"\\/"',
        '"\\b\\f\\n\\r\\t"',
        '"\\u0423зел"',
        '"\\uFFFF"',
        -- Escape не в начале строки: длина пропущенного считается от него
        -- самого, а не от кавычки.
        '"x\\u0041y"',
    })
end

g.test_a_string_is_read_letter_by_letter = function()
    -- Шаг через байт проскочил бы закрывающую кавычку на теле нечётной
    -- длины, а пробел внутри строки — это не управляющий знак.
    all_are(true, { '"a"', '"abc"', '"a b"', '" "', '""' })
end

g.test_a_broken_string_is_not_json = function()
    all_are(false, {
        '"без конца',
        '"\\x"',
        '"\\u12"',
        '"\\u12g4"',
        '"перевод\nстроки"',
        "'одинарные'",
    })
end

g.test_a_broken_structure_is_not_json = function()
    all_are(false, {
        '[1,]',
        '{"а": 1,}',
        '{"а" 1}',
        '{а: 1}',
        '{"а": }',
        '[1 2]',
        '[1',
        '{',
        '[1] лишнее',
        '',
        '   ',
    })
end

g.test_nesting_has_an_end = function()
    -- Без предела строка вида «[[[[[…» кладёт стек интерпретатора вместо
    -- того, чтобы получить ответ «не JSON». Предел считается по значениям:
    -- сама единица в середине — тоже уровень, поэтому скобок на одну меньше.
    t.assert_equals(json().valid(('['):rep(63) .. '1' .. (']'):rep(63)), true)
    t.assert_equals(json().valid(('['):rep(64) .. '1' .. (']'):rep(64)), false)
end

g.test_nesting_of_objects_has_the_same_end = function()
    t.assert_equals(json().valid(('{"a":'):rep(63) .. '1' .. ('}'):rep(63)), true)
    t.assert_equals(json().valid(('{"a":'):rep(64) .. '1' .. ('}'):rep(64)), false)
end

g.test_an_empty_structure_costs_one_level_less = function()
    -- Пустому списку значения не нужны, и последний уровень остаётся
    -- незанятым: предел считается по разбираемым значениям, а не по скобкам.
    t.assert_equals(json().valid(('['):rep(64) .. (']'):rep(64)), true)
    t.assert_equals(json().valid(('['):rep(65) .. (']'):rep(65)), false)
end
