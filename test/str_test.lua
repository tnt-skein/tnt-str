--- Тесты фасада и цепочки: то, ради чего пакет и делался.

local t = require('luatest')

local helper = dofile('test/helper.lua')

local g = t.group('tnt.str')

local str = helper.str

g.test_the_facade_gives_every_group_at_hand = function()
    -- Проверка не столько поведения, сколько состава: действие, забытое
    -- в фасаде, работает во всех проверках своего модуля и не работает
    -- у того, кто подключил пакет.
    t.assert_equals(str.upper('узел'), 'УЗЕЛ')
    t.assert_equals(str.kebab('СписокУзлов'), 'список-узлов')
    t.assert_equals(str.headline('список_узлов'), 'Список Узлов')
    t.assert_equals(str.limit('Список узлов', 6), 'Список…')
    t.assert_equals(str.after_last('a/b/c', '/'), 'c')
    t.assert_equals(str.contains('Список узлов', 'узл'), true)
    t.assert_equals(str.is_uuid('5f8a1c2e-3b4d-4e5f-8a9b-0c1d2e3f4a5b'), true)
    t.assert_equals(str.squish('  Список   узлов '), 'Список узлов')
    t.assert_equals(str.pad_left('1', 3, '0'), '001')
    t.assert_equals(str.slug('Список Узлов'), 'spisok-uzlov')
    t.assert_equals(str.plural(5, helper.FORMS), 'узлов')
    t.assert_equals(str.counted(2, helper.FORMS), '2 узла')
    t.assert_equals(str.width('日本'), 4)
    t.assert_equals(str.words_of('списокУзлов'), { 'список', 'Узлов' })
end

g.test_ascii_is_the_transliteration_under_a_familiar_name = function()
    t.assert_equals(str.ascii, str.transliterate)
    t.assert_equals(str.ascii('Ёжик'), 'Yozhik')
end

g.test_the_chain_reads_in_the_order_it_runs = function()
    t.assert_equals(str.of('  Список Узлов '):trim():slug():value(), 'spisok-uzlov')
    t.assert_equals(str.of('узел'):upper():value(), 'УЗЕЛ')
end

g.test_the_chain_ends_where_the_answer_is_not_a_string = function()
    t.assert_equals(str.of('Узел'):length(), 4)
    t.assert_equals(str.of('Список узлов'):contains('узл'), true)
    t.assert_equals(str.of('a,b'):split(','), { 'a', 'b' })
end

g.test_a_refusal_comes_out_of_the_chain_as_a_pair = function()
    t.assert_equals(
        { str.of('двенадцать'):to_number() },
        { nil, '«двенадцать» — не число' }
    )
    t.assert_equals(str.of(' 12 '):to_number(), 12)
end

g.test_the_chain_turns_into_a_string_where_a_string_is_expected = function()
    t.assert_equals(tostring(str.of('Узел')), 'Узел')
    t.assert_equals(str.of('Узел') .. '!', 'Узел!')
    t.assert_equals('!' .. str.of('Узел'), '!Узел')
    t.assert_equals(('%s'):format(tostring(str.of('Узел'))), 'Узел')
end

g.test_two_chains_are_equal_when_their_strings_are = function()
    t.assert_equals(str.of('Узел') == str.of('Узел'), true)
    t.assert_equals(str.of('Узел') == str.of('Диск'), false)
end

g.test_the_length_of_a_chain_is_counted_in_letters = function()
    -- `#` до метаметода не доходит: LuaJIT зовёт `__len` только
    -- для userdata, а для таблицы молча берёт длину массивной части.
    -- Сам метаметод верен, и там, где его зовут, ответ правильный.
    local chain = str.of('Узел')

    t.assert_equals(getmetatable(chain).__len(chain), 4)
    t.assert_equals(#chain, 0)
end

g.test_a_typo_in_the_name_falls_on_the_spot = function()
    -- Тихий nil уехал бы дальше и всплыл через три слоя в виде
    -- «attempt to index a nil value».
    t.assert_error_msg_equals('у строки нет такого действия: trimm', function()
        return str.of('Узел'):trimm()
    end)
end

g.test_the_chain_starts_from_a_string_only = function()
    t.assert_error_msg_equals('значение: нужна строка, а не number', str.of, 42)
end

g.test_every_action_of_the_facade_is_an_action_of_the_chain = function()
    -- Обёртка получает список действий при сборке: разойтись фасаду
    -- и цепочке негде, и эта проверка сторожит именно сборку.
    local chain = str.of('Узел')

    for name, action in pairs(str) do
        if name ~= 'of' then
            t.assert_equals(type(action), 'function', name)
            t.assert_equals(type(chain[name]), 'function', name)
        end
    end
end
