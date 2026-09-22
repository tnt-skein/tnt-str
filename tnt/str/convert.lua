--- Преобразование: строка во что-нибудь другое или в другой вид.
---
--- Здесь живёт `slug` — то, ради чего в пакете вообще появилась
--- транслитерация: адрес из заголовка на русском без неё пуст.
---
--- Разбиение (`split`, `lines`, `chunk`) отдаёт список, а не итератор:
--- список видно в отладчике целиком, его длину можно спросить, и он
--- не портится, если по нему пройти дважды. Строк, для которых это дорого,
--- в панели не бывает.

local chars = require('tnt.str.chars')
local case = require('tnt.str.case')
local edit = require('tnt.str.edit')
local guard = require('tnt.str.guard')
local russian = require('tnt.str.russian')

local Module = {}

--- Разделитель в адресах.
local HYPHEN = '-'

--- Слова, которые считаются согласием.
local TRUTHY = { ['1'] = true, ['true'] = true, ['on'] = true, ['yes'] = true, ['да'] = true }

--- Слова, которые считаются отказом; пустая строка тоже.
local FALSY = { [''] = true, ['0'] = true, ['false'] = true, ['off'] = true, ['no'] = true, ['нет'] = true }

--- Адрес из заголовка: «Список Узлов» → `spisok-uzlov`.
---
--- Всё, что не буква и не цифра латиницы, становится разделителем, а идущие
--- подряд разделители схлопываются в один: отдельной обрезки краёв
--- и схлопывания не нужно — их делает сама сборка из слов.
---@param text string
---@param separator string|nil Умолчание — дефис
---@return string
function Module.slug(text, separator)
    local latin = case.lower(russian.transliterate(guard.text(text)))
    local words = {}

    for word in latin:gmatch('%w+') do
        table.insert(words, word)
    end

    return table.concat(words, separator or HYPHEN)
end

--- Номер знака, с которого начинать: целый, отрицательный — с конца.
---
--- Номер считается с единицы, как в `string.sub` и `utf8`, а не с нуля:
--- разнобой в счёте внутри одного языка дороже чужой привычки. Ноль и всё,
--- что левее строки, значат первый знак — так же читает начало
--- `string.sub`, и `mask` с `position` расходиться с ним незачем.
---@param index any
---@param count integer Сколько знаков в строке
---@param name string Как назвать аргумент в отказе
---@return number
local function starting(index, count, name)
    return math.max(chars.absolute(guard.integer(index, name), count), 1)
end

--- Спрятать середину строки: «tay***@example.com».
---
--- Номер знака и длина — целые: дробный номер не указывает ни на какой
--- знак (см. `starting`).
---@param text string
---@param character string Чем закрывать
---@param index integer С какого знака прятать
---@param length integer|nil Сколько знаков спрятать; без него — до конца
---@return string
function Module.mask(text, character, index, length)
    guard.text(text)

    local count = chars.len(text)
    local start = starting(index, count, 'начало')
    local head = chars.first(text, start - 1)
    local tail = ''

    if length ~= nil then
        tail = chars.sub(text, start + guard.natural(length, 'длина'))
    end

    return head .. character:rep(count - chars.len(head) - chars.len(tail)) .. tail
end

--- Разрезать на куски по столько-то знаков.
---@param text string
---@param size integer Сколько знаков в куске
---@return string[]
function Module.chunk(text, size)
    guard.natural(size, 'размер куска')

    local parts = {}
    local current = {}

    for _, piece in ipairs(chars.pieces(guard.text(text))) do
        table.insert(current, piece.text)

        if #current == size then
            table.insert(parts, table.concat(current))
            current = {}
        end
    end

    if #current > 0 then
        table.insert(parts, table.concat(current))
    end

    return parts
end

--- Разбить по знакам; предел — как у `split`: последний кусок забирает
--- всё прочее.
---
--- Пустой разделитель поиск находит в каждом месте, поэтому знаки режет
--- `chunk`, а не цикл `split`. Остаток берётся одним срезом, а не склейкой
--- знаков по одному: при пределе, равном числу знаков, склейка и обход
--- дают один ответ, и сдвиг границы на единицу проверкой было бы
--- не поймать.
---@param text string
---@param limit integer|nil
---@return string[]
local function letters(text, limit)
    if limit == nil then
        return Module.chunk(text, 1)
    end

    local parts = Module.chunk(chars.first(text, limit - 1), 1)
    local rest = chars.sub(text, limit)

    if rest ~= '' then
        table.insert(parts, rest)
    end

    return parts
end

--- Разбить по разделителю.
---
--- Разделитель ищется дословно, а не шаблоном: строка `.` разделяет точки,
--- а не «любой знак». Шаблон здесь был бы ловушкой — разделители в настройках
--- пишут люди, и точка в них означает точку.
---@param text string
---@param separator string Пустой — разбить по знакам
---@param limit integer|nil Сколько кусков вернуть; в последнем остаётся всё прочее
---@return string[]
function Module.split(text, separator, limit)
    guard.text(text)

    if limit ~= nil then
        guard.natural(limit, 'число кусков')
    end

    if separator == '' then
        return letters(text, limit)
    end

    local parts = {}
    -- Начало непрочитанного — отрицательным отсчётом, то есть первым байтом
    -- любой строки, и пустой тоже: единицу и ноль поиск и срез читают
    -- одинаково, и мутант с нулём был бы неотличим.
    local from = -#text

    while limit == nil or #parts + 1 < limit do
        local at = text:find(separator, from, true)

        if at == nil then
            break
        end

        table.insert(parts, text:sub(from, at - 1))
        from = at + #separator
    end

    table.insert(parts, text:sub(from))

    return parts
end

--- Разбить на строки; годятся все три вида перевода строки.
---@param text string
---@return string[]
function Module.lines(text)
    local normalized = guard.text(text):gsub('\r\n', '\n'):gsub('\r', '\n')

    return Module.split(normalized, '\n')
end

--- Строка числом.
---@param text string
---@return number|nil
---@return string|nil err
function Module.to_number(text)
    local value = tonumber(edit.trim(guard.text(text)))

    if value == nil then
        return nil, ('«%s» — не число'):format(text)
    end

    return value
end

--- Строка признаком: «1», «true», «on», «yes», «да» и обратные им.
---
--- Незнакомое слово — отказ, а не ложь. Настройка `debug = 'нет'`,
--- молча ставшая ложью, и настройка `debug = 'ага'`, молча ставшая ложью
--- же, — разные беды, и вторую надо показать человеку.
---@param text string
---@return boolean|nil
---@return string|nil err
function Module.to_boolean(text)
    local word = case.lower(edit.trim(guard.text(text)))

    if TRUTHY[word] then
        return true
    end

    if FALSY[word] then
        return false
    end

    return nil, ('«%s» — не «да» и не «нет»'):format(text)
end

--- Сколько в строке знаков.
---@param text string
---@return integer
function Module.length(text)
    return chars.len(guard.text(text))
end

--- Ширина строки в ячейках терминала.
---@param text string
---@return integer
function Module.width(text)
    return chars.width(guard.text(text))
end

--- Номер знака, с которого начинается подстрока.
---
--- Начало поиска считается как номер знака у `mask` (см. `starting`).
---@param text string
---@param needle string
---@param offset integer|nil С какого знака искать; умолчание — с первого
---@return integer|nil
function Module.position(text, needle, offset)
    guard.text(text)

    ---@type number
    local start = 1

    if offset ~= nil then
        start = starting(offset, chars.len(text), 'начало поиска')
    end

    local head = chars.first(text, start - 1)
    local at = chars.locate(text:sub(#head + 1), needle)

    if at == nil then
        return nil
    end

    return chars.index_of(text, at + #head)
end

return Module
