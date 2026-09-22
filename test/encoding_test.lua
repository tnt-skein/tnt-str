--- Тесты перекодировки: cp1251 в UTF-8 и обратно, отказы парой.

local t = require('luatest')

local helper = dofile('test/helper.lua')

local g = t.group('tnt.str.encoding')

---@return any
local function encoding()
    return helper.part('tnt.str.encoding')
end

--- «Привет» в cp1251: по байту на букву.
local CP1251_HELLO = '\207\240\232\226\229\242'

--- «Привет» в koi8-r: те же буквы, другие байты.
local KOI8_HELLO = '\240\210\201\215\197\212'

--- Модуль перекодировки, загруженный заново поверх подменённого ядра `iconv`.
---
--- Файл берётся из списка модулей помощника: так проверка грузит тот же
--- исходник, что и остальные, где бы он ни лежал. Настоящее ядро
--- возвращается на место и тогда, когда исходник не загрузился.
---@param core table Замена встроенного модуля `iconv`
---@return any
local function encoding_over(core)
    ---@type string|nil
    local path

    for _, module in ipairs(helper.MODULES) do
        if module.name == 'tnt.str.encoding' then
            path = module.path
        end
    end

    -- Без пути `dofile` читал бы стандартный ввод и ждал бы его молча.
    if path == nil then
        error('модуля tnt.str.encoding нет в списке помощника', 0)
    end

    local real = package.loaded.iconv

    package.loaded.iconv = core

    local ok, loaded = pcall(dofile, path)

    package.loaded.iconv = real

    if not ok then
        error(loaded, 0)
    end

    return loaded
end

g.test_decode_turns_cp1251_into_utf8 = function()
    t.assert_equals(encoding().decode(CP1251_HELLO, 'cp1251'), 'Привет')
    t.assert_equals(encoding().decode(KOI8_HELLO, 'koi8-r'), 'Привет')
    t.assert_equals(encoding().decode('', 'cp1251'), '')
    -- Латиница в cp1251 совпадает с ASCII и проходит как есть.
    t.assert_equals(encoding().decode('node-001', 'cp1251'), 'node-001')
end

g.test_encode_turns_utf8_into_cp1251 = function()
    t.assert_equals(encoding().encode('Привет', 'cp1251'), CP1251_HELLO)
    t.assert_equals(encoding().encode('Привет', 'koi8-r'), KOI8_HELLO)
    t.assert_equals(encoding().encode('', 'cp1251'), '')
end

g.test_the_name_of_the_encoding_is_taken_as_iconv_takes_it = function()
    -- Регистр и синонимы — дело ядра: `cp1251`, `CP1251` и `windows-1251`
    -- одна кодировка, и пакет их не переписывает.
    t.assert_equals(encoding().decode(CP1251_HELLO, 'CP1251'), 'Привет')
    t.assert_equals(encoding().decode(CP1251_HELLO, 'windows-1251'), 'Привет')
    t.assert_equals(encoding().encode('Привет', 'WINDOWS-1251'), CP1251_HELLO)
end

g.test_the_core_is_asked_for_utf8_by_its_registered_name = function()
    -- glibc выбрасывает из имени кодировки лишние знаки: `UTF 8` и `UTF+8`
    -- у него — тот же UTF-8, и по ответу написание не различить. iconv(3)
    -- такого не обещает, поэтому ядру уходит имя из реестра IANA — иначе
    -- перекодировка работала бы только там, где libc прощает написание.
    local core = require('iconv')
    local asked = {}
    local converting = encoding_over({
        new = function(to, from)
            table.insert(asked, { to, from })

            return core.new(to, from)
        end,
    })

    t.assert_equals(converting.decode(CP1251_HELLO, 'cp1251'), 'Привет')
    t.assert_equals(converting.encode('Привет', 'koi8-r'), KOI8_HELLO)
    t.assert_equals(asked, { { 'UTF-8', 'cp1251' }, { 'koi8-r', 'UTF-8' } })
    t.assert_is(package.loaded.iconv, core)
end

g.test_decode_and_encode_are_inverse = function()
    local text = 'Узел storage-001: диск заполнен на 97 %'
    local bytes = encoding().encode(text, 'cp1251')

    t.assert_equals(#bytes, 39)
    t.assert_equals(encoding().decode(bytes, 'cp1251'), text)
end

g.test_utf8_itself_is_an_encoding_too = function()
    -- Через ядро UTF-8 в UTF-8 — это проверка годности: битый байт
    -- отвергается, а не проходит дальше.
    t.assert_equals(encoding().decode('Привет', 'utf-8'), 'Привет')
    t.assert_equals(
        { encoding().decode('a\255b', 'utf-8') },
        { nil, 'в тексте есть байты не из кодировки utf-8' }
    )
end

g.test_a_byte_that_the_encoding_does_not_have_is_a_refusal = function()
    -- 0x98 в cp1251 не назначен: файл с ним — не cp1251 либо битый.
    t.assert_equals(
        { encoding().decode('a\152b', 'cp1251') },
        { nil, 'в тексте есть байты не из кодировки cp1251' }
    )
end

g.test_a_text_cut_in_the_middle_of_a_character_is_a_refusal = function()
    -- UTF-16 — по два байта на знак; нечётный хвост — оборванный знак.
    -- Ядро подписывает эту причину «Invalid multibyte sequence», то есть
    -- как негодную, а не оборванную; пакет называет её верно.
    t.assert_equals(
        { encoding().decode('\255\254\30', 'utf-16') },
        { nil, 'текст в кодировке utf-16 обрывается посреди знака' }
    )
    t.assert_equals(encoding().decode('\255\254\30\4', 'utf-16'), 'О')
end

g.test_a_character_that_the_encoding_does_not_have_is_a_refusal = function()
    t.assert_equals(
        { encoding().encode('Узел 日本', 'cp1251') },
        { nil, 'в тексте есть знак, которого нет в кодировке cp1251' }
    )
    t.assert_equals(
        { encoding().encode('a😀b', 'koi8-r') },
        { nil, 'в тексте есть знак, которого нет в кодировке koi8-r' }
    )
end

g.test_encode_names_the_broken_byte_before_asking_the_kernel = function()
    -- У ядра битый байт и знак не из кодировки — одна причина; вызывающему
    -- они чинятся в разных местах, поэтому байт называется отдельно.
    t.assert_equals({ encoding().encode('a\255b', 'cp1251') }, { nil, 'байт 2 — не UTF-8' })
    t.assert_equals({ encoding().encode('При\208', 'cp1251') }, { nil, 'байт 7 — не UTF-8' })
    t.assert_equals({ encoding().encode('\192\128', 'cp1251') }, { nil, 'байт 1 — не UTF-8' })
end

g.test_an_unknown_encoding_is_a_refusal_not_an_exception = function()
    -- Имя кодировки приходит из заголовка письма — это случай из жизни.
    t.assert_equals(
        { encoding().decode(CP1251_HELLO, 'cp-1251-x') },
        { nil, 'кодировка «cp-1251-x» неизвестна' }
    )
    t.assert_equals(
        { encoding().encode('Привет', 'nope-42') },
        { nil, 'кодировка «nope-42» неизвестна' }
    )
end

g.test_an_empty_name_is_a_refusal_because_it_means_the_locale = function()
    -- Ядро принимает пустое имя как «кодировка локали» — скрытую
    -- настройку машины, от которой ответ зависел бы молча.
    t.assert_equals({ encoding().decode(CP1251_HELLO, '') }, { nil, 'кодировка не названа' })
    t.assert_equals({ encoding().encode('Привет', '') }, { nil, 'кодировка не названа' })
end

g.test_iconv_suffixes_are_refused = function()
    -- `//IGNORE` портит соседние конвертеры той же пары кодировок:
    -- они начинают молча терять знаки. Отвергается до ядра.
    t.assert_equals({ encoding().encode('Узел 日本', 'cp1251//IGNORE') }, {
        nil,
        'кодировка «cp1251//IGNORE»: суффиксы //TRANSLIT и //IGNORE не принимаются',
    })
    t.assert_equals({ encoding().decode(CP1251_HELLO, 'cp1251//TRANSLIT') }, {
        nil,
        'кодировка «cp1251//TRANSLIT»: суффиксы //TRANSLIT и //IGNORE не принимаются',
    })
    t.assert_equals({ encoding().decode(CP1251_HELLO, '//TRANSLIT') }, {
        nil,
        'кодировка «//TRANSLIT»: суффиксы //TRANSLIT и //IGNORE не принимаются',
    })
end

g.test_a_non_string_is_a_programmer_error = function()
    t.assert_error_msg_equals(
        'значение: нужна строка, а не number',
        encoding().decode,
        42,
        'cp1251'
    )
    t.assert_error_msg_equals(
        'значение: нужна строка, а не nil',
        encoding().encode,
        nil,
        'cp1251'
    )
    t.assert_error_msg_equals(
        'кодировка: нужна строка, а не nil',
        encoding().decode,
        CP1251_HELLO
    )
    t.assert_error_msg_equals(
        'кодировка: нужна строка, а не table',
        encoding().encode,
        'Привет',
        {}
    )
    -- Ошибка программиста видна раньше отказа на данных: у `encode`
    -- без имени кодировки не «байт 2 — не UTF-8», а исключение.
    t.assert_error_msg_equals('кодировка: нужна строка, а не nil', encoding().encode, 'a\255b')
end

g.test_the_facade_and_the_chain_know_the_encoding = function()
    local str = helper.str

    t.assert_equals(str.decode(CP1251_HELLO, 'cp1251'), 'Привет')
    t.assert_equals(str.encode('Привет', 'cp1251'), CP1251_HELLO)
    t.assert_equals(str.of(CP1251_HELLO):decode('cp1251'):upper():value(), 'ПРИВЕТ')
    t.assert_equals(
        { str.of('a\152b'):decode('cp1251') },
        { nil, 'в тексте есть байты не из кодировки cp1251' }
    )
end
