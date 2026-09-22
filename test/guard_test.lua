--- Тесты проверки аргументов: за что пакет роняет вызывающего и что говорит.

local t = require('luatest')

local helper = dofile('test/helper.lua')

local g = t.group('tnt.str.guard')

---@return any
local function guard()
    return helper.part('tnt.str.guard')
end

g.test_a_string_goes_through_untouched = function()
    t.assert_equals(guard().text('Узел'), 'Узел')
    t.assert_equals(guard().text(''), '')
end

g.test_a_number_instead_of_a_string_is_a_programmer_error = function()
    -- Отказом это не вернуть: прикладной код не обязан проверять,
    -- строку ли он сам же и передал.
    t.assert_error_msg_equals('значение: нужна строка, а не number', guard().text, 42)
    t.assert_error_msg_equals('значение: нужна строка, а не nil', guard().text, nil)
end

g.test_the_argument_is_named_in_the_message_when_it_has_a_name = function()
    t.assert_error_msg_equals(
        'образец: нужна строка, а не table',
        guard().text,
        {},
        'образец'
    )
end

g.test_a_number_is_demanded_where_a_number_is_meant = function()
    t.assert_equals(guard().number(3, 'предел'), 3)
    t.assert_equals(guard().number(-1, 'предел'), -1)
    t.assert_error_msg_equals(
        'предел: нужно число, а не string',
        guard().number,
        '3',
        'предел'
    )
end

g.test_nan_and_infinity_are_not_numbers_here = function()
    -- Тип у них `number`, но счётом и шириной они не бывают. Пропущенная,
    -- бесконечность дошла бы до `rep` и кончилась, смотря по сборке,
    -- нехваткой памяти или молча пустой строкой — не там, где её передали.
    t.assert_error_msg_equals(
        'ширина: нужно конечное число, а не inf',
        guard().number,
        1 / 0,
        'ширина'
    )
    t.assert_error_msg_equals(
        'ширина: нужно конечное число, а не -inf',
        guard().number,
        -1 / 0,
        'ширина'
    )
    -- NaN называется одинаково на любой сборке, а не «nan» или «-nan».
    t.assert_error_msg_equals(
        'ширина: нужно конечное число, а не NaN',
        guard().number,
        0 / 0,
        'ширина'
    )
    -- Граница — сама бесконечность: конечное число, самое далёкое от нуля, проходит.
    t.assert_equals(guard().number(-1.7976931348623157e308, 'ширина'), -1.7976931348623157e308)
end

g.test_infinity_is_not_a_positive_number_either = function()
    t.assert_error_msg_equals(
        'размер куска: нужно конечное число, а не inf',
        guard().positive,
        math.huge,
        'размер куска'
    )
end

g.test_zero_is_refused_where_it_would_loop_forever = function()
    t.assert_equals(guard().positive(1, 'размер куска'), 1)
    t.assert_error_msg_equals(
        'размер куска: нужно число больше нуля, а не 0',
        guard().positive,
        0,
        'размер куска'
    )
    t.assert_error_msg_equals(
        'размер куска: нужно число больше нуля, а не -2',
        guard().positive,
        -2,
        'размер куска'
    )
end

g.test_a_count_of_letters_is_demanded_whole = function()
    t.assert_equals(guard().integer(3, 'предел'), 3)
    t.assert_equals(guard().integer(-2, 'предел'), -2)
    t.assert_equals(guard().integer(0, 'предел'), 0)
    -- Дробный номер не указывает ни на какой знак; пропущенный, он падал
    -- арифметикой внутри среза, а не текстом про аргумент.
    t.assert_error_msg_equals(
        'предел: нужно целое число, а не 2.5',
        guard().integer,
        2.5,
        'предел'
    )
    t.assert_error_msg_equals(
        'предел: нужно целое число, а не -0.5',
        guard().integer,
        -0.5,
        'предел'
    )
end

g.test_an_integer_is_a_finite_number_first = function()
    -- Тип и конечность проверяются раньше целости: у строки и NaN
    -- вопрос «целое ли» смысла не имеет.
    t.assert_error_msg_equals(
        'предел: нужно число, а не string',
        guard().integer,
        '3',
        'предел'
    )
    t.assert_error_msg_equals(
        'предел: нужно конечное число, а не inf',
        guard().integer,
        math.huge,
        'предел'
    )
    t.assert_error_msg_equals(
        'предел: нужно конечное число, а не NaN',
        guard().integer,
        0 / 0,
        'предел'
    )
end

g.test_a_count_that_cannot_be_negative_stops_at_zero = function()
    t.assert_equals(guard().count(0, 'радиус'), 0)
    t.assert_equals(guard().count(7, 'радиус'), 7)
    t.assert_error_msg_equals(
        'радиус: нужно число не меньше нуля, а не -1',
        guard().count,
        -1,
        'радиус'
    )
    t.assert_error_msg_equals(
        'радиус: нужно целое число, а не 1.5',
        guard().count,
        1.5,
        'радиус'
    )
end

g.test_a_natural_count_starts_at_one = function()
    t.assert_equals(guard().natural(1, 'размер куска'), 1)
    t.assert_equals(guard().natural(4, 'размер куска'), 4)
    -- О нуле отказ тот же, что у `positive`: пустого куска не бывает.
    t.assert_error_msg_equals(
        'размер куска: нужно число больше нуля, а не 0',
        guard().natural,
        0,
        'размер куска'
    )
    t.assert_error_msg_equals(
        'размер куска: нужно целое число, а не 2.5',
        guard().natural,
        2.5,
        'размер куска'
    )
end

g.test_three_word_forms_are_demanded_whole = function()
    t.assert_equals(guard().forms(helper.FORMS), helper.FORMS)
end

g.test_a_missing_form_is_named_by_its_number = function()
    -- Пропущенная третья форма выстрелит на пяти узлах, а не на одном:
    -- то есть не там и не тогда, где её забыли.
    t.assert_error_msg_equals(
        'формы слова: 3-я форма должна быть непустой строкой',
        guard().forms,
        { 'узел', 'узла' }
    )
    t.assert_error_msg_equals(
        'формы слова: 1-я форма должна быть непустой строкой',
        guard().forms,
        { '', 'узла', 'узлов' }
    )
    t.assert_error_msg_equals(
        'формы слова: 2-я форма должна быть непустой строкой',
        guard().forms,
        { 'узел', 2, 'узлов' }
    )
    t.assert_error_msg_equals(
        'формы слова: нужен список из трёх строк, а не string',
        guard().forms,
        'узел'
    )
end

g.test_a_lone_value_becomes_a_list_of_one = function()
    t.assert_equals(guard().many('уз'), { 'уз' })
    t.assert_equals(guard().many({ 'уз', 'ел' }), { 'уз', 'ел' })
end
