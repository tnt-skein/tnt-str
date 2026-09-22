--- Вырезка: взять от строки кусок и не разрубить при этом букву.
---
--- Всё, что меряется числом, меряется знаками: «обрезать до 20» — это
--- двадцать букв, а не двадцать байтов, иначе «Список узлов» обрывается
--- посреди «л» и ломает разбор JSON у того, кому ответ уедет.
---
--- Границы (`before`, `after`) ищутся байтами и возвращают исходную строку,
--- когда границы в ней нет. Так удобнее в цепочке:
--- `of(path):after_last('/')` работает и на пути без косой черты. Там, где
--- молчаливого ответа быть не должно — `between` без второй границы,
--- `excerpt` без искомого, — возвращается пара `nil, err`: выдумать кусок
--- между границами, которых нет, нельзя, а отдать вместо него всю строку
--- значит соврать.

local chars = require('tnt.str.chars')
local edit = require('tnt.str.edit')
local guard = require('tnt.str.guard')

local Module = {}

--- Многоточие: один знак, а не три точки.
---
--- Три точки в узком столбце панели съедают место, отведённое под сам
--- текст. Здесь «…»: выглядит так же, а места занимает втрое меньше.
local ELLIPSIS = '…'

--- Сколько знаков вокруг найденного показывает `excerpt` по умолчанию.
local RADIUS = 100

--- Обрезать до числа знаков; если обрезали — добавить окончание.
---
--- Окончание добавляется сверх предела, а не внутрь него: предел считает
--- текст, а многоточие — знак обрезки. Строка на выходе длиннее предела
--- ровно на длину окончания.
---@param text string
---@param count integer Сколько знаков оставить
---@param ending string|nil Умолчание — многоточие
---@return string
function Module.limit(text, count, ending)
    guard.count(count, 'предел')

    if chars.len(guard.text(text)) <= count then
        return text
    end

    return chars.first(text, count) .. (ending or ELLIPSIS)
end

--- Обрезать до числа слов, не разрывая последнее.
---@param text string
---@param count integer Сколько слов оставить
---@param ending string|nil Умолчание — многоточие
---@return string
function Module.words(text, count, ending)
    guard.count(count, 'число слов')

    local taken = 0
    local inside = false

    for from, _, code in chars.walk(guard.text(text)) do
        if chars.is_space(code) then
            inside = false
        elseif not inside then
            inside = true
            taken = taken + 1

            if taken > count then
                return edit.rtrim(chars.before_offset(text, from)) .. (ending or ELLIPSIS)
            end
        end
    end

    return text
end

--- Кусок строки по одну сторону от вхождения.
---@param text string
---@param search string
---@param last boolean Считать от последнего вхождения, а не от первого
---@param tail boolean Нужен кусок после вхождения, а не до него
---@return string
local function sliced(text, search, last, tail)
    local at = chars.locate(guard.text(text), search, last)

    if at == nil then
        return text
    end

    if tail then
        return text:sub(at + #search)
    end

    return chars.before_offset(text, at)
end

--- До первого вхождения.
---@param text string
---@param search string
---@return string
function Module.before(text, search)
    return sliced(text, search, false, false)
end

--- До последнего вхождения.
---@param text string
---@param search string
---@return string
function Module.before_last(text, search)
    return sliced(text, search, true, false)
end

--- После первого вхождения.
---@param text string
---@param search string
---@return string
function Module.after(text, search)
    return sliced(text, search, false, true)
end

--- После последнего вхождения.
---@param text string
---@param search string
---@return string
function Module.after_last(text, search)
    return sliced(text, search, true, true)
end

--- Кусок между двумя границами.
---@param text string
---@param from string Начальная граница; берётся первая
---@param to string Конечная граница
---@param last boolean Брать последнюю конечную границу, а не первую
---@return string|nil
---@return string|nil err
local function carved(text, from, to, last)
    local opened = chars.locate(guard.text(text), from)

    if opened == nil then
        return nil, ('в тексте нет начала «%s»'):format(from)
    end

    local rest = text:sub(opened + #from)
    local closed = chars.locate(rest, to, last)

    if closed == nil then
        return nil, ('в тексте нет конца «%s» после начала «%s»'):format(to, from)
    end

    return chars.before_offset(rest, closed)
end

--- Между первой начальной границей и последней конечной.
---@param text string
---@param from string
---@param to string
---@return string|nil
---@return string|nil err
function Module.between(text, from, to)
    return carved(text, from, to, true)
end

--- Между первой начальной границей и первой же конечной: самый короткий кусок.
---@param text string
---@param from string
---@param to string
---@return string|nil
---@return string|nil err
function Module.between_first(text, from, to)
    return carved(text, from, to, false)
end

--- Взять знаки с начала строки; отрицательное число — с конца.
---@param text string
---@param count integer
---@return string
function Module.take(text, count)
    guard.text(text)
    guard.integer(count, 'число знаков')

    if count < 0 then
        return chars.sub(text, count)
    end

    return chars.first(text, count)
end

--- Окрестность найденного: искомое и по столько-то знаков вокруг.
---
--- Тем и полезно в выдаче поиска: показать, в каком месте текста нашлось,
--- не показывая текст целиком. Отрезанное с краёв отмечается многоточием,
--- а не отрезанное — нет, поэтому по виду ответа видно, где текст кончился.
---
--- Радиус — сколько знаков показать с каждой стороны, целое не меньше
--- нуля; при нуле от текста остаётся одно искомое, а отрезанное
--- по-прежнему отмечено.
---@param text string
---@param phrase string Что искать; ищется дословно, с учётом регистра
---@param opts { radius: integer|nil, omission: string|nil }|nil
---@return string|nil
---@return string|nil err
function Module.excerpt(text, phrase, opts)
    local settings = opts or {}
    local radius = guard.count(settings.radius or RADIUS, 'радиус')
    local omission = settings.omission or ELLIPSIS

    local at = chars.locate(guard.text(text), phrase)

    if at == nil then
        return nil, ('в тексте нет подстроки «%s»'):format(phrase)
    end

    local head = chars.before_offset(text, at)
    local tail = text:sub(at + #phrase)
    local near = edit.ltrim(head)

    -- Левая сторона — последние `radius` знаков, и начало среза считается
    -- от длины, а не отсчётом `-radius` с конца: минус ноль — это ноль,
    -- а ноль в срезе значит «с первого знака», и нулевой радиус показывал
    -- левую сторону целиком.
    local left = edit.ltrim(chars.sub(near, chars.len(near) - radius + 1))
    local right = edit.rtrim(chars.first(edit.rtrim(tail), radius))

    if left ~= head then
        left = omission .. left
    end

    if right ~= tail then
        right = right .. omission
    end

    return left .. phrase .. right
end

return Module
