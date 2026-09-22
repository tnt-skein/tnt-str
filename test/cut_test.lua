--- Тесты вырезки: обрезка по знакам и по словам, границы, окрестность.

local t = require('luatest')

local helper = dofile('test/helper.lua')

local g = t.group('tnt.str.cut')

---@return any
local function cut()
    return helper.part('tnt.str.cut')
end

g.test_limit_counts_letters_and_marks_the_cut = function()
    t.assert_equals(cut().limit('Список узлов кластера', 12), 'Список узлов…')
    t.assert_equals(cut().limit('Список', 6), 'Список')
    t.assert_equals(cut().limit('Список', 9), 'Список')
    t.assert_equals(cut().limit('Список', 5), 'Списо…')
    t.assert_equals(cut().limit('Список', 0), '…')
end

g.test_limit_takes_its_own_ending = function()
    t.assert_equals(cut().limit('Список узлов', 6, '...'), 'Список...')
    t.assert_equals(cut().limit('Список узлов', 6, ''), 'Список')
end

g.test_words_keeps_the_last_word_whole = function()
    t.assert_equals(
        cut().words('Perfectly balanced, as all things should be.', 3, ' >>>'),
        'Perfectly balanced, as >>>'
    )
    t.assert_equals(cut().words('Список узлов кластера', 2), 'Список узлов…')
    t.assert_equals(cut().words('Список узлов', 2), 'Список узлов')
    t.assert_equals(cut().words('Список узлов', 5), 'Список узлов')
end

g.test_words_cuts_the_spaces_it_stopped_on = function()
    -- Обрезка посреди пробелов оставила бы хвост из них перед многоточием.
    t.assert_equals(cut().words('Список   узлов', 1, '…'), 'Список…')
    t.assert_equals(cut().words('   Список узлов', 1, '…'), '   Список…')
end

g.test_words_cuts_by_the_whole_separator = function()
    -- Разделителем бывает и неразрывный пробел в два байта: обрезка
    -- на байт левее оставила бы от него половину.
    t.assert_equals(cut().words('Список' .. helper.NBSP .. 'узлов', 1, '…'), 'Список…')
end

g.test_before_and_after_take_the_first_occurrence = function()
    t.assert_equals(cut().before('This is my name', 'my'), 'This is ')
    t.assert_equals(cut().after('This is my name', 'my'), ' name')
    t.assert_equals(cut().before('a-b-c', '-'), 'a')
    t.assert_equals(cut().after('a-b-c', '-'), 'b-c')
end

g.test_before_last_and_after_last_take_the_last_one = function()
    t.assert_equals(cut().before_last('a-b-c', '-'), 'a-b')
    t.assert_equals(cut().after_last('a-b-c', '-'), 'c')
end

g.test_a_missing_border_leaves_the_string_as_it_was = function()
    -- Так удобно в цепочке: `after_last('/')` работает и на пути
    -- без косой черты.
    t.assert_equals(cut().before('Узел', '/'), 'Узел')
    t.assert_equals(cut().after('Узел', '/'), 'Узел')
    t.assert_equals(cut().before_last('Узел', '/'), 'Узел')
    t.assert_equals(cut().after_last('Узел', '/'), 'Узел')
    t.assert_equals(cut().before('Узел', ''), 'Узел')
end

g.test_between_takes_the_widest_piece = function()
    t.assert_equals(cut().between('This is my name', 'This', 'name'), ' is my ')
    t.assert_equals(cut().between('[a] bc [d]', '[', ']'), 'a] bc [d')
end

g.test_between_first_takes_the_shortest_piece = function()
    t.assert_equals(cut().between_first('[a] bc [d]', '[', ']'), 'a')
end

g.test_between_without_a_border_refuses_instead_of_guessing = function()
    -- Отдать вместо куска всю строку значит соврать: между границами,
    -- которых нет, ничего нет.
    t.assert_equals({ cut().between('Узел', '[', ']') }, { nil, 'в тексте нет начала «[»' })
    t.assert_equals(
        { cut().between('[Узел', '[', ']') },
        { nil, 'в тексте нет конца «]» после начала «[»' }
    )
    t.assert_equals({ cut().between_first('Узел', '[', ']') }, { nil, 'в тексте нет начала «[»' })
end

g.test_take_counts_from_either_end = function()
    t.assert_equals(cut().take('Список узлов', 6), 'Список')
    t.assert_equals(cut().take('Список узлов', -5), 'узлов')
    t.assert_equals(cut().take('Список узлов', -1), 'в')
    t.assert_equals(cut().take('Список узлов', 0), '')
end

g.test_excerpt_shows_the_neighbourhood_of_what_was_found = function()
    t.assert_equals(cut().excerpt('This is my name', 'my', { radius = 3 }), '…is my na…')
    t.assert_equals(cut().excerpt('This is my name', 'name', { radius = 3, omission = '(...) ' }), '(...) my name')
end

g.test_excerpt_does_not_mark_the_side_it_did_not_cut = function()
    -- По виду ответа видно, где текст кончился, а где его обрезали.
    t.assert_equals(cut().excerpt('Узел', 'зе'), 'Узел')
    t.assert_equals(cut().excerpt('Список узлов', 'узлов', { radius = 2 }), '…к узлов')
end

g.test_excerpt_radius_counts_letters_up_to_the_edge = function()
    -- Слева восемь знаков: радиус восемь берёт их все и многоточия
    -- не ставит, радиус семь отрезает ровно одну букву.
    t.assert_equals(cut().excerpt('This is my name', 'my', { radius = 8 }), 'This is my name')
    t.assert_equals(cut().excerpt('This is my name', 'my', { radius = 7 }), '…his is my name')
    t.assert_equals(cut().excerpt('Кластер узлов', 'узлов', { radius = 5 }), '…стер узлов')
end

g.test_excerpt_with_zero_radius_shows_the_phrase_alone = function()
    -- Срез отсчётом `-radius` с конца брал при нуле левую сторону целиком:
    -- минус ноль — это ноль, а ноль в срезе — «с первого знака».
    t.assert_equals(cut().excerpt('один два три четыре', 'два', { radius = 0 }), '…два…')
    t.assert_equals(cut().excerpt('один два три четыре', 'два', { radius = -0 }), '…два…')
    -- Неотрезанная сторона по-прежнему без многоточия.
    t.assert_equals(cut().excerpt('один два', 'один', { radius = 0 }), 'один…')
    t.assert_equals(cut().excerpt('один два', 'два', { radius = 0 }), '…два')
end

g.test_excerpt_shows_a_hundred_letters_around_by_default = function()
    local long = ('а'):rep(150) .. 'ключ'

    t.assert_equals(cut().excerpt(long, 'ключ'), '…' .. ('а'):rep(100) .. 'ключ')
end

g.test_excerpt_without_the_phrase_refuses = function()
    t.assert_equals(
        { cut().excerpt('Узел', 'нет') },
        { nil, 'в тексте нет подстроки «нет»' }
    )
end

g.test_a_number_instead_of_a_count_falls_on_the_spot = function()
    t.assert_error_msg_equals('предел: нужно число, а не string', cut().limit, 'Узел', '3')
    t.assert_error_msg_equals('число слов: нужно число, а не nil', cut().words, 'Узел')
    t.assert_error_msg_equals('число знаков: нужно число, а не nil', cut().take, 'Узел')
end

g.test_the_radius_of_an_excerpt_is_checked_like_any_count = function()
    -- Без проверки строка падала арифметикой внутри пакета, а NaN
    -- и бесконечность молча отдавали весь текст.
    t.assert_error_msg_equals(
        'радиус: нужно число, а не string',
        cut().excerpt,
        'This is my name',
        'my',
        { radius = '3' }
    )
    t.assert_error_msg_equals(
        'радиус: нужно конечное число, а не inf',
        cut().excerpt,
        'This is my name',
        'my',
        { radius = math.huge }
    )
end

g.test_a_fractional_count_is_refused_by_its_name = function()
    -- Без проверки дробный счёт падал арифметикой внутри среза, а в словах
    -- молча брал на одно слово больше целой части.
    t.assert_error_msg_equals('предел: нужно целое число, а не 2.5', cut().limit, 'abcdef', 2.5)
    t.assert_error_msg_equals(
        'число слов: нужно целое число, а не 1.5',
        cut().words,
        'a b c',
        1.5
    )
    t.assert_error_msg_equals(
        'число знаков: нужно целое число, а не 2.5',
        cut().take,
        'abcdef',
        2.5
    )
    t.assert_error_msg_equals(
        'число знаков: нужно целое число, а не -2.5',
        cut().take,
        'abcdef',
        -2.5
    )
    t.assert_error_msg_equals(
        'радиус: нужно целое число, а не 1.5',
        cut().excerpt,
        'один два три',
        'два',
        { radius = 1.5 }
    )
end

g.test_a_negative_count_is_refused_where_it_means_nothing = function()
    -- `take` считает отрицательное с конца, а «минус три знака вокруг»
    -- и «обрезать до минус одного» смысла не имеют: радиус резал текст
    -- бессмысленно, а предел отдавал строку целиком с многоточием.
    t.assert_error_msg_equals(
        'радиус: нужно число не меньше нуля, а не -3',
        cut().excerpt,
        'один два три четыре',
        'два',
        { radius = -3 }
    )
    t.assert_error_msg_equals(
        'предел: нужно число не меньше нуля, а не -1',
        cut().limit,
        'Список',
        -1
    )
    t.assert_error_msg_equals(
        'число слов: нужно число не меньше нуля, а не -1',
        cut().words,
        'a b',
        -1
    )
    t.assert_equals(cut().words('Список узлов', 0), '…')
end
