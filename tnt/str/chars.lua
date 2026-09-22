--- Знаки вместо байтов.
---
--- Строка в Lua — это байты, и вся стандартная библиотека считает байты:
--- `#'Узел'` равно восьми, `('Кластер'):sub(1, 3)` разрубает букву пополам,
--- `('Узел'):upper()` оставляет строку как была. На латинице этого не видно,
--- на кириллице — каждый раз.
---
--- Здесь собрано то, чего во встроенном `utf8` Tarantool нет: обход строки
--- по знакам, срез по номерам знаков, переворот, ширина при выводе. Всё
--- остальное (`len`, `sub`, `upper`, `lower`, `isalpha`) берётся у него —
--- он на ICU и знает про регистр больше, чем любая таблица, которую можно
--- написать здесь руками.
---
--- Где пакет работает байтами, а где знаками.
---
--- **Байтами** — поиск подстроки, замена, разбиение по разделителю. UTF-8
--- самосинхронизирующийся: байты продолжения не могут начать знак, поэтому
--- поиск правильной подстроки не совпадёт с серединой буквы. Это ещё
--- и быстрее: поиск идёт в C, а не шагами по знакам.
---
--- **Знаками** — всё, где число знаков видно снаружи: длина, срез, обрезка,
--- дополнение до ширины, переворот, разбиение на слова, обрезка пробелов.
--- Байтовый счёт дал бы здесь обрубок буквы, а его уже не склеить.
---
--- Битые байты не теряются. `utf8.next` на негодной последовательности
--- молчит — возвращает nil и посреди строки, и на её конце, — так что обход
--- по нему потерял бы весь остаток строки. Здесь такой байт считается
--- знаком длиной в байт: текст в чужой кодировке пройдёт через пакет
--- покорёженным, но целым.
---
--- Знак — это кодовая точка, а не то, что видит глаз. «й» из «и» и краткой
--- сверху — два знака, эмодзи с цветом кожи — два-три. Пакет их не склеивает:
--- склейка требует таблиц Unicode, которых в Tarantool нет.

local utf8 = require('utf8')

local Module = {}

--- Пробельные знаки, которые снимает обрезка.
---
--- Неразрывный пробел U+00A0 — тот, ради кого список и заведён. Он приезжает
--- из текста, набранного человеком, выглядит ровно как пробел, а шаблон `%s`
--- его не видит: в UTF-8 это два байта, и ни один из них не пробельный.
--- Строка «Узел\194\160» после байтовой обрезки остаётся с хвостом,
--- и сравнение с «Узел» не совпадает — искать такое потом дорого.
local SPACES = {
    [0x09] = true, -- табуляция
    [0x0A] = true, -- перевод строки
    [0x0B] = true, -- вертикальная табуляция
    [0x0C] = true, -- подача страницы
    [0x0D] = true, -- возврат каретки
    [0x20] = true, -- пробел
    [0x85] = true, -- следующая строка
    [0xA0] = true, -- неразрывный пробел
    [0x1680] = true, -- огамический пробел
    [0x2028] = true, -- разделитель строк
    [0x2029] = true, -- разделитель абзацев
    [0x202F] = true, -- узкий неразрывный пробел
    [0x205F] = true, -- средний математический пробел
    [0x3000] = true, -- идеографический пробел
    [0xFEFF] = true, -- неразрывный пробел нулевой ширины, он же метка порядка байтов
}

-- Пробелы наборщика: от круглой шпации до волосяного пробела.
for code = 0x2000, 0x200A do
    SPACES[code] = true
end

--- Знаки нулевой ширины: они ложатся на соседний знак, своей ячейки не занимая.
local ZERO_WIDTH = {
    { 0x0300, 0x036F }, -- объединяемая диакритика
    { 0x0483, 0x0489 }, -- славянские надстрочные знаки и титло
    { 0x200B, 0x200F }, -- нулевой пробел и метки направления письма
    { 0x20D0, 0x20F0 }, -- объединяемые знаки для символов
    { 0xFE00, 0xFE0F }, -- селекторы начертания
}

--- Знаки в две ячейки: восточноазиатские письменности и эмодзи.
local WIDE = {
    { 0x1100, 0x115F }, -- корейские чамо
    { 0x2E80, 0x303E }, -- ключи и знаки препинания CJK
    { 0x3041, 0x33FF }, -- каны и составные знаки
    { 0x3400, 0x4DBF }, -- иероглифы, расширение A
    { 0x4E00, 0x9FFF }, -- иероглифы, основной блок
    { 0xA000, 0xA4CF }, -- слоговое письмо и
    { 0xAC00, 0xD7A3 }, -- корейские слоги
    { 0xF900, 0xFAFF }, -- совместимые иероглифы
    { 0xFE30, 0xFE6F }, -- вертикальные и малые формы
    { 0xFF00, 0xFF60 }, -- полноширинные формы
    { 0xFFE0, 0xFFE6 }, -- полноширинные знаки валют
    { 0x1F300, 0x1F64F }, -- эмодзи
    { 0x1F900, 0x1F9FF }, -- эмодзи, дополнение
    { 0x20000, 0x3FFFD }, -- иероглифы, расширения B и дальше
}

--- Попадает ли знак в один из отрезков.
---
--- Ответ — `true` либо ничего: он идёт только в условие, а явная ложь
--- в конце ничем не отличалась бы от пустоты, и проверить её было бы нечем.
---@param code integer
---@param ranges integer[][]
---@return true|nil
local function within(code, ranges)
    for _, range in ipairs(ranges) do
        if code >= range[1] and code <= range[2] then
            return true
        end
    end
end

--- Обход строки по знакам.
---
--- На каждом шаге отдаёт границы знака в байтах и его кодовую точку;
--- у битого байта кодовой точки нет, и вместо неё приходит nil.
---@param text string
---@return fun(): integer|nil, integer|nil, integer|nil
function Module.walk(text)
    local from = 1
    local length = #text

    return function()
        if from > length then
            return nil
        end

        local start = from
        -- Битый байт: `utf8.next` о нём молчит, и без запасного шага
        -- обход оборвался бы на нём, потеряв весь остаток строки. Шаг
        -- в один байт отмеряет образец, а не сложение: у `start + 1`
        -- мутанты, оставлявшие шаг на месте, зацикливали обход, и обход,
        -- копивший знаки, съедал память так, что падал сам luatest.
        local following, code = utf8.next(text, start)
        from = following or text:match('^.()', start)

        return start, from - 1, code
    end
end

--- Сколько в строке знаков.
---@param text string
---@return integer
function Module.len(text)
    local count = 0

    for _ in Module.walk(text) do
        count = count + 1
    end

    return count
end

--- Байтовые смещения начал знаков; последним — смещение за концом строки.
---
--- Нужны там, где срез берут сразу по двум номерам: пройти строку один раз
--- дешевле, чем дважды искать смещение шагами.
---@param text string
---@return integer[]
function Module.offsets(text)
    local marks = {}

    for from in Module.walk(text) do
        table.insert(marks, from)
    end

    table.insert(marks, #text + 1)

    return marks
end

--- Знаки строки: сам знак и его кодовая точка.
---
--- Так строку читают почти все, кому нужны знаки: обрезка смотрит на код
--- (пробельный ли), а собирает ответ из самих знаков. Собирать это заново
--- в каждом модуле значит трижды написать один и тот же цикл.
---@param text string
---@return { text: string, code: integer|nil }[]
function Module.pieces(text)
    local list = {}

    for from, to, code in Module.walk(text) do
        table.insert(list, { text = text:sub(from, to), code = code })
    end

    return list
end

--- Где в строке вхождение подстроки: первое или последнее.
---
--- Ищется байтами, и это не небрежность: в UTF-8 байты продолжения знака
--- не могут начать другой знак, поэтому вхождение правильной подстроки
--- не совпадёт с серединой буквы. Поиск при этом идёт в C, а не шагами
--- по знакам, и разница на длинном тексте заметная.
---
--- Пустую подстроку не ищем: `find` находит её в любом месте, и всё, что
--- на этом построено, начинает вести себя необъяснимо.
---
--- Конец вхождения не возвращается: подстрока ищется дословно, и её конец
--- вычисляется из начала и длины самой подстроки. Второе возвращаемое
--- значение здесь только сбивало бы с толку в местах, где оно не нужно.
---@param text string
---@param search string
---@param last boolean|nil Искать последнее вхождение, а не первое
---@return integer|nil at Начало вхождения в байтах
function Module.locate(text, search, last)
    if search == '' then
        return nil
    end

    -- Начало поиска — умолчание, а не число: единица и ноль значат здесь
    -- одно, и мутант с нулём был бы неотличим.
    local at = text:find(search, nil, true)

    while last and at ~= nil do
        local following = text:find(search, at + 1, true)

        if following == nil then
            break
        end

        at = following
    end

    return at
end

--- Положительный номер знака: отрицательный считается с конца строки.
---@param index number
---@param count number Сколько знаков в строке
---@return number
function Module.absolute(index, count)
    if index < 0 then
        return count + index + 1
    end

    return index
end

--- Срез по номерам знаков; правила те же, что у `string.sub`.
---@param text string
---@param from number|nil Умолчание — первый знак
---@param to number|nil Умолчание — последний знак
---@return string
function Module.sub(text, from, to)
    local marks = Module.offsets(text)
    local count = #marks - 1

    ---@type number
    local first = 1
    ---@type number
    local last = count

    if from ~= nil then
        first = math.max(Module.absolute(from, count), 1)
    end

    if to ~= nil then
        last = math.min(Module.absolute(to, count), count)
    end

    if first > last then
        return ''
    end

    -- Границы уже уложены в размер строки, значит смещения на месте:
    -- в списке их на одно больше, чем знаков.
    local opened = marks[first]
    local closed = marks[last + 1]
    ---@cast opened integer
    ---@cast closed integer

    return text:sub(opened, closed - 1)
end

--- Первые сколько-то знаков.
---
--- Начало не называется числом, а оставляется умолчанием: «с первого
--- знака» и «с начала» — это одно и то же, и писать это дважды незачем.
---@param text string
---@param count number
---@return string
function Module.first(text, count)
    return Module.sub(text, nil, count)
end

--- Байты до названного места, не включая его.
---
--- Байтовый срез, а не знаковый: место сюда приходит от поиска, который
--- ищет байтами, и переводить его в номер знака только затем, чтобы
--- отрезать по нему же, значит пройти строку лишний раз.
---@param text string
---@param offset integer Байтовое смещение, до которого берём
---@return string
function Module.before_offset(text, offset)
    local last = offset - 1

    -- Начало среза — отрицательным отсчётом, то есть первым байтом любой
    -- строки, и пустой тоже: у `sub(1, last)` мутанты `0` и `1-1` дают
    -- ту же строку, а у `-#text` единственный мутант не проходит загрузку.
    return text:sub(-#text, last)
end

--- Один знак под названным номером.
---@param text string
---@param index number
---@return string
function Module.at(text, index)
    return Module.sub(text, index, index)
end

--- Номер знака по байтовому смещению.
---
--- Поиск идёт байтами, а отвечать надо знаками: `position`, вернувший 5 там,
--- где знаков три, не годится ни для среза, ни для показа человеку.
---
--- Смещение, попавшее внутрь знака, относится к следующему за ним: внутрь
--- знака попадает только смещение из битой строки, и выбор там между
--- «ближайший следующий» и «отказ» — в пользу первого.
---@param text string
---@param offset number
---@return integer
function Module.index_of(text, offset)
    local index = 1

    for from in Module.walk(text) do
        if from >= offset then
            return index
        end

        index = index + 1
    end

    return index
end

--- Строка задом наперёд, по знакам.
---@param text string
---@return string
function Module.reverse(text)
    local pieces = {}

    for from, to in Module.walk(text) do
        table.insert(pieces, 1, text:sub(from, to))
    end

    return table.concat(pieces)
end

--- Пробельный ли это знак.
---@param code integer|nil
---@return boolean
function Module.is_space(code)
    return SPACES[code] == true
end

--- Ширина знака в ячейках терминала.
---@param code integer|nil nil — битый байт
---@return integer
function Module.width_of(code)
    if code == nil then
        return 1
    end

    if within(code, ZERO_WIDTH) then
        return 0
    end

    if within(code, WIDE) then
        return 2
    end

    return 1
end

--- Ширина строки в ячейках терминала.
---
--- Знак не равен ячейке: иероглиф занимает две, диакритика — ноль. Считать
--- по знакам столбцы таблицы значит получить рваную правую границу там,
--- где в данных встретился не латинский текст.
---@param text string
---@return integer
function Module.width(text)
    local total = 0

    for _, _, code in Module.walk(text) do
        total = total + Module.width_of(code)
    end

    return total
end

return Module
