--- Тесты русского языка: транслитерация и согласование слова с числом.

local t = require('luatest')

local helper = dofile('test/helper.lua')

local g = t.group('tnt.str.russian')

---@return any
local function russian()
    return helper.part('tnt.str.russian')
end

g.test_cyrillic_turns_into_readable_latin = function()
    -- Транслитерация практическая, а не паспортная: ИКАО дала бы
    -- «iuriia» вместо «yuriya», и прочесть это обратно уже нельзя.
    t.assert_equals(russian().transliterate('список узлов'), 'spisok uzlov')
    t.assert_equals(russian().transliterate('ёжик'), 'yozhik')
    t.assert_equals(russian().transliterate('щука'), 'shchuka')
    t.assert_equals(russian().transliterate('юрия'), 'yuriya')
    t.assert_equals(russian().transliterate('цех'), 'tsekh')
    t.assert_equals(russian().transliterate('подъезд'), 'podezd')
end

g.test_latin_and_digits_pass_through_as_they_were = function()
    t.assert_equals(russian().transliterate('storage-001'), 'storage-001')
    t.assert_equals(russian().transliterate(''), '')
end

g.test_the_case_of_the_letter_is_kept = function()
    t.assert_equals(russian().transliterate('Жук'), 'Zhuk')
    t.assert_equals(russian().transliterate('Ёж'), 'Yozh')
end

g.test_inside_a_shout_the_whole_replacement_is_capital = function()
    -- Иначе «ЖУК» превратился бы в «ZhUK».
    t.assert_equals(russian().transliterate('ЖУК'), 'ZHUK')
    t.assert_equals(russian().transliterate('ЩИ'), 'SHCHI')
    -- Прописная в конце крика: смотреть надо и назад, а не только вперёд.
    t.assert_equals(russian().transliterate('ИЖ'), 'IZH')
    t.assert_equals(russian().transliterate('Иж'), 'Izh')
end

g.test_the_ascii_border_runs_by_the_last_seven_bit_letter = function()
    -- U+007F ещё ASCII и проходит как есть, U+0080 уже нет — и перевода
    -- у него нет тоже.
    t.assert_equals(russian().transliterate('\127'), '\127')
    t.assert_equals(russian().transliterate('\194\128', '?'), '?')
end

g.test_a_letter_without_a_translation_disappears_or_is_replaced = function()
    t.assert_equals(russian().transliterate('日本'), '')
    t.assert_equals(russian().transliterate('a日b', '-'), 'a-b')
    t.assert_equals(russian().transliterate('\255'), '')
end

g.test_neighbouring_slavic_letters_are_translated_too = function()
    -- Знак без перевода просто исчез бы из адреса, склеив соседние слова.
    t.assert_equals(russian().transliterate('їжак ґанок ўзор'), 'yizhak ganok uzor')
end

g.test_the_form_of_a_word_follows_the_last_digit = function()
    t.assert_equals(russian().plural(1, helper.FORMS), 'узел')
    t.assert_equals(russian().plural(2, helper.FORMS), 'узла')
    t.assert_equals(russian().plural(4, helper.FORMS), 'узла')
    t.assert_equals(russian().plural(5, helper.FORMS), 'узлов')
    t.assert_equals(russian().plural(0, helper.FORMS), 'узлов')
    t.assert_equals(russian().plural(21, helper.FORMS), 'узел')
    t.assert_equals(russian().plural(22, helper.FORMS), 'узла')
    t.assert_equals(russian().plural(25, helper.FORMS), 'узлов')
end

g.test_the_teens_do_not_obey_the_last_digit = function()
    -- «11 узлов», а не «11 узел»: в этом десятке счётная форма общая.
    t.assert_equals(russian().plural(11, helper.FORMS), 'узлов')
    t.assert_equals(russian().plural(12, helper.FORMS), 'узлов')
    t.assert_equals(russian().plural(13, helper.FORMS), 'узлов')
    t.assert_equals(russian().plural(14, helper.FORMS), 'узлов')
    t.assert_equals(russian().plural(15, helper.FORMS), 'узлов')
    t.assert_equals(russian().plural(10, helper.FORMS), 'узлов')
    t.assert_equals(russian().plural(111, helper.FORMS), 'узлов')
    t.assert_equals(russian().plural(113, helper.FORMS), 'узлов')
    t.assert_equals(russian().plural(114, helper.FORMS), 'узлов')
    t.assert_equals(russian().plural(121, helper.FORMS), 'узел')
end

g.test_a_fraction_always_takes_the_second_form = function()
    t.assert_equals(russian().plural(1.5, helper.FORMS), 'узла')
    t.assert_equals(russian().plural(0.5, helper.FORMS), 'узла')
    t.assert_equals(russian().plural(11.5, helper.FORMS), 'узла')
end

g.test_a_negative_count_is_counted_by_its_size = function()
    t.assert_equals(russian().plural(-1, helper.FORMS), 'узел')
    t.assert_equals(russian().plural(-5, helper.FORMS), 'узлов')
end

g.test_the_form_is_known_by_its_number = function()
    t.assert_equals(russian().plural_form(1), 1)
    t.assert_equals(russian().plural_form(3), 2)
    t.assert_equals(russian().plural_form(7), 3)
end

g.test_the_number_comes_with_the_word = function()
    t.assert_equals(russian().counted(5, helper.FORMS), '5 узлов')
    t.assert_equals(russian().counted(1, helper.FORMS), '1 узел')
end

g.test_bad_arguments_fall_on_the_spot = function()
    t.assert_error_msg_equals('число: нужно число, а не string', russian().plural_form, '5')
    t.assert_error_msg_equals(
        'формы слова: 3-я форма должна быть непустой строкой',
        russian().plural,
        5,
        { 'узел', 'узла' }
    )
    t.assert_error_msg_equals('значение: нужна строка, а не number', russian().transliterate, 5)
end
