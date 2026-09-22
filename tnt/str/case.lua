--- Регистр и разбиение на слова.
---
--- Смена регистра целиком отдана `utf8` Tarantool: он на ICU, знает про «ё»,
--- про «ß» (в верхнем регистре — «SS», то есть строка удлиняется) и про
--- письменности, где регистра нет вовсе. Таблица соответствий, написанная
--- руками, врала бы на первом же не русском слове.
---
--- Своего здесь одно — разбиение на слова, и оно общее для всех именований.
--- Слово кончается там, где кончились буквы и цифры, и там, где строчная
--- сменилась прописной: «списокУзлов» — два слова, «HTTPСервер» — тоже два.
--- Из-за этого `snake('Список Узлов')` даёт `список_узлов`, а не транслит:
--- перевод в латиницу — дело `slug`, а не именований.
---
--- Что делать с битым байтом, решает ICU: на 3.8 `upper` возвращает
--- негодный байт как был. Своего мнения на этот счёт у пакета нет.

local utf8 = require('utf8')

local chars = require('tnt.str.chars')
local guard = require('tnt.str.guard')

local Module = {}

--- Разделитель слов в `snake` по умолчанию.
local UNDERSCORE = '_'

--- Разделитель слов в `kebab`: он же разделитель в адресах.
local HYPHEN = '-'

--- Буква или цифра: из них состоит слово, всё прочее их разделяет.
---@param code integer|nil
---@return boolean
local function wordy(code)
    return code ~= nil and (utf8.isalpha(code) or utf8.isdigit(code))
end

--- Прописная ли буква.
---@param code integer|nil
---@return boolean
local function capital(code)
    return code ~= nil and utf8.isupper(code)
end

--- Начинается ли на этом знаке новое слово.
---
--- Спрашивается на каждой букве, в том числе на первой в слове: там ответ
--- «да» ничего не меняет — слово и так только начинается, а сбрасывать
--- из накопленного нечего.
---
--- Поводов два. Строчная сменилась прописной — «списокУзлов». Или прописная
--- стоит перед строчной, а до неё была прописная — «HTTPСервер»: сокращение
--- кончилось, началось слово. Без второго правила «HTTPСервер» превратился
--- бы в одно слово `httpсервер`, а не в `http_сервер`.
---@param mark { text: string, code: integer|nil }
---@param previous integer|nil Код предыдущего знака
---@param following { text: string, code: integer|nil }|nil
---@return boolean
local function boundary(mark, previous, following)
    local capitalized = capital(mark.code)

    -- Строчная слова не начинает, прописная после строчной — начинает всегда:
    -- в обоих случаях ответ — сама прописность знака. Отдельная ложь на первый
    -- случай была бы неотличима от пустоты: ответ идёт только в условие.
    if not capitalized or not capital(previous) then
        return capitalized
    end

    return following ~= nil and wordy(following.code) and not capital(following.code)
end

--- Слова строки.
---@param text string
---@return string[]
function Module.words_of(text)
    local marks = chars.pieces(guard.text(text))
    local words = {}
    local current = {}
    ---@type integer|nil
    local previous = nil

    local function flush()
        if #current > 0 then
            table.insert(words, table.concat(current))
            current = {}
        end
    end

    for index, mark in ipairs(marks) do
        if not wordy(mark.code) then
            flush()
        else
            if boundary(mark, previous, marks[index + 1]) then
                flush()
            end

            table.insert(current, mark.text)
        end

        previous = mark.code
    end

    flush()

    return words
end

--- Слова, переделанные по одному и склеенные разделителем.
---@param text string
---@param separator string
---@param transform fun(word: string): string
---@return string
local function joined(text, separator, transform)
    local pieces = {}

    for _, word in ipairs(Module.words_of(text)) do
        table.insert(pieces, transform(word))
    end

    return table.concat(pieces, separator)
end

--- В верхний регистр.
---@param text string
---@return string
function Module.upper(text)
    return utf8.upper(guard.text(text))
end

--- В нижний регистр.
---@param text string
---@return string
function Module.lower(text)
    return utf8.lower(guard.text(text))
end

--- Первый знак — прописным, остальные как были.
---@param text string
---@return string
function Module.ucfirst(text)
    return Module.upper(chars.at(guard.text(text), 1)) .. chars.sub(text, 2)
end

--- Первый знак — строчным, остальные как были.
---@param text string
---@return string
function Module.lcfirst(text)
    return Module.lower(chars.at(guard.text(text), 1)) .. chars.sub(text, 2)
end

--- Слово с прописной буквы, остальное строчными.
---@param word string
---@return string
local function capitalized(word)
    return Module.ucfirst(Module.lower(word))
end

--- Знак с перевёрнутым регистром; не буква остаётся собой.
---@param piece { text: string, code: integer|nil }
---@return string
local function swapped(piece)
    if piece.code == nil then
        return piece.text
    end

    if utf8.isupper(piece.code) then
        return utf8.lower(piece.text)
    end

    return utf8.upper(piece.text)
end

--- Перевернуть регистр каждой буквы: «Узел» → «уЗЕЛ».
---
--- Замена по словарю к этому имени отношения не имеет: она зовётся
--- `replace` со списком.
---@param text string
---@return string
function Module.swap(text)
    local pieces = {}

    for _, piece in ipairs(chars.pieces(guard.text(text))) do
        table.insert(pieces, swapped(piece))
    end

    return table.concat(pieces)
end

--- Знак заголовка: первая буква сплошного куска — прописной, прочие строчными.
---@param piece { text: string, code: integer|nil }
---@param first boolean Начало ли это куска букв
---@return string
local function titled(piece, first)
    if piece.code == nil then
        return piece.text
    end

    if first then
        return utf8.upper(piece.text)
    end

    return utf8.lower(piece.text)
end

--- СлитноСПрописных: «список узлов» → «СписокУзлов».
---@param text string
---@return string
function Module.studly(text)
    return joined(text, '', capitalized)
end

--- То же самое; имя из мира, где этот вид зовут паскалевским.
---@param text string
---@return string
function Module.pascal(text)
    return Module.studly(text)
end

--- слитноСоВторогоСлова: «список узлов» → «списокУзлов».
---@param text string
---@return string
function Module.camel(text)
    return Module.lcfirst(Module.studly(text))
end

--- через_подчёркивание.
---@param text string
---@param separator string|nil Умолчание — подчёркивание
---@return string
function Module.snake(text, separator)
    return joined(text, separator or UNDERSCORE, Module.lower)
end

--- через-дефис.
---@param text string
---@return string
function Module.kebab(text)
    return Module.snake(text, HYPHEN)
end

--- Каждое Слово С Прописной, знаки препинания на месте.
---
--- В отличие от `headline`, здесь строка не разбирается на слова: пробелы,
--- запятые и дефисы остаются такими, какими были. Прописной становится
--- первая буква каждого сплошного куска букв.
---@param text string
---@return string
function Module.title(text)
    local pieces = {}
    local previous = false

    for _, piece in ipairs(chars.pieces(guard.text(text))) do
        local letter = piece.code ~= nil and utf8.isalpha(piece.code)

        table.insert(pieces, titled(piece, letter and not previous))

        previous = letter
    end

    return table.concat(pieces)
end

--- Заголовок из именования: «список_узлов» и «списокУзлов» → «Список Узлов».
---@param text string
---@return string
function Module.headline(text)
    return joined(text, ' ', capitalized)
end

return Module
