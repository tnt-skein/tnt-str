--- Тесты знаков: обход, срез, переворот, ширина и поиск по байтам.

local t = require('luatest')

local helper = dofile('test/helper.lua')

local g = t.group('tnt.str.chars')

---@return any
local function chars()
    return helper.part('tnt.str.chars')
end

--- Знаки строки списком: так проверять обход нагляднее, чем итератором.
---@param text string
---@return string[]
local function pieces_of(text)
    local list = {}

    for _, piece in ipairs(chars().pieces(text)) do
        table.insert(list, piece.text)
    end

    return list
end

g.test_walk_gives_byte_bounds_of_every_letter = function()
    local bounds = {}

    for from, to, code in chars().walk('Уз') do
        table.insert(bounds, { from, to, code })
    end

    -- Кириллическая буква — два байта: границы обязаны это учитывать,
    -- иначе срез по ним разрубит её пополам.
    t.assert_equals(bounds, { { 1, 2, 0x0423 }, { 3, 4, 0x0437 } })
end

g.test_walk_does_not_lose_a_broken_byte = function()
    -- utf8.next на негодной последовательности возвращает nil и посреди
    -- строки: обход по нему потерял бы весь остаток.
    local bounds = {}

    for from, to, code in chars().walk('\255a') do
        table.insert(bounds, { from, to, code })
    end

    t.assert_equals(bounds, { { 1, 1, nil }, { 2, 2, 0x61 } })
end

g.test_length_counts_letters_not_bytes = function()
    t.assert_equals(chars().len('Узел'), 4)
    t.assert_equals(chars().len('node'), 4)
    t.assert_equals(chars().len(''), 0)
    t.assert_equals(chars().len('\255\254'), 2)
end

g.test_offsets_end_with_the_place_past_the_string = function()
    -- Последнее смещение нужно срезу: без него конец последнего знака
    -- пришлось бы считать отдельно.
    t.assert_equals(chars().offsets('Уз'), { 1, 3, 5 })
    t.assert_equals(chars().offsets(''), { 1 })
end

g.test_pieces_carry_the_letter_and_its_code = function()
    t.assert_equals(chars().pieces('a\255'), {
        { text = 'a', code = 0x61 },
        { text = '\255' },
    })
end

g.test_negative_index_counts_from_the_end = function()
    t.assert_equals(chars().absolute(2, 4), 2)
    t.assert_equals(chars().absolute(-1, 4), 4)
    t.assert_equals(chars().absolute(-4, 4), 1)
    t.assert_equals(chars().absolute(0, 4), 0)
end

g.test_slice_counts_letters = function()
    t.assert_equals(chars().sub('Кластер', 1, 3), 'Кла')
    t.assert_equals(chars().sub('Кластер', 2, 3), 'ла')
    t.assert_equals(chars().sub('Кластер', 3, 3), 'а')
    t.assert_equals(chars().sub('Кластер', 5), 'тер')
    t.assert_equals(chars().sub('Кластер'), 'Кластер')
end

g.test_slice_takes_negative_bounds_and_clamps_the_rest = function()
    t.assert_equals(chars().sub('Кластер', -3), 'тер')
    t.assert_equals(chars().sub('Кластер', -3, -2), 'те')
    t.assert_equals(chars().sub('Кластер', 0, 2), 'Кл')
    t.assert_equals(chars().sub('Кластер', -99, 2), 'Кл')
    t.assert_equals(chars().sub('Кластер', 2, 99), 'ластер')
    t.assert_equals(chars().sub('Кластер', 5, 2), '')
    t.assert_equals(chars().sub('', 1, 3), '')
end

g.test_the_beginning_of_a_string_is_taken_by_count = function()
    t.assert_equals(chars().first('Кластер', 3), 'Кла')
    t.assert_equals(chars().first('Кластер', 99), 'Кластер')
    t.assert_equals(chars().first('Кластер', 0), '')
end

g.test_bytes_before_an_offset_are_taken_as_they_are = function()
    -- Смещение приходит от поиска, который ищет байтами.
    t.assert_equals(chars().before_offset('Кластер', 5), 'Кл')
    t.assert_equals(chars().before_offset('Кластер', 1), '')
    t.assert_equals(chars().before_offset('Кластер', 4), 'К\208')
end

g.test_single_letter_is_taken_by_number = function()
    t.assert_equals(chars().at('Узел', 1), 'У')
    t.assert_equals(chars().at('Узел', -1), 'л')
    t.assert_equals(chars().at('Узел', 9), '')
end

g.test_byte_offset_turns_into_a_letter_number = function()
    -- Поиск идёт байтами, а отвечать надо знаками.
    t.assert_equals(chars().index_of('Узел', 1), 1)
    t.assert_equals(chars().index_of('Узел', 5), 3)
    t.assert_equals(chars().index_of('Узел', 9), 5)
end

g.test_offset_inside_a_letter_belongs_to_the_next_one = function()
    -- Внутрь знака смещение попадает только в битой строке; ответ
    -- «ближайший следующий» там лучше отказа.
    t.assert_equals(chars().index_of('Узел', 4), 3)
end

g.test_reverse_keeps_letters_whole = function()
    t.assert_equals(chars().reverse('Узел'), 'лезУ')
    t.assert_equals(chars().reverse(''), '')
    t.assert_equals(chars().reverse('Уз\255'), '\255зУ')
end

g.test_space_includes_the_non_breaking_one = function()
    -- Перечислены все до одного: пробельный знак, выпавший из списка,
    -- остаётся в строке после обрезки и находится потом дорого.
    local spaces = {
        0x09,
        0x0A,
        0x0B,
        0x0C,
        0x0D,
        0x20,
        0x85,
        0xA0,
        0x1680,
        0x2000,
        0x2005,
        0x200A,
        0x2028,
        0x2029,
        0x202F,
        0x205F,
        0x3000,
        0xFEFF,
    }

    for _, code in ipairs(spaces) do
        t.assert_equals(chars().is_space(code), true, ('%04X'):format(code))
    end

    t.assert_equals(chars().is_space(0x0423), false)
    t.assert_equals(chars().is_space(0x200B), false)
    t.assert_equals(chars().is_space(nil), false)
end

g.test_width_counts_cells_not_letters = function()
    -- Знак не равен ячейке: иероглиф занимает две, диакритика — ноль.
    t.assert_equals(chars().width('Узел'), 4)
    t.assert_equals(chars().width('日本'), 4)
    t.assert_equals(chars().width('e\204\129'), 1)
    t.assert_equals(chars().width(''), 0)
end

g.test_width_of_a_letter_knows_the_edges_of_the_ranges = function()
    -- Границы отрезков проверяются с обеих сторон: иначе сдвиг границы
    -- на единицу остаётся незамеченным.
    t.assert_equals(chars().width_of(0x1100), 2)
    t.assert_equals(chars().width_of(0x115F), 2)
    t.assert_equals(chars().width_of(0x10FF), 1)
    t.assert_equals(chars().width_of(0x1160), 1)
    t.assert_equals(chars().width_of(0x4E01), 2)
    t.assert_equals(chars().width_of(0x0300), 0)
    t.assert_equals(chars().width_of(0x036F), 0)
    t.assert_equals(chars().width_of(0x02FF), 1)
    t.assert_equals(chars().width_of(0x0370), 1)
    t.assert_equals(chars().width_of(nil), 1)
end

g.test_search_finds_the_first_occurrence = function()
    t.assert_equals(chars().locate('абаб', 'аб'), 1)
    t.assert_equals(chars().locate('абаб', 'аб', false), 1)
    t.assert_equals(chars().locate('абаб', 'б'), 3)
end

g.test_search_takes_the_substring_literally = function()
    -- Искомое приходит из настроек и от человека: точка в нём означает
    -- точку, а не «любой знак».
    t.assert_equals(chars().locate('a.b', '.'), 2)
    t.assert_equals(chars().locate('a.b.c', '.', true), 4)
end

g.test_search_finds_the_last_occurrence_when_asked = function()
    t.assert_equals(chars().locate('абаб', 'аб', true), 5)
    t.assert_equals(chars().locate('аб', 'аб', true), 1)
end

g.test_the_last_occurrence_may_overlap_the_one_before_it = function()
    -- «aa» в «aaa» встречается дважды, и второе вхождение начинается
    -- внутри первого: шаг через всё найденное его бы пропустил.
    t.assert_equals(chars().locate('aaa', 'aa', true), 2)
end

g.test_search_answers_nothing_for_a_missing_or_empty_needle = function()
    -- Пустая подстрока находится в любом месте, и всё, что на этом
    -- построено, начинает вести себя необъяснимо.
    t.assert_equals(chars().locate('Узел', ''), nil)
    t.assert_equals(chars().locate('Узел', '', true), nil)
    t.assert_equals(chars().locate('Узел', 'нет'), nil)
    t.assert_equals(chars().locate('Узел', 'нет', true), nil)
end

g.test_pieces_of_a_broken_string_keep_every_byte = function()
    t.assert_equals(pieces_of('Уз\255ел'), { 'У', 'з', '\255', 'е', 'л' })
end
