--- Проверки: то, что отвечает «да» или «нет».
---
--- Все они ищут байтами: ответ «да или нет» от способа счёта не зависит,
--- а байтовый поиск идёт в C. Исключение — сравнение без учёта регистра:
--- там обе строки сперва приводятся к нижнему регистру через ICU, потому
--- что «Ё» и «ё» — разные байты, и никакой байтовый приём их не сблизит.
---
--- `is_match` берёт **шаблон Lua**, а не регулярное выражение: `%d+`,
--- а не `\d+`. Регулярных выражений в Tarantool нет, а тащить их ради
--- одной проверки — значит завести пакету зависимость, которой у него нет.
--- Там, где хватает звёздочки, есть `is`: `is(name, 'storage-*')`.

local utf8 = require('utf8')

local chars = require('tnt.str.chars')
local guard = require('tnt.str.guard')
local json = require('tnt.str.json')

local Module = {}

--- Схемы ссылок, которые считаются ссылками без лишних слов.
---
--- Список, а не «любая схема»: `javascript:alert(1)` — тоже ссылка
--- по RFC 3986, и пропустить её в разметку панели значит отдать панель.
local DEFAULT_SCHEMES = { 'http', 'https' }

--- Знаки, у которых в шаблоне Lua особое значение.
local MAGIC = '[%^%$%(%)%%%.%[%]%*%+%-%?]'

--- UUID в каноническом виде: 8-4-4-4-12 шестнадцатеричных знаков.
local UUID_PATTERN = '^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$'

--- Ссылка: схема, разделитель и весь остаток строки.
---
--- Образец кончается на `://` нарочно. Прежний `[^/?#%s]+%S*$` ставил рядом
--- два жадных повтора, и на строке, которая ему не подходит, откат перебирал
--- все их дележи: «http://» со ста тысячами букв и пробелом на конце считался
--- на 3.8 четырнадцать секунд в одном файбере и без единой уступки. Строка
--- сюда приходит откуда угодно, так что столько же стоил бы один запрос.
--- Остаток теперь смотрят два поиска, каждый за один проход, и те же сто
--- тысяч знаков получают ответ за полмиллисекунды.
local URL_PATTERN = '^(%a[%w%+%-%.]*)://(.*)$'

--- Узел: за разделителем должен стоять хоть один знак, и не тот, с которого
--- начинаются путь, запрос или якорь. Пустой остаток не совпадёт тоже —
--- `https://` ссылкой не считается.
local URL_HOST_PATTERN = '^[^/?#]'

--- Пробельный знак: в ссылке его не бывает нигде.
local SPACE_PATTERN = '%s'

--- Байты, которых в ASCII нет.
local NOT_ASCII = '[\128-\255]'

--- Строка, приведённая к нижнему регистру, если регистр не важен.
---@param text string
---@param ignore_case boolean|nil
---@return string
local function folded(text, ignore_case)
    if ignore_case then
        return utf8.lower(text)
    end

    return text
end

--- Есть ли в строке хоть одна из подстрок.
---@param text string
---@param needles string|string[]
---@param ignore_case boolean|nil
---@return boolean
function Module.contains(text, needles, ignore_case)
    local haystack = folded(guard.text(text), ignore_case)

    for _, needle in ipairs(guard.many(needles)) do
        if chars.locate(haystack, folded(needle, ignore_case)) ~= nil then
            return true
        end
    end

    return false
end

--- Есть ли в строке все перечисленные подстроки.
---@param text string
---@param needles string|string[]
---@param ignore_case boolean|nil
---@return boolean
function Module.contains_all(text, needles, ignore_case)
    local haystack = folded(guard.text(text), ignore_case)

    for _, needle in ipairs(guard.many(needles)) do
        if chars.locate(haystack, folded(needle, ignore_case)) == nil then
            return false
        end
    end

    return true
end

--- Совпадает ли край строки с одной из подстрок.
---@param text string
---@param needles string|string[]
---@param ignore_case boolean|nil
---@param edge fun(haystack: string, piece: string): string Край нужной длины
---@return boolean
local function has_edge(text, needles, ignore_case, edge)
    local haystack = folded(guard.text(text), ignore_case)

    for _, needle in ipairs(guard.many(needles)) do
        local piece = folded(needle, ignore_case)

        -- Пустая подстрока есть в начале и в конце любой строки; отвечать
        -- «да» на неё значит незаметно пропустить пустую настройку.
        if piece ~= '' and edge(haystack, piece) == piece then
            return true
        end
    end

    return false
end

--- Начинается ли строка с одной из подстрок.
---@param text string
---@param needles string|string[]
---@param ignore_case boolean|nil
---@return boolean
function Module.starts_with(text, needles, ignore_case)
    return has_edge(text, needles, ignore_case, function(haystack, piece)
        return chars.before_offset(haystack, #piece + 1)
    end)
end

--- Кончается ли строка одной из подстрок.
---@param text string
---@param needles string|string[]
---@param ignore_case boolean|nil
---@return boolean
function Module.ends_with(text, needles, ignore_case)
    return has_edge(text, needles, ignore_case, function(haystack, piece)
        return haystack:sub(-#piece)
    end)
end

--- Подходит ли строка под образец со звёздочкой: `is(name, 'storage-*')`.
---
--- Звёздочка — единственный особый знак образца; всё прочее сравнивается
--- дословно, включая точки и дефисы. Так образец, написанный человеком
--- в настройках, не превращается в регулярное выражение с неожиданностями.
---@param text string
---@param pattern string
---@param ignore_case boolean|nil
---@return boolean
function Module.is(text, pattern, ignore_case)
    local subject = folded(guard.text(text), ignore_case)
    local mask = folded(guard.text(pattern, 'образец'), ignore_case)
    local escaped = mask:gsub(MAGIC, '%%%0'):gsub('%%%*', '.*')

    return subject:find('^' .. escaped .. '$') ~= nil
end

--- Подходит ли строка под шаблон Lua.
---@param text string
---@param pattern string Шаблон Lua, а не регулярное выражение
---@return boolean
function Module.is_match(text, pattern)
    return guard.text(text):find(guard.text(pattern, 'шаблон')) ~= nil
end

--- Пусто ли: пустая строка или ничего.
---
--- Принимает и `nil` намеренно: чаще всего так проверяют поле, которого
--- в присланных данных могло не быть вовсе.
---@param text string|nil
---@return boolean
function Module.is_empty(text)
    return text == nil or text == ''
end

--- Только ли из ASCII состоит строка.
---@param text string
---@return boolean
function Module.is_ascii(text)
    return guard.text(text):find(NOT_ASCII) == nil
end

--- Правильный ли это JSON.
---@param text string
---@return boolean
function Module.is_json(text)
    return json.valid(guard.text(text))
end

--- Есть ли у ссылки узел и нет ли в ней пробелов.
---@param rest string Всё, что идёт после `://`
---@return boolean
local function addressed(rest)
    return rest:find(URL_HOST_PATTERN) ~= nil and rest:find(SPACE_PATTERN) == nil
end

--- Похоже ли на ссылку, схема которой разрешена.
---@param text string
---@param schemes string[]|nil Умолчание — только http и https
---@return boolean
function Module.is_url(text, schemes)
    local scheme, rest = guard.text(text):match(URL_PATTERN)

    if scheme == nil then
        return false
    end

    -- Остаток есть всегда, когда есть схема: обе скобки одного образца.
    local tail = rest --[[@as string]]

    if not addressed(tail) then
        return false
    end

    for _, allowed in ipairs(schemes or DEFAULT_SCHEMES) do
        if scheme:lower() == allowed then
            return true
        end
    end

    return false
end

--- UUID ли это в каноническом виде.
---@param text string
---@return boolean
function Module.is_uuid(text)
    return guard.text(text):match(UUID_PATTERN) ~= nil
end

return Module
