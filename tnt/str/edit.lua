--- Правка строки: обрезка, замена, дополнение, перенос.
---
--- Здесь сходятся оба счёта. Замена и удаление ищут байтами — подстрока
--- в UTF-8 не совпадает с серединой буквы, и байтовый поиск быстрее
--- и короче. Обрезка, дополнение и перенос считают знаки: их число видно
--- снаружи, и ошибка в нём — это обрубок буквы в выводе.
---
--- Дополнение (`pad_*`) меряет не знаки, а **ячейки терминала**, и это
--- решение, о котором стоит знать. Дополняют ради столбца: чтобы правая
--- граница таблицы была ровной. Для кириллицы и латиницы знак и ячейка —
--- одно и то же, так что разницы не видно; а вот столбец с иероглифом,
--- посчитанный по знакам, уезжает вдвое. Обратная сторона: знак в две
--- ячейки не делится, и ширину не всегда удаётся набрать точно —
--- недобор в одну ячейку остаётся как есть.
---
--- Замены без учёта регистра здесь нет намеренно. Найти совпадение просто,
--- а вот вырезать его из исходной строки — уже нет: у некоторых букв
--- строчная и прописная разной длины в байтах («ß» → «SS»), и смещения,
--- посчитанные по приведённой копии, не годятся для исходной. Проверки
--- (`contains`, `starts_with`) регистр игнорировать умеют — им хватает
--- ответа «да или нет».

local chars = require('tnt.str.chars')
local guard = require('tnt.str.guard')

local Module = {}

--- Чем дополняют до ширины, если не сказано иное.
local SPACE = ' '

--- Ширина строки при переносе по умолчанию: строка целиком помещается
--- в терминал на 80 колонок, и остаётся запас под отступ или знак цитирования.
local WRAP_WIDTH = 75

--- Чем разделяются строки при переносе по умолчанию.
local NEWLINE = '\n'

--- Решение, снимать ли знак с края строки.
---
--- Без списка знаков снимается пробельное — вместе с неразрывным пробелом,
--- ради которого всё и затевалось. Со списком снимается только названное,
--- и сравнение идёт по знакам, а не по байтам: список «…» — это один знак,
--- а не три байта, каждый из которых снимали бы поодиночке.
---@param charlist string|nil
---@return fun(code: integer|nil): boolean
local function stripper(charlist)
    if charlist == nil then
        return chars.is_space
    end

    local set = {}

    for _, piece in ipairs(chars.pieces(charlist)) do
        set[piece.code] = true
    end

    return function(code)
        return set[code] == true
    end
end

--- Снять знаки с краёв: с левого, с правого или с обоих.
---@param text string
---@param charlist string|nil
---@param left boolean
---@param right boolean
---@return string
local function cut_edges(text, charlist, left, right)
    local drop = stripper(charlist)
    local pieces = chars.pieces(guard.text(text))
    local first = 1
    local last = #pieces

    -- Границы не выходят за список: условие цикла держит их внутри,
    -- и знак под номером обязательно есть.
    ---@param index integer
    ---@return integer|nil
    local function code_at(index)
        local piece = pieces[index]
        ---@cast piece { text: string, code: integer|nil }

        return piece.code
    end

    while left and first <= last and drop(code_at(first)) do
        first = first + 1
    end

    while right and first <= last and drop(code_at(last)) do
        last = last - 1
    end

    return chars.sub(text, first, last)
end

--- Снять пробелы с обоих краёв.
---@param text string
---@param charlist string|nil Свой список знаков вместо пробельных
---@return string
function Module.trim(text, charlist)
    return cut_edges(text, charlist, true, true)
end

--- Снять пробелы слева.
---@param text string
---@param charlist string|nil
---@return string
function Module.ltrim(text, charlist)
    return cut_edges(text, charlist, true, false)
end

--- Снять пробелы справа.
---@param text string
---@param charlist string|nil
---@return string
function Module.rtrim(text, charlist)
    return cut_edges(text, charlist, false, true)
end

--- Схлопнуть пробелы: подряд идущие в один, по краям — совсем.
---@param text string
---@return string
function Module.squish(text)
    local words = {}
    local current = {}

    for _, piece in ipairs(chars.pieces(guard.text(text))) do
        if chars.is_space(piece.code) then
            if #current > 0 then
                table.insert(words, table.concat(current))
                current = {}
            end
        else
            table.insert(current, piece.text)
        end
    end

    if #current > 0 then
        table.insert(words, table.concat(current))
    end

    return table.concat(words, SPACE)
end

--- Заполнитель нужной ширины: повторяется и обрезается по знакам.
---@param pad string
---@param cells number Сколько ячеек добрать
---@return string
local function filling(pad, cells)
    -- Заполнитель нулевой ширины набирал бы ширину вечно.
    guard.positive(chars.width(pad), 'заполнитель')

    local pieces = {}
    local total = 0

    -- Повторов ровно столько, сколько ячеек: один повтор — это не меньше
    -- одной ячейки, значит набранного хватит с запасом, а лишнее срежет
    -- сам цикл. Ячеек меньше одной — повторов ноль, и цикл не начнётся.
    for _, piece in ipairs(chars.pieces(pad:rep(math.floor(cells)))) do
        local step = chars.width_of(piece.code)

        if total + step > cells then
            break
        end

        total = total + step
        table.insert(pieces, piece.text)
    end

    return table.concat(pieces)
end

--- Дополнить слева до ширины.
---@param text string
---@param width number Ширина в ячейках терминала
---@param pad string|nil Умолчание — пробел
---@return string
function Module.pad_left(text, width, pad)
    local gap = guard.number(width, 'ширина') - chars.width(guard.text(text))

    return filling(pad or SPACE, gap) .. text
end

--- Дополнить справа до ширины.
---@param text string
---@param width number
---@param pad string|nil
---@return string
function Module.pad_right(text, width, pad)
    local gap = guard.number(width, 'ширина') - chars.width(guard.text(text))

    return text .. filling(pad or SPACE, gap)
end

--- Дополнить с обеих сторон; лишняя ячейка достаётся правой.
---@param text string
---@param width number
---@param pad string|nil
---@return string
function Module.pad_both(text, width, pad)
    local gap = guard.number(width, 'ширина') - chars.width(guard.text(text))
    -- Половина — умножением, а не делением: мутант деления на ноль давал
    -- бесконечность, и `rep` на ней ронял процесс нехваткой памяти вместо
    -- того, чтобы провалить проверку.
    local left = math.floor(gap * 0.5)

    return filling(pad or SPACE, left) .. text .. filling(pad or SPACE, gap - left)
end

--- Повторить строку.
---@param text string
---@param times number
---@return string
function Module.repeat_times(text, times)
    return guard.text(text):rep(math.floor(guard.number(times, 'число повторов')))
end

--- Задом наперёд, по знакам.
---@param text string
---@return string
function Module.reverse(text)
    return chars.reverse(guard.text(text))
end

--- Замена вхождений подстроки.
---
--- Чем заменять, решает `supply`: он получает номер вхождения и отдаёт
--- замену либо nil — «дальше не заменяем». Через него выражаются и замена
--- всех вхождений, и первого, и замена по списку.
---@param text string
---@param search string
---@param supply fun(number: integer): string|nil
---@return string
local function substitute(text, search, supply)
    if search == '' then
        return text
    end

    local pieces = {}
    -- Начало непрочитанного — отрицательным отсчётом, то есть первым байтом
    -- любой строки, и пустой тоже: единицу и ноль поиск и срез читают
    -- одинаково, и мутант с нулём был бы неотличим.
    local from = -#text
    local number = 0

    while true do
        local at = text:find(search, from, true)

        if at == nil then
            break
        end

        number = number + 1
        local replacement = supply(number)

        if replacement == nil then
            break
        end

        table.insert(pieces, text:sub(from, at - 1))
        table.insert(pieces, replacement)
        from = at + #search
    end

    table.insert(pieces, text:sub(from))

    return table.concat(pieces)
end

--- Заменить все вхождения; искать можно и по списку подстрок.
---@param text string
---@param search string|string[]
---@param replacement string
---@return string
function Module.replace(text, search, replacement)
    local result = guard.text(text)

    for _, needle in ipairs(guard.many(search)) do
        result = substitute(result, needle, function()
            return replacement
        end)
    end

    return result
end

--- Заменить первое вхождение.
---@param text string
---@param search string
---@param replacement string
---@return string
function Module.replace_first(text, search, replacement)
    return substitute(guard.text(text), search, function(number)
        if number == 1 then
            return replacement
        end

        return nil
    end)
end

--- Сколько раз подстрока встречается в строке; вхождения не перекрываются.
---@param text string
---@param needle string
---@return integer
function Module.substr_count(text, needle)
    guard.text(text)

    local total = 0
    -- Начало поиска — отрицательным отсчётом, по той же причине, что у замены.
    local from = -#text

    while needle ~= '' do
        local at = text:find(needle, from, true)

        if at == nil then
            break
        end

        total = total + 1
        from = at + #needle
    end

    return total
end

--- Заменить последнее вхождение.
---
--- Через ту же замену по номеру: вхождения до последнего заменяются
--- сами на себя. Резать строку на куски вокруг найденного пришлось бы
--- вторым способом, а два способа делать одно и то же однажды разойдутся.
---@param text string
---@param search string
---@param replacement string
---@return string
function Module.replace_last(text, search, replacement)
    local last = Module.substr_count(guard.text(text), search)

    return substitute(text, search, function(number)
        if number == last then
            return replacement
        end

        return search
    end)
end

--- Заменить вхождения по очереди: первое — первым из списка, и так далее.
---
--- Так собирают строку с местами для подстановки: «между ? и ?».
--- Когда список кончился, оставшиеся вхождения остаются как были.
---@param text string
---@param search string
---@param replacements string[]
---@return string
function Module.replace_array(text, search, replacements)
    return substitute(guard.text(text), search, function(number)
        return replacements[number]
    end)
end

--- Выбросить подстроку; искать можно и по списку.
---@param text string
---@param search string|string[]
---@return string
function Module.remove(text, search)
    return Module.replace(text, search, '')
end

--- Обернуть строку: кавычками, скобками, тегом.
---@param text string
---@param before string
---@param after string|nil Умолчание — то же, чем начали
---@return string
function Module.wrap(text, before, after)
    return before .. guard.text(text) .. (after or before)
end

--- Снять обёртку, если она есть с обеих сторон.
---@param text string
---@param before string
---@param after string|nil
---@return string
function Module.unwrap(text, before, after)
    local tail = after or before
    local inner = chars.sub(guard.text(text), chars.len(before) + 1, -chars.len(tail) - 1)

    if before .. inner .. tail == text then
        return inner
    end

    return text
end

--- Добавить начало, если его ещё нет.
---@param text string
---@param prefix string
---@return string
function Module.start(text, prefix)
    if chars.locate(guard.text(text), prefix) == 1 then
        return text
    end

    return prefix .. text
end

--- Добавить конец, если его ещё нет.
---@param text string
---@param suffix string
---@return string
function Module.finish(text, suffix)
    if guard.text(text):sub(-#suffix) == suffix then
        return text
    end

    return text .. suffix
end

--- Сколько в строке слов; слово — это то, что отделено пробелами.
---@param text string
---@return integer
function Module.word_count(text)
    local total = 0
    local inside = false

    for _, piece in ipairs(chars.pieces(guard.text(text))) do
        if chars.is_space(piece.code) then
            inside = false
        elseif not inside then
            inside = true
            total = total + 1
        end
    end

    return total
end

--- Разложить слово, которое само длиннее строки, на куски по ширине.
---@param word string
---@param width number
---@return string[]
local function chopped(word, width)
    local parts = {}
    local current = {}
    local total = 0

    for _, piece in ipairs(chars.pieces(word)) do
        local step = chars.width_of(piece.code)

        -- Знак шире целой строки даёт пустой кусок перед собой: разрубить
        -- его нечем, а пустое слово сборщик строк потом просто пропустит.
        if total + step > width then
            table.insert(parts, table.concat(current))
            current = {}
            total = 0
        end

        total = total + step
        table.insert(current, piece.text)
    end

    table.insert(parts, table.concat(current))

    return parts
end

--- Слова строки вместе с длинными, разложенными на куски.
---@param line string
---@param width number
---@param cut_long boolean|nil
---@return string[]
local function wrappable(line, width, cut_long)
    local words = {}

    for word in line:gmatch('%S+') do
        if cut_long then
            -- Слово короче строки `chopped` отдаёт целиком, поэтому длину
            -- отдельно не спрашиваем: два одинаковых условия разошлись бы.
            for _, part in ipairs(chopped(word, width)) do
                table.insert(words, part)
            end
        else
            table.insert(words, word)
        end
    end

    return words
end

--- Перенести строку по словам.
---
--- Существующие переводы строк остаются переводами строк: текст, набранный
--- абзацами, не должен слипнуться в один. Слово длиннее ширины по умолчанию
--- вылезает за границу целиком — рубить слова посреди можно, но об этом
--- просят явно: `cut_long`.
---@param text string
---@param width number|nil Ширина в ячейках; умолчание — 75
---@param line_break string|nil Чем разделять строки; умолчание — перевод строки
---@param cut_long boolean|nil Рубить ли слова, которые сами длиннее строки
---@return string
function Module.word_wrap(text, width, line_break, cut_long)
    local limit = guard.positive(width or WRAP_WIDTH, 'ширина')
    local separator = line_break or NEWLINE
    local wrapped = {}

    for line in (guard.text(text) .. NEWLINE):gmatch('([^\n]*)\n') do
        local built = {}
        local current = ''

        for _, word in ipairs(wrappable(line, limit, cut_long)) do
            if current == '' then
                current = word
            elseif chars.width(current) + chars.width(word) < limit then
                current = current .. SPACE .. word
            else
                table.insert(built, current)
                current = word
            end
        end

        table.insert(built, current)
        table.insert(wrapped, table.concat(built, separator))
    end

    return table.concat(wrapped, separator)
end

return Module
