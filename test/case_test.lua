--- Тесты регистра и разбиения на слова.

local t = require('luatest')

local helper = dofile('test/helper.lua')

local g = t.group('tnt.str.case')

---@return any
local function case()
    return helper.part('tnt.str.case')
end

g.test_words_are_split_by_everything_that_is_not_a_letter = function()
    t.assert_equals(case().words_of('список узлов'), { 'список', 'узлов' })
    t.assert_equals(case().words_of('список_узлов'), { 'список', 'узлов' })
    t.assert_equals(case().words_of('список-узлов'), { 'список', 'узлов' })
    t.assert_equals(case().words_of('  список  , узлов  '), { 'список', 'узлов' })
    t.assert_equals(case().words_of(''), {})
end

g.test_digits_belong_to_the_word = function()
    t.assert_equals(case().words_of('storage 001'), { 'storage', '001' })
    t.assert_equals(case().words_of('узел1'), { 'узел1' })
end

g.test_a_broken_byte_separates_words = function()
    -- Буквой его не назвать, а терять слова из-за него незачем.
    t.assert_equals(case().words_of('уз\255ел'), { 'уз', 'ел' })
end

g.test_a_capital_letter_starts_a_new_word = function()
    t.assert_equals(case().words_of('списокУзлов'), { 'список', 'Узлов' })
    t.assert_equals(case().words_of('СписокУзлов'), { 'Список', 'Узлов' })
    t.assert_equals(case().words_of('аБ'), { 'а', 'Б' })
end

g.test_an_abbreviation_stays_one_word = function()
    -- «HTTPСервер» — это «HTTP» и «Сервер», а не восемь букв поодиночке
    -- и не одно слово целиком.
    t.assert_equals(case().words_of('HTTPСервер'), { 'HTTP', 'Сервер' })
    t.assert_equals(case().words_of('HTTP'), { 'HTTP' })
    t.assert_equals(case().words_of('AB'), { 'AB' })
    t.assert_equals(case().words_of('Ab'), { 'Ab' })
end

g.test_an_abbreviation_at_the_edge_of_a_word_is_not_cut = function()
    -- Прописная перед не буквой — не начало нового слова: «AB.c» — это
    -- «AB» и «c», а не «A», «B» и «c».
    t.assert_equals(case().words_of('AB.c'), { 'AB', 'c' })
end

g.test_case_is_changed_by_icu_not_by_bytes = function()
    t.assert_equals(case().upper('узел ёж'), 'УЗЕЛ ЁЖ')
    t.assert_equals(case().lower('УЗЕЛ ЁЖ'), 'узел ёж')
end

g.test_only_the_first_letter_changes_case = function()
    t.assert_equals(case().ucfirst('узел'), 'Узел')
    t.assert_equals(case().ucfirst('узЕЛ'), 'УзЕЛ')
    t.assert_equals(case().lcfirst('УЗЕЛ'), 'уЗЕЛ')
    t.assert_equals(case().ucfirst(''), '')
end

g.test_swap_turns_every_letter_over = function()
    t.assert_equals(case().swap('Узел-1'), 'уЗЕЛ-1')
    t.assert_equals(case().swap('уЗЕЛ'), 'Узел')
end

g.test_swap_keeps_a_broken_byte_as_it_was = function()
    -- Не буква через ICU не идёт вовсе: что бы тот ни решил делать
    -- с негодным байтом, у `swap` байт остаётся байтом.
    t.assert_equals(case().swap('а\255'), 'А\255')
end

g.test_namings_are_built_from_the_same_words = function()
    t.assert_equals(case().camel('список узлов'), 'списокУзлов')
    t.assert_equals(case().studly('список_узлов'), 'СписокУзлов')
    t.assert_equals(case().pascal('список узлов'), 'СписокУзлов')
    t.assert_equals(case().snake('Список Узлов'), 'список_узлов')
    t.assert_equals(case().snake('Список Узлов', '.'), 'список.узлов')
    t.assert_equals(case().kebab('СписокУзлов'), 'список-узлов')
end

g.test_naming_of_an_abbreviation_keeps_it_together = function()
    t.assert_equals(case().snake('HTTPСервер'), 'http_сервер')
    t.assert_equals(case().studly('http_сервер'), 'HttpСервер')
end

g.test_headline_reads_like_a_heading = function()
    t.assert_equals(case().headline('emailNotificationSent'), 'Email Notification Sent')
    t.assert_equals(case().headline('список_узлов'), 'Список Узлов')
end

g.test_title_keeps_punctuation_where_it_was = function()
    -- В отличие от headline, строка не разбирается на слова: запятые,
    -- дефисы и двойные пробелы остаются на месте.
    t.assert_equals(case().title('привет, МИР'), 'Привет, Мир')
    t.assert_equals(case().title('а  б'), 'А  Б')
    t.assert_equals(case().title("о'нил"), "О'Нил")
end

g.test_title_keeps_a_broken_byte_as_it_was = function()
    t.assert_equals(case().title('\255аб'), '\255Аб')
end

g.test_a_number_instead_of_a_string_falls_on_the_spot = function()
    t.assert_error_msg_equals('значение: нужна строка, а не number', case().upper, 42)
    t.assert_error_msg_equals('значение: нужна строка, а не number', case().words_of, 42)
end
