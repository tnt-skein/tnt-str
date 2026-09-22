--- Тесты преобразования: адрес, маска, разбиение, число и признак.

local t = require('luatest')

local helper = dofile('test/helper.lua')

local g = t.group('tnt.str.convert')

---@return any
local function convert()
    return helper.part('tnt.str.convert')
end

g.test_slug_turns_a_russian_heading_into_an_address = function()
    -- Без транслитерации адрес из русского заголовка вышел бы пустым.
    t.assert_equals(convert().slug('Список Узлов'), 'spisok-uzlov')
    t.assert_equals(convert().slug('  Список,  узлов!  '), 'spisok-uzlov')
    t.assert_equals(convert().slug('storage-001'), 'storage-001')
    t.assert_equals(convert().slug('Список Узлов', '_'), 'spisok_uzlov')
end

g.test_slug_of_a_string_without_letters_is_empty = function()
    t.assert_equals(convert().slug('!!!'), '')
    t.assert_equals(convert().slug(''), '')
end

g.test_mask_hides_what_it_was_told_to = function()
    t.assert_equals(convert().mask('taylor@example.com', '*', 4), 'tay***************')
    t.assert_equals(convert().mask('taylor@example.com', '*', -15, 3), 'tay***@example.com')
    t.assert_equals(convert().mask('Узел', '*', 1), '****')
end

g.test_mask_counts_letters_from_one = function()
    -- Номер знака считается с единицы, как в `string.sub`, а не с нуля:
    -- пакет живёт в Lua.
    t.assert_equals(convert().mask('Узел', '*', 2, 2), 'У**л')
    t.assert_equals(convert().mask('Узел', '*', -2, 1), 'Уз*л')
    t.assert_equals(convert().mask('Узел', '*', 0, 1), '*зел')
    t.assert_equals(convert().mask('Узел', '*', 9, 1), 'Узел')
end

g.test_mask_of_nothing_is_a_programmer_error = function()
    t.assert_error_msg_equals(
        'длина: нужно число больше нуля, а не 0',
        convert().mask,
        'Узел',
        '*',
        2,
        0
    )
    t.assert_error_msg_equals('начало: нужно число, а не nil', convert().mask, 'Узел', '*')
end

g.test_mask_demands_whole_numbers = function()
    -- Дробный номер не указывает ни на какой знак: без проверки начало 2.5
    -- падало арифметикой внутри среза, а длина 1.5 — внутри `sub`.
    t.assert_error_msg_equals(
        'начало: нужно целое число, а не 2.5',
        convert().mask,
        'abcdef',
        '*',
        2.5
    )
    t.assert_error_msg_equals(
        'длина: нужно целое число, а не 1.5',
        convert().mask,
        'abcdef',
        '*',
        2,
        1.5
    )
end

g.test_chunks_are_counted_in_letters = function()
    t.assert_equals(convert().chunk('Узелок', 2), { 'Уз', 'ел', 'ок' })
    t.assert_equals(convert().chunk('Узел', 3), { 'Узе', 'л' })
    t.assert_equals(convert().chunk('', 3), {})
    t.assert_error_msg_equals(
        'размер куска: нужно число больше нуля, а не 0',
        convert().chunk,
        'Узел',
        0
    )
end

g.test_a_fractional_chunk_size_is_refused = function()
    -- Размер 2.5 ни разу не совпадал с числом набранных знаков, и строка
    -- молча уходила одним куском.
    t.assert_error_msg_equals(
        'размер куска: нужно целое число, а не 2.5',
        convert().chunk,
        'abcdef',
        2.5
    )
end

g.test_split_takes_the_separator_literally = function()
    -- Разделители в настройках пишут люди, и точка в них означает точку,
    -- а не «любой знак».
    t.assert_equals(convert().split('a.b.c', '.'), { 'a', 'b', 'c' })
    t.assert_equals(convert().split('axbxc', '.'), { 'axbxc' })
    t.assert_equals(convert().split('a,,b', ','), { 'a', '', 'b' })
    t.assert_equals(convert().split('Уз', ''), { 'У', 'з' })
end

g.test_split_can_be_limited_and_keeps_the_rest_whole = function()
    t.assert_equals(convert().split('a,b,c', ',', 2), { 'a', 'b,c' })
    t.assert_equals(convert().split('a,b,c', ',', 1), { 'a,b,c' })
    t.assert_equals(convert().split('a,b,c', ',', 9), { 'a', 'b', 'c' })
end

g.test_split_into_letters_keeps_the_limit_too = function()
    -- Пустой разделитель режет по знакам, и предел значит то же, что
    -- с любым другим: последний кусок забирает всё прочее.
    t.assert_equals(convert().split('Узел', '', 2), { 'У', 'зел' })
    t.assert_equals(convert().split('Узел', '', 1), { 'Узел' })
    t.assert_equals(convert().split('Узел', '', 4), { 'У', 'з', 'е', 'л' })
    t.assert_equals(convert().split('Уз', '', 5), { 'У', 'з' })
    t.assert_equals(convert().split('', '', 2), {})
end

g.test_the_split_limit_is_a_count_of_pieces = function()
    -- Без проверки строка падала сравнением внутри пакета, дробь молча
    -- округлялась вверх, а ноль давал один кусок.
    t.assert_error_msg_equals(
        'число кусков: нужно целое число, а не 2.5',
        convert().split,
        'a,b,c',
        ',',
        2.5
    )
    t.assert_error_msg_equals(
        'число кусков: нужно число больше нуля, а не 0',
        convert().split,
        'a,b,c',
        ',',
        0
    )
    t.assert_error_msg_equals(
        'число кусков: нужно число, а не string',
        convert().split,
        'a,b,c',
        ',',
        '2'
    )
    t.assert_error_msg_equals(
        'число кусков: нужно целое число, а не 1.5',
        convert().split,
        'Уз',
        '',
        1.5
    )
end

g.test_lines_understand_all_three_kinds_of_break = function()
    t.assert_equals(convert().lines('a\r\nb\rc\nd'), { 'a', 'b', 'c', 'd' })
    t.assert_equals(convert().lines(''), { '' })
end

g.test_a_number_comes_out_of_a_string_or_a_reason_does = function()
    t.assert_equals(convert().to_number(' 12 '), 12)
    t.assert_equals(convert().to_number('-1.5'), -1.5)
    t.assert_equals(convert().to_number('12' .. helper.NBSP), 12)
    t.assert_equals(
        { convert().to_number('двенадцать') },
        { nil, '«двенадцать» — не число' }
    )
end

g.test_a_flag_comes_out_of_a_word_or_a_reason_does = function()
    -- Слова перечислены все до одного: выпавшее из списка становится
    -- отказом, и настройка, которая вчера работала, сегодня не читается.
    for _, word in ipairs({ '1', 'true', 'on', 'yes', 'да', ' TRUE ', 'Да' }) do
        t.assert_equals(convert().to_boolean(word), true, word)
    end

    for _, word in ipairs({ '', '0', 'false', 'off', 'no', 'нет', 'НЕТ' }) do
        t.assert_equals(convert().to_boolean(word), false, word)
    end
end

g.test_an_unknown_word_is_a_refusal_and_not_a_lie = function()
    -- Настройка «ага», молча ставшая ложью, — это беда, которую надо
    -- показать человеку, а не проглотить.
    t.assert_equals({ convert().to_boolean('ага') }, { nil, '«ага» — не «да» и не «нет»' })
end

g.test_length_counts_letters_and_width_counts_cells = function()
    t.assert_equals(convert().length('Узел'), 4)
    t.assert_equals(convert().width('Узел'), 4)
    t.assert_equals(convert().width('日本'), 4)
end

g.test_position_answers_in_letters_not_bytes = function()
    -- Номер 5 там, где знаков четыре, не годится ни для среза,
    -- ни для показа человеку.
    t.assert_equals(convert().position('Узел', 'е'), 3)
    t.assert_equals(convert().position('Узел', 'У'), 1)
    t.assert_equals(convert().position('Узел', 'нет'), nil)
end

g.test_position_can_start_from_a_given_letter = function()
    t.assert_equals(convert().position('узелузел', 'зе'), 2)
    t.assert_equals(convert().position('узелузел', 'зе', 3), 6)
    t.assert_equals(convert().position('узелузел', 'зе', 7), nil)
end

g.test_position_counts_its_start_like_mask = function()
    -- Отрицательное начало — с конца, ноль и всё, что левее строки, —
    -- первый знак: так читает начало и `string.sub`. Ноль прежде отрезал
    -- всю строку, и поиск не находил ничего.
    t.assert_equals(convert().position('узелузел', 'у', -4), 5)
    t.assert_equals(convert().position('узелузел', 'зе', 0), 2)
    t.assert_equals(convert().position('узелузел', 'зе', -100), 2)
    t.assert_equals(convert().position('узелузел', 'у', 1), 1)
end

g.test_position_demands_a_whole_start = function()
    t.assert_error_msg_equals(
        'начало поиска: нужно целое число, а не 2.5',
        convert().position,
        'abcabc',
        'b',
        2.5
    )
    t.assert_error_msg_equals(
        'начало поиска: нужно число, а не string',
        convert().position,
        'abcabc',
        'b',
        '2'
    )
end
