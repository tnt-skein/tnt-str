--- Тесты правки: обрезка, схлопывание, дополнение, замена, перенос.

local t = require('luatest')

local helper = dofile('test/helper.lua')

local g = t.group('tnt.str.edit')

---@return any
local function edit()
    return helper.part('tnt.str.edit')
end

g.test_trim_takes_the_non_breaking_space_too = function()
    -- Шаблон `%s` неразрывного пробела не видит: в UTF-8 это два байта,
    -- и ни один из них не пробельный. Хвост остаётся, сравнение не сходится.
    t.assert_equals(edit().trim('  Узел' .. helper.NBSP .. ' '), 'Узел')
    t.assert_equals(edit().trim(helper.NBSP .. 'Узел'), 'Узел')
end

g.test_trim_works_on_one_side_when_asked = function()
    t.assert_equals(edit().ltrim('  Узел  '), 'Узел  ')
    t.assert_equals(edit().rtrim('  Узел  '), '  Узел')
    t.assert_equals(edit().ltrim('   '), '')
    t.assert_equals(edit().rtrim('   '), '')
end

g.test_trim_of_nothing_but_spaces_leaves_nothing = function()
    t.assert_equals(edit().trim('   '), '')
    t.assert_equals(edit().trim(' '), '')
    t.assert_equals(edit().trim(''), '')
end

g.test_trim_by_its_own_list_counts_letters_not_bytes = function()
    -- Список «…» — это один знак, а не три байта, каждый из которых
    -- снимали бы поодиночке.
    t.assert_equals(edit().trim('…Узел…', '…'), 'Узел')
    t.assert_equals(edit().trim('//узел//', '/'), 'узел')
    t.assert_equals(edit().ltrim('  Узел', '/'), '  Узел')
end

g.test_squish_collapses_the_spaces_inside_too = function()
    t.assert_equals(edit().squish('   Список    узлов   '), 'Список узлов')
    t.assert_equals(
        edit().squish('Список' .. helper.NBSP .. helper.NBSP .. 'узлов'),
        'Список узлов'
    )
    t.assert_equals(edit().squish('   '), '')
    -- Слово в одну букву — тоже слово, и в конце строки тоже.
    t.assert_equals(edit().squish(' а  б '), 'а б')
    t.assert_equals(edit().squish(' а  б'), 'а б')
end

g.test_padding_fills_up_to_the_width = function()
    t.assert_equals(edit().pad_left('Узел', 8, '.'), '....Узел')
    t.assert_equals(edit().pad_right('Узел', 8, '.'), 'Узел....')
    t.assert_equals(edit().pad_left('Узел', 6), '  Узел')
    t.assert_equals(edit().pad_both('James', 10, '_'), '__James___')
end

g.test_padding_does_nothing_when_the_string_is_already_wide_enough = function()
    t.assert_equals(edit().pad_left('Узел', 4, '.'), 'Узел')
    t.assert_equals(edit().pad_right('Узел', 2, '.'), 'Узел')
end

g.test_a_long_filler_is_cut_by_letters = function()
    t.assert_equals(edit().pad_left('x', 5, 'аб'), 'абабx')
    t.assert_equals(edit().pad_right('x', 4, 'аб'), 'xаба')
end

g.test_a_filler_of_two_cells_does_not_overrun_the_width = function()
    -- Знак в две ячейки не делится: недобор в одну ячейку остаётся,
    -- а вот перебор испортил бы весь столбец.
    t.assert_equals(edit().pad_left('a', 4, '日'), '日a')
    t.assert_equals(edit().pad_left('a', 5, '日'), '日日a')
end

g.test_a_filler_of_no_width_is_a_programmer_error = function()
    -- Иначе ширина набиралась бы вечно.
    t.assert_error_msg_equals(
        'заполнитель: нужно число больше нуля, а не 0',
        edit().pad_left,
        'Узел',
        8,
        '\204\129'
    )
end

g.test_repeat_and_reverse = function()
    t.assert_equals(edit().repeat_times('уз', 3), 'узузуз')
    t.assert_equals(edit().repeat_times('уз', 0), '')
    t.assert_equals(edit().reverse('Узел'), 'лезУ')
end

g.test_an_endless_count_or_width_is_a_programmer_error = function()
    -- До `rep` бесконечность не доходит: там она кончалась, смотря
    -- по сборке, нехваткой памяти или молча пустой строкой.
    t.assert_error_msg_equals(
        'число повторов: нужно конечное число, а не inf',
        edit().repeat_times,
        'уз',
        math.huge
    )
    t.assert_error_msg_equals(
        'ширина: нужно конечное число, а не inf',
        edit().pad_left,
        'Узел',
        1 / 0
    )
    t.assert_error_msg_equals(
        'ширина: нужно конечное число, а не inf',
        edit().pad_both,
        'Узел',
        1 / 0
    )
    t.assert_error_msg_equals(
        'ширина: нужно конечное число, а не NaN',
        edit().pad_right,
        'Узел',
        0 / 0
    )
end

g.test_replace_changes_every_occurrence = function()
    t.assert_equals(edit().replace('a?b?c', '?', '!'), 'a!b!c')
    -- Искомое берётся дословно: точка заменяет точку, а не любой знак.
    t.assert_equals(edit().replace('a.b.c', '.', '!'), 'a!b!c')
    t.assert_equals(edit().replace('Узел', 'нет', '!'), 'Узел')
    t.assert_equals(edit().replace('a?b', { '?', 'b' }, '!'), 'a!!')
end

g.test_replace_of_nothing_changes_nothing = function()
    -- Пустая подстрока есть между любыми двумя знаками: замена по ней
    -- превратила бы строку в кашу из замен.
    t.assert_equals(edit().replace('Узел', '', '!'), 'Узел')
end

g.test_replace_can_be_limited_to_the_first_or_the_last = function()
    t.assert_equals(edit().replace_first('a?b?c', '?', '!'), 'a!b?c')
    t.assert_equals(edit().replace_last('a?b?c', '?', '!'), 'a?b!c')
    t.assert_equals(edit().replace_first('Узел', 'нет', '!'), 'Узел')
    t.assert_equals(edit().replace_last('Узел', 'нет', '!'), 'Узел')
end

g.test_replace_by_list_fills_the_places_in_order = function()
    t.assert_equals(edit().replace_array('между ? и ?', '?', { '8:30', '9:00' }), 'между 8:30 и 9:00')
end

g.test_replace_by_list_leaves_the_rest_when_the_list_runs_out = function()
    t.assert_equals(edit().replace_array('? и ? и ?', '?', { 'а', 'б' }), 'а и б и ?')
    t.assert_equals(edit().replace_array('? и ?', '?', {}), '? и ?')
end

g.test_remove_throws_the_substring_out = function()
    t.assert_equals(edit().remove('Список узлов', ' узлов'), 'Список')
    t.assert_equals(edit().remove('a-b-c', { '-', 'b' }), 'ac')
end

g.test_wrap_and_unwrap = function()
    t.assert_equals(edit().wrap('Узел', '"'), '"Узел"')
    t.assert_equals(edit().wrap('Узел', '<i>', '</i>'), '<i>Узел</i>')
    t.assert_equals(edit().unwrap('"Узел"', '"'), 'Узел')
    t.assert_equals(edit().unwrap('<i>Узел</i>', '<i>', '</i>'), 'Узел')
end

g.test_unwrap_leaves_a_string_wrapped_on_one_side_only = function()
    t.assert_equals(edit().unwrap('"Узел', '"'), '"Узел')
    t.assert_equals(edit().unwrap('Узел', '"'), 'Узел')
end

g.test_start_and_finish_add_what_is_missing = function()
    t.assert_equals(edit().start('узел', '/'), '/узел')
    t.assert_equals(edit().start('/узел', '/'), '/узел')
    t.assert_equals(edit().finish('/узел', '/'), '/узел/')
    t.assert_equals(edit().finish('/узел/', '/'), '/узел/')
    t.assert_equals(edit().finish('', '/'), '/')
end

g.test_occurrences_are_counted_without_overlap = function()
    t.assert_equals(edit().substr_count('abcabc', 'bc'), 2)
    -- Вхождение с первого байта считается тоже: поиск начинается с начала.
    t.assert_equals(edit().substr_count('узел, узел', 'узел'), 2)
    t.assert_equals(edit().substr_count('aaa', 'aa'), 1)
    t.assert_equals(edit().substr_count('Узел', 'нет'), 0)
    t.assert_equals(edit().substr_count('Узел', ''), 0)
    -- Искомое берётся дословно: иначе точка сосчитала бы все знаки.
    t.assert_equals(edit().substr_count('a.b.c', '.'), 2)
end

g.test_word_count_counts_what_is_separated_by_spaces = function()
    t.assert_equals(edit().word_count('Список  узлов кластера'), 3)
    t.assert_equals(edit().word_count('  '), 0)
    t.assert_equals(edit().word_count('Список' .. helper.NBSP .. 'узлов'), 2)
end

g.test_word_wrap_breaks_between_words = function()
    local text = 'The quick brown fox jumped over the lazy dog.'

    t.assert_equals(edit().word_wrap(text, 20, '/'), 'The quick brown fox/jumped over the lazy/dog.')
end

g.test_word_wrap_keeps_the_line_breaks_it_was_given = function()
    -- Текст, набранный абзацами, не должен слипнуться в один.
    t.assert_equals(edit().word_wrap('аб\nвг', 20, '/'), 'аб/вг')
    t.assert_equals(edit().word_wrap('', 20, '/'), '')
end

g.test_word_wrap_breaks_exactly_at_the_width = function()
    -- Строка ровно в ширину помещается целиком, а на знак шире — уже нет.
    t.assert_equals(edit().word_wrap('abc de', 6, '/'), 'abc de')
    t.assert_equals(edit().word_wrap('abc de', 5, '/'), 'abc/de')
end

g.test_word_wrap_keeps_an_empty_line_empty = function()
    t.assert_equals(edit().word_wrap('аб\n\nвг', 20, '/'), 'аб//вг')
end

g.test_word_wrap_takes_the_default_width_and_break = function()
    -- Умолчание названо числом: строка из 38 однобуквенных слов — это ровно
    -- 75 ячеек вместе с пробелами, и она обязана поместиться целиком.
    local width = helper.part('tnt.str.chars').width
    local single = edit().word_wrap(('x '):rep(80))

    t.assert_equals(width(single:match('^[^\n]*')), 75)

    -- А слово в две ячейки на 76-й уже не влезает.
    local mixed = edit().word_wrap(('x '):rep(37) .. 'yy ' .. ('x '):rep(40))

    t.assert_equals(width(mixed:match('^[^\n]*')), 73)
    t.assert_equals(edit().word_count(edit().word_wrap(('слово '):rep(20))), 20)
end

g.test_a_word_longer_than_the_line_hangs_out_by_default = function()
    t.assert_equals(
        edit().word_wrap('аб длинноеслово вг', 5, '/'),
        'аб/длинноеслово/вг'
    )
end

g.test_a_long_word_is_cut_when_asked = function()
    t.assert_equals(edit().word_wrap('аб длинноеслово', 5, '/', true), 'аб/длинн/оесло/во')
    t.assert_equals(edit().word_wrap('日本語', 4, '/', true), '日本/語')
end

g.test_a_line_of_one_cell_takes_one_letter = function()
    -- Знак, который сам шире строки, всё равно остаётся целым: разрубить
    -- его нечем, а пустой кусок перед ним — это пустая строка в выводе.
    t.assert_equals(edit().word_wrap('абв', 1, '/', true), 'а/б/в')
    t.assert_equals(edit().word_wrap('日本', 1, '/', true), '日/本')
end

g.test_word_wrap_of_no_width_is_a_programmer_error = function()
    t.assert_error_msg_equals(
        'ширина: нужно число больше нуля, а не 0',
        edit().word_wrap,
        'аб',
        0
    )
end
