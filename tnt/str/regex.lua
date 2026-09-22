--- Регулярные выражения: то, чего шаблонам Lua не хватает.
---
--- В шаблонах Lua нет ни чередования `a|b`, ни счётчика `{n,m}`, ни группы
--- с повтором, и всё это расписывается руками: UUID — тридцать два `%x`
--- подряд, почтовый адрес — образец и три отдельные проверки рядом с ним.
--- Здесь — PCRE2 через рок `lrexlib-pcre2` (модуль `rex_pcre2`).
---
--- Зависимость необязательная. Без рока весь остальной пакет работает
--- как прежде, `available()` отвечает «нет», а само действие роняет
--- вызов: регулярное выражение пишет программист, и звать его на узле
--- без движка — ошибка сборки узла, а не случай из жизни.
---
--- Выражение — из кода, строка — откуда угодно. Выражение, пришедшее
--- снаружи (фильтр из запроса, поле настроек), сюда отдавать нельзя, и
--- шаблонам Lua его отдавать нельзя тоже. Проверено на 3.8: `(a+)+$`
--- на тридцати знаках упирается в предел PCRE2 за 0,07 с и роняет вызов,
--- а шаблон Lua `^a*a*a*a*a*a*a*b` на шестидесяти знаках считает шесть
--- секунд без единой уступки — предела у него нет вовсе, и узел стоит.
--- Разница между движками не в том, вешает ли выражение узел, а в том,
--- что PCRE2 об этом говорит, а шаблон Lua — нет.
---
--- Строка — UTF-8, и выражение видит знаки, а не байты: `.` — одна буква
--- «ж», `\w`, `\d` и `(?i)` знают кириллицу. Строка не в UTF-8 — отказ
--- парой: сверять байты со знаками нельзя.
---
--- `$` — строгий конец строки, как в шаблонах Lua, а не «конец либо перед
--- последним переводом строки», как в Perl: `^\d+$` не пропускает «12\n».
--- С `(?m)` `$` снова значит конец каждой строки — так и просили.
---
--- Движок спрашивается на каждом вызове, а не запоминается при загрузке:
--- внешняя зависимость подменяет его в проверках, а запомненный движок подмены бы не
--- заметил. Стоит это одного обращения к `package.loaded`.

local utf8 = require('utf8')

local external = require('tnt.external')

local guard = require('tnt.str.guard')

--- Ошибка программиста: сообщение без места вызова, как у всего пакета.
---
--- Бросает общий помощник `tnt-must`: уровни ноль и минус единица
--- у `error` в Lua значат одно и то же, и неотличимый мутант уровня
--- стоит на одной его строке, а не в каждом пакете. Текст либо чужое
--- значение ошибки идёт как есть.
local fail = require('tnt.must.fail').raise

local Module = {}

--- Модуль рока: `lrexlib-pcre2` кладёт его под этим именем.
local LIBRARY = 'rex_pcre2'

--- Средства снаружи: подключение рока.
local DEFAULTS = {
    load = function(name)
        return pcall(require, name)
    end,
}

local source = external.install(Module, DEFAULTS)

--- Флаги компиляции по движку: UTF-8, знание Unicode и строгий `$`.
---
--- Считаются один раз на движок: `flags()` собирает таблицу на полторы
--- сотни записей при каждом вызове. Ключ слабый, чтобы подменённый
--- в проверках движок не жил здесь вечно.
---@type table<table, number>
local OPTIONS = setmetatable({}, { __mode = 'k' })

--- Движок либо `nil`, если рок не поставлен.
---@return table|nil
local function engine()
    local ok, library = source().load(LIBRARY)

    if not ok then
        return nil
    end

    return library
end

--- Движок, иначе исключение: узел собран без него.
---@return table
local function demand()
    local library = engine()

    if library == nil then
        fail(
            'регулярные выражения недоступны: поставьте рок lrexlib-pcre2 (модуль rex_pcre2)'
        )
    end

    return library --[[@as table]]
end

--- Флаги компиляции для движка.
---@param library table
---@return number
local function options(library)
    local known = OPTIONS[library]

    if known == nil then
        local flags = library.flags()

        known = flags.UTF + flags.UCP + flags.DOLLAR_ENDONLY
        OPTIONS[library] = known
    end

    return known
end

--- Скомпилированное выражение; негодное — исключение с причиной от PCRE2.
---
--- Негодное выражение — ошибка программиста: выражения пишутся в коде,
--- и такое обязано упасть там, где его написали, а не вернуться парой
--- вместе с настоящими отказами по строке.
---@param library table
---@param pattern string
---@return any
local function compile(library, pattern)
    local ok, compiled = pcall(library.new, pattern, options(library))

    if not ok then
        fail(('регулярное выражение «%s» негодно: %s'):format(pattern, tostring(compiled)))
    end

    return compiled
end

--- Аргумент в UTF-8 либо отказ.
---@param text string
---@return string|nil
---@return string|nil err
local function encoded(text)
    local counted, position = utf8.len(text)

    if counted == nil then
        return nil, ('байт %d — не UTF-8'):format(position)
    end

    return text
end

--- Ответ движка; отказ движка на ходу — исключение с выражением в тексте.
---
--- На ходу PCRE2 отказывает одним: выражение с вложенными повторами
--- не уложилось в предел шагов на этой строке (`PCRE2_ERROR_MATCHLIMIT`).
--- Это плохое выражение, а не плохая строка, и чинят его в коде, — поэтому
--- исключение, а не пара. Чужая ошибка — из функции замены — идёт как есть.
---@param pattern string
---@param action function
---@param ... any
---@return any ...
local function outcome(pattern, action, ...)
    local results = { pcall(action, ...) }

    if not results[1] then
        local err = results[2]

        if type(err) == 'string' and err:match('PCRE2') ~= nil then
            fail(
                ('регулярное выражение «%s» не справилось со строкой: %s'):format(
                    pattern,
                    err
                )
            )
        end

        fail(err)
    end

    return unpack(results, 2, table.maxn(results))
end

--- Всё, что нужно действию: движок, выражение и строка в UTF-8.
---
--- Порядок проверок — от ошибок программиста к отказу по данным: не строка
--- вместо строки, узел без движка и негодное выражение роняют вызов, и
--- только строка не в UTF-8 возвращается парой.
---@param text any
---@param pattern any
---@return table|nil library
---@return any compiled
---@return string|nil err
local function prepare(text, pattern)
    guard.text(text)
    guard.text(pattern, 'выражение')

    local library = demand()
    local compiled = compile(library, pattern)
    local ready, err = encoded(text)

    if ready == nil then
        return nil, nil, err
    end

    return library, compiled
end

--- Есть ли движок: поставлен ли рок `lrexlib-pcre2`.
---@return boolean
function Module.available()
    return engine() ~= nil
end

--- Подходит ли строка под выражение: `regex_is('storage-001', '^\\w+-\\d{3}$')`.
---@param text string
---@param pattern string Регулярное выражение PCRE2
---@return boolean|nil
---@return string|nil err
function Module.is(text, pattern)
    local _, compiled, err = prepare(text, pattern)

    if compiled == nil then
        return nil, err
    end

    return outcome(pattern, compiled.find, compiled, text) ~= nil
end

--- Первое совпадение: захваты, а без них — совпадение целиком.
---
--- Как `string.match`: нет совпадения — `nil`, захват, не участвовавший
--- в совпадении, — `false`.
---@param text string
---@param pattern string Регулярное выражение PCRE2
---@return any ...
function Module.match(text, pattern)
    local _, compiled, err = prepare(text, pattern)

    if compiled == nil then
        return nil, err
    end

    return outcome(pattern, compiled.match, compiled, text)
end

--- Все совпадения списком.
---
--- Каждое — то, что отдало бы `string.gmatch` за один шаг: совпадение
--- целиком, единственный захват либо список захватов, когда их несколько.
---@param text string
---@param pattern string Регулярное выражение PCRE2
---@return any[]|nil
---@return string|nil err
function Module.match_all(text, pattern)
    local library, compiled, err = prepare(text, pattern)

    if library == nil then
        return nil, err
    end

    -- Отказ движка случается на шаге, а не при сборке обхода: оборачивается
    -- каждый шаг.
    local step = library.gmatch(text, compiled)
    local found = {}

    while true do
        ---@type any[]
        local captures = { outcome(pattern, step) }

        if captures[1] == nil then
            return found
        end

        if #captures == 1 then
            table.insert(found, captures[1])
        else
            table.insert(found, captures)
        end
    end
end

--- Заменить все совпадения.
---
--- Замена — как у `string.gsub`: строка с `%1` и `%0`, функция от захватов
--- либо таблица по первому захвату; `nil` из функции оставляет совпадение
--- как было. Ответ — только строка: число замен цепочке ни к чему.
---@param text string
---@param pattern string Регулярное выражение PCRE2
---@param replacement string|function|table
---@return string|nil
---@return string|nil err
function Module.replace(text, pattern, replacement)
    local kind = type(replacement)

    if kind ~= 'string' and kind ~= 'function' and kind ~= 'table' then
        fail(('замена: нужна строка, функция или таблица, а не %s'):format(kind))
    end

    local library, compiled, err = prepare(text, pattern)

    if library == nil then
        return nil, err
    end

    return (outcome(pattern, library.gsub, text, compiled, replacement))
end

--- Разбить по выражению: `regex_split('a, b ,c', '\\s*,\\s*')`.
---
--- Кусков всегда на один больше, чем разделителей: пустая строка — один
--- пустой кусок, разделитель в конце — пустой кусок за ним.
---@param text string
---@param pattern string Регулярное выражение PCRE2
---@return string[]|nil
---@return string|nil err
function Module.split(text, pattern)
    local library, compiled, err = prepare(text, pattern)

    if library == nil then
        return nil, err
    end

    local step = library.split(text, compiled)
    local pieces = {}

    while true do
        local piece = outcome(pattern, step)

        if piece == nil then
            return pieces
        end

        table.insert(pieces, piece)
    end
end

return Module
