--- Строгая проверка формы JSON.
---
--- Своя, а не `json.decode` из Tarantool, и тому две причины. Пакет
--- не берёт ничего сверх встроенных `utf8`, `string`, `table` и `iconv`, —
--- это его главное свойство, и тянуть `json` ради одной проверки незачем. Вторая
--- важнее: cjson, на котором стоит `json.decode`, принимает то, чего в JSON
--- нет, — `nan`, `inf`, — а «это JSON» и «это разбирает наш разборщик» —
--- разные утверждения. Здесь проверяется первое, по RFC 8259.
---
--- Разбор ничего не строит. Он только идёт по строке и отвечает, где
--- кончилось разобранное: таблицы, которую тут же выбросят, не возникает,
--- и мегабайт чужого тела запроса не превращается в мегабайт таблиц.

local Module = {}

--- Докуда можно вкладывать одно в другое.
---
--- Предел нужен не от злого умысла, а от строки вида «[[[[[[…»: разбор
--- рекурсивный, и без предела такая строка кладёт стек интерпретатора
--- вместо того, чтобы получить ответ «не JSON».
local DEPTH = 64

--- Что бывает после обратной косой черты, кроме `\u`.
local ESCAPES = { ['"'] = true, ['\\'] = true, ['/'] = true, b = true, f = true, n = true, r = true, t = true }

--- Слова, которые в JSON значат сами себя.
local LITERALS = { 'true', 'false', 'null' }

--- Докуда дотянулся шаблон: где начинается то, что за ним.
---
--- Через `find`, а не через `match` с меткой позиции: `match` объявлен
--- возвращающим строку, и каждый разборщик пришлось бы приводить к числу.
---@param text string
---@param pattern string
---@param at integer
---@return integer|nil
local function upto(text, pattern, at)
    local _, stop = text:find(pattern, at)

    if stop == nil then
        return nil
    end

    return stop + 1
end

--- Пропустить пробельное; отвечает, где оно кончилось.
---@param text string
---@param at integer
---@return integer
local function skip(text, at)
    local index = upto(text, '^[ \t\n\r]*', at)
    -- Шаблон из одних необязательных знаков совпадает всегда, поэтому
    -- метка позиции есть непременно.
    ---@cast index integer

    return index
end

--- Строка в кавычках.
---@param text string
---@param at integer
---@return integer|nil Где строка кончилась
local function scan_string(text, at)
    if text:sub(at, at) ~= '"' then
        return nil
    end

    local index = at + 1

    while true do
        local sign = text:sub(index, index)

        if sign == '' then
            return nil
        end

        if sign == '"' then
            return index + 1
        end

        if sign ~= '\\' then
            -- Управляющий знак в строке JSON пишется только через escape:
            -- перевод строки внутри кавычек — это уже не JSON.
            if sign < ' ' then
                return nil
            end

            index = index + 1
        else
            local escape = text:sub(index + 1, index + 1)

            if escape == 'u' then
                -- Конец escape'а берётся у самого шаблона, а не отсчитывается
                -- от начала: длина «\uXXXX» написана бы дважды — здесь
                -- и в шаблоне, — и разошлась бы при первой же правке.
                local after = upto(text, '^%x%x%x%x', index + 2)

                if after == nil then
                    return nil
                end

                index = after
            elseif ESCAPES[escape] then
                index = index + 2
            else
                return nil
            end
        end
    end
end

--- Число.
---
--- В JSON число строже, чем в Lua: ни ведущего нуля («01»), ни точки без
--- цифры перед ней («.5»), ни плюса впереди, ни шестнадцатеричной записи.
---@param text string
---@param at integer
---@return integer|nil
local function scan_number(text, at)
    -- Ноль стоит вторым: он и только он бывает ведущим, и попытка
    -- разобрать «01» как число обязана кончиться на первой же цифре.
    local index = upto(text, '^%-?[1-9]%d*', at) or upto(text, '^%-?0', at)

    if index == nil then
        return nil
    end

    index = upto(text, '^%.%d+', index) or index

    return upto(text, '^[eE][%+%-]?%d+', index) or index
end

--- Слово: true, false или null.
---@param text string
---@param at integer
---@return integer|nil
local function scan_literal(text, at)
    for _, word in ipairs(LITERALS) do
        if text:sub(at, at + #word - 1) == word then
            return at + #word
        end
    end

    return nil
end

---@type fun(text: string, at: integer, depth: integer): integer|nil
local scan_value

--- Перечисление до закрывающего знака: список или пары «ключ — значение».
---@param text string
---@param at integer
---@param closing string Каким знаком кончается перечисление
---@param keyed boolean Ждать ли перед каждым значением ключ с двоеточием
---@param depth integer
---@return integer|nil
local function scan_items(text, at, closing, keyed, depth)
    local index = skip(text, at)

    if text:sub(index, index) == closing then
        return index + 1
    end

    while true do
        if keyed then
            local after_key = scan_string(text, index)

            if after_key == nil then
                return nil
            end

            index = skip(text, after_key)

            if text:sub(index, index) ~= ':' then
                return nil
            end

            index = index + 1
        end

        local after_value = scan_value(text, index, depth)

        if after_value == nil then
            return nil
        end

        index = skip(text, after_value)
        local sign = text:sub(index, index)

        if sign == closing then
            return index + 1
        end

        -- Висящая запятая — не JSON: «[1,]» отвергается, как и «{}» с ней.
        if sign ~= ',' then
            return nil
        end

        index = skip(text, index + 1)
    end
end

--- Одно значение: докуда оно тянется.
---@param text string
---@param at integer
---@param depth integer
---@return integer|nil
function scan_value(text, at, depth)
    if depth > DEPTH then
        return nil
    end

    local index = skip(text, at)
    local sign = text:sub(index, index)

    if sign == '{' then
        return scan_items(text, index + 1, '}', true, depth + 1)
    end

    if sign == '[' then
        return scan_items(text, index + 1, ']', false, depth + 1)
    end

    if sign == '"' then
        return scan_string(text, index)
    end

    return scan_number(text, index) or scan_literal(text, index)
end

--- Правильный ли это JSON целиком.
---@param text string
---@return boolean
function Module.valid(text)
    -- Разбор начинается с первого байта — отрицательным отсчётом, то есть
    -- с начала любой строки, и пустой тоже: единицу и ноль поиск читает
    -- одинаково, и мутант с нулём был бы неотличим, — и с первого уровня
    -- вложенности.
    local index = scan_value(text, -#text, 1)

    if index == nil then
        return false
    end

    return skip(text, index) == #text + 1
end

return Module
