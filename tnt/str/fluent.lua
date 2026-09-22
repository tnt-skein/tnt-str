--- Цепочка: `str.of('  Список Узлов '):trim():slug()`.
---
--- Ради неё пакет и затевался. Одно и то же преобразование, записанное
--- вызовами, читается задом наперёд — `slug(trim(lower(text)))`, — и чем
--- больше шагов, тем хуже. Цепочка читается по порядку.
---
--- Действия в цепочке те же самые, что у фасада: обёртка не знает о них
--- ничего, кроме имени, и получает список при сборке. Новое действие
--- фасада попадает в цепочку само — расходиться им негде.
---
--- Строка продолжает цепочку, всё прочее из неё выходит: `:length()` отдаёт
--- число, `:contains('уз')` — истину, `:split(',')` — список, и продолжать
--- цепочку после них нечем. Отказ выходит парой, как везде: `:to_number()`
--- вернёт `nil` и причину.
---
--- Опечатка в имени действия роняет вызов на месте: `:trimm()` — это
--- «у строки нет такого действия», а не тихий `nil`, который уедет дальше
--- и всплывёт через три слоя в виде «attempt to index a nil value».
---
--- Чего цепочка не умеет: `#` на ней возвращает ноль. Метаметод `__len`
--- у обёртки есть, но LuaJIT, на котором работает Tarantool, зовёт его
--- только для userdata, а для таблиц молча берёт длину массивной части.
--- Длину строки надо спрашивать `:length()` — она и правильнее, потому
--- что считает знаки, а не байты.

local chars = require('tnt.str.chars')
local guard = require('tnt.str.guard')
local raise = require('tnt.must.fail').raise

local Module = {}

--- Ключ, под которым в обёртке лежит сама строка.
---
--- Таблица, а не имя: с именем поле обёртки однажды совпало бы с именем
--- действия, и `of(x).value` означало бы то одно, то другое.
local VALUE = {}

---@class TntStrFluent
---@field value fun(self: TntStrFluent): string Сама строка

--- Собирает `of` по таблице действий.
---@param actions table<string, function> Что умеет фасад
---@return fun(text: string): TntStrFluent
function Module.factory(actions)
    local meta = {}

    ---@param text string
    ---@return TntStrFluent
    local function of(text)
        return setmetatable({ [VALUE] = guard.text(text) }, meta)
    end

    --- Что делать с ответом действия: строка продолжает цепочку,
    --- всё прочее из неё выходит как есть, вместе с причиной отказа.
    local function outcome(first, second)
        if type(first) == 'string' then
            return of(first)
        end

        return first, second
    end

    meta.__index = function(self, key)
        if key == 'value' then
            return function()
                return rawget(self, VALUE)
            end
        end

        local action = actions[key]

        if action == nil then
            raise(('у строки нет такого действия: %s'):format(tostring(key)))
        end

        return function(_, ...)
            return outcome(action(rawget(self, VALUE), ...))
        end
    end

    meta.__tostring = function(self)
        return rawget(self, VALUE)
    end

    meta.__concat = function(left, right)
        return tostring(left) .. tostring(right)
    end

    -- LuaJIT зовёт его только для userdata; для таблицы `#` вернёт ноль.
    -- Метаметод всё равно объявлен: он верный, и там, где его зовут
    -- (Lua 5.2 и дальше), ответ будет правильным — по знакам, а не байтам.
    meta.__len = function(self)
        return chars.len(rawget(self, VALUE))
    end

    meta.__eq = function(left, right)
        return rawget(left, VALUE) == rawget(right, VALUE)
    end

    return of
end

return Module
