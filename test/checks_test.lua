--- Тесты проверок: вхождение, края, образец, форма значения.

local t = require('luatest')
local clock = require('clock')

local helper = dofile('test/helper.lua')

local g = t.group('tnt.str.checks')

---@return any
local function checks()
    return helper.part('tnt.str.checks')
end

g.test_contains_finds_one_of_the_substrings = function()
    t.assert_equals(checks().contains('Список узлов', 'узл'), true)
    t.assert_equals(checks().contains('Список узлов', 'диск'), false)
    t.assert_equals(checks().contains('Список узлов', { 'диск', 'узл' }), true)
    t.assert_equals(checks().contains('Список узлов', { 'диск', 'том' }), false)
end

g.test_contains_can_forget_the_case = function()
    -- «Ё» и «ё» — разные байты, и никакой байтовый приём их не сблизит:
    -- обе строки приводятся к нижнему регистру через ICU.
    t.assert_equals(checks().contains('ЁЖИК', 'ёж'), false)
    t.assert_equals(checks().contains('ЁЖИК', 'ёж', true), true)
end

g.test_an_empty_substring_is_not_found_anywhere = function()
    t.assert_equals(checks().contains('Узел', ''), false)
    t.assert_equals(checks().contains_all('Узел', { '' }), false)
end

g.test_contains_all_demands_every_substring = function()
    t.assert_equals(checks().contains_all('Список узлов', { 'Список', 'узл' }), true)
    t.assert_equals(checks().contains_all('Список узлов', { 'Список', 'диск' }), false)
    t.assert_equals(checks().contains_all('СПИСОК узлов', { 'список', 'УЗЛ' }, true), true)
    t.assert_equals(checks().contains_all('Узел', {}), true)
end

g.test_edges_are_checked_by_the_whole_substring = function()
    t.assert_equals(checks().starts_with('Список узлов', 'Спис'), true)
    t.assert_equals(checks().starts_with('Список узлов', 'писок'), false)
    t.assert_equals(checks().ends_with('Список узлов', 'узлов'), true)
    t.assert_equals(checks().ends_with('Список узлов', 'узло'), false)
end

g.test_edges_take_a_list_and_can_forget_the_case = function()
    t.assert_equals(checks().starts_with('Узел', { 'Диск', 'Уз' }), true)
    t.assert_equals(checks().ends_with('Узел', { 'ок', 'ел' }), true)
    t.assert_equals(checks().starts_with('УЗЕЛ', 'уз', true), true)
    t.assert_equals(checks().ends_with('УЗЕЛ', 'ел', true), true)
end

g.test_an_empty_substring_is_no_edge = function()
    -- Пустая подстрока есть в начале и в конце любой строки; отвечать
    -- на неё «да» значит незаметно пропустить пустую настройку.
    t.assert_equals(checks().starts_with('Узел', ''), false)
    t.assert_equals(checks().ends_with('Узел', ''), false)
end

g.test_pattern_with_a_star_matches_by_the_whole_string = function()
    t.assert_equals(checks().is('storage-001', 'storage-*'), true)
    t.assert_equals(checks().is('storage-001', '*-001'), true)
    t.assert_equals(checks().is('storage-001', '*'), true)
    t.assert_equals(checks().is('storage-001', 'storage'), false)
    t.assert_equals(checks().is('storage-001', 'torage-*'), false)
end

g.test_everything_but_the_star_in_a_pattern_is_taken_literally = function()
    -- Образцы пишут люди в настройках: точка в них означает точку,
    -- а не «любой знак».
    t.assert_equals(checks().is('axb', 'a.b'), false)
    t.assert_equals(checks().is('a.b', 'a.b'), true)
    t.assert_equals(checks().is('photo.JPG', '*.jpg', true), true)
end

g.test_a_pattern_escapes_every_sign_that_lua_counts_special = function()
    -- Каждый из них в шаблоне Lua значит своё, и неэкранированный
    -- превращает образец из настроек в неожиданное правило. Звёздочки
    -- в списке нет: она в образце значит своё намеренно.
    for _, sign in ipairs({ '+', '-', '?', '.', '(', ')', '[', ']', '^', '$', '%' }) do
        local sample = 'a' .. sign .. 'b'

        t.assert_equals(checks().is(sample, sample), true, sample)
        t.assert_equals(checks().is('axb', sample), false, sample)
    end
end

g.test_lua_pattern_is_available_where_a_star_is_not_enough = function()
    t.assert_equals(checks().is_match('storage-001', '%-%d+$'), true)
    t.assert_equals(checks().is_match('storage-abc', '%-%d+$'), false)
end

g.test_empty_means_empty_or_nothing_at_all = function()
    t.assert_equals(checks().is_empty(''), true)
    t.assert_equals(checks().is_empty(nil), true)
    t.assert_equals(checks().is_empty(' '), false)
    t.assert_equals(checks().is_empty('Узел'), false)
end

g.test_ascii_is_only_the_first_half_of_the_byte = function()
    t.assert_equals(checks().is_ascii('storage-001'), true)
    t.assert_equals(checks().is_ascii(''), true)
    t.assert_equals(checks().is_ascii('Узел'), false)
end

g.test_uuid_is_checked_by_its_canonical_shape = function()
    t.assert_equals(checks().is_uuid('5f8a1c2e-3b4d-4e5f-8a9b-0c1d2e3f4a5b'), true)
    t.assert_equals(checks().is_uuid('5F8A1C2E-3B4D-4E5F-8A9B-0C1D2E3F4A5B'), true)
    t.assert_equals(checks().is_uuid('5f8a1c2e3b4d4e5f8a9b0c1d2e3f4a5b'), false)
    t.assert_equals(checks().is_uuid('5f8a1c2e-3b4d-4e5f-8a9b-0c1d2e3f4a5'), false)
end

g.test_a_link_is_a_link_only_with_an_allowed_scheme = function()
    -- `javascript:alert(1)` — тоже ссылка по RFC 3986; пропустить её
    -- в разметку панели значит отдать панель.
    t.assert_equals(checks().is_url('https://example.org/a?b#c'), true)
    t.assert_equals(checks().is_url('HTTP://example.org'), true)
    t.assert_equals(checks().is_url('javascript://example.org'), false)
    t.assert_equals(checks().is_url('javascript://example.org', { 'javascript' }), true)
    t.assert_equals(checks().is_url('example.org'), false)
    t.assert_equals(checks().is_url('https://'), false)
    t.assert_equals(checks().is_url('https:///'), false)
    t.assert_equals(checks().is_url('http://a'), true)
end

g.test_a_scheme_may_be_short_and_may_have_signs_in_it = function()
    -- Схемы вроде `coap+tcp` и `chrome-extension` существуют, и отказывать
    -- им из-за знака в имени неправильно.
    t.assert_equals(checks().is_url('a://b', { 'a' }), true)
    t.assert_equals(checks().is_url('a+b://c', { 'a+b' }), true)
    t.assert_equals(checks().is_url('a-b://c', { 'a-b' }), true)
    t.assert_equals(checks().is_url('a.b://c', { 'a.b' }), true)
end

g.test_a_space_anywhere_in_the_link_makes_it_not_a_link = function()
    -- Пробел значит, что в строку попало что-то сверх ссылки: адрес
    -- с припиской, две ссылки подряд, обрывок формы.
    t.assert_equals(checks().is_url('http://exa mple.org'), false)
    t.assert_equals(checks().is_url('http://example.org '), false)
    t.assert_equals(checks().is_url('http://example.org/a\tb'), false)
end

g.test_a_link_of_a_hundred_thousand_letters_is_answered_at_once = function()
    -- Прежний образец ставил рядом два жадных повтора, и на этой строке
    -- откат считал четырнадцать секунд, не уступая файбера никому. Строка
    -- приходит откуда угодно, так что столько же стоил бы один запрос.
    -- Порог взят с запасом в сотни раз: на деле ответ за полмиллисекунды.
    local huge = 'http://' .. ('a'):rep(100000) .. ' x'

    local started = clock.monotonic()
    local answer = checks().is_url(huge)

    t.assert_equals(answer, false)
    t.assert_lt(clock.monotonic() - started, 0.5)
end

g.test_json_is_checked_through_the_scanner = function()
    t.assert_equals(checks().is_json('{"узел": [1, null]}'), true)
    t.assert_equals(checks().is_json('{узел: 1}'), false)
end

g.test_a_number_instead_of_a_string_falls_on_the_spot = function()
    t.assert_error_msg_equals(
        'значение: нужна строка, а не number',
        checks().contains,
        42,
        'уз'
    )
    t.assert_error_msg_equals('образец: нужна строка, а не nil', checks().is, 'Узел')
    t.assert_error_msg_equals('шаблон: нужна строка, а не nil', checks().is_match, 'Узел')
end
