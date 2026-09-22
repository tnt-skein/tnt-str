--- Перекодировка: cp1251 и прочее в UTF-8 и обратно.
---
--- Выгрузки в Excel и письма из Windows приходят в cp1251, а весь пакет
--- считает строку UTF-8. Такой текст через него проходит, но толку мало:
--- каждый байт не из UTF-8 считается знаком длиной в байт, так что длина
--- сходится случайно, `upper` возвращает слово как было, а `slug` пуст.
--- Перекодировать надо на входе, и здесь это делается встроенным
--- `iconv` — без своих таблиц.
---
--- Отказ — пара `nil, err`: битый файл и незнакомая кодировка в заголовке
--- письма — случаи из жизни, а не ошибка программиста. Ядро же на всё
--- отвечает исключением, и причины в нём подписаны наоборот (см. `TRUNCATED`);
--- сюда наружу выходит только русская причина.
---
--- Суффиксы `//TRANSLIT` и `//IGNORE` не принимаются. Проверено на 3.8:
--- пока жив конвертер с `//IGNORE`, соседний конвертер той же пары
--- кодировок начинает молча терять знаки — `a日b` превращается в `a`,
--- без отказа. Один такой конвертер в приложении портил бы все остальные.

local iconv = require('iconv')
local utf8 = require('utf8')

local guard = require('tnt.str.guard')

local Module = {}

--- Конвертер ядра: cdata, которое зовётся как функция.
---@alias TntStrConverter fun(text: string): string

--- Кодировка, в которой живёт весь остальной пакет.
local UTF8 = 'UTF-8'

--- Что ядро говорит про оборванный на середине знака текст.
---
--- В `iconv(3)` это `EINVAL`, и ядро подписывает его «Invalid multibyte
--- sequence», а `EILSEQ` — негодную последовательность и знак, которого
--- в кодировке нет, — «Incomplete multibyte sequence». То есть ровно
--- наоборот; проверено по исходнику `builtin/iconv.lua` в 3.8. Впереди
--- ядро приписывает место в своём файле, поэтому сверяется хвост.
local TRUNCATED = 'Invalid multibyte sequence'

--- Отказ на оборванный текст; пишется с именем кодировки.
local CUT_SHORT = 'текст в кодировке %s обрывается посреди знака'

--- Отказ на суффикс в имени кодировки.
local SUFFIXES = 'суффиксы //TRANSLIT и //IGNORE не принимаются'

--- Отказы на то, чего в кодировке нет: у каждого направления свой,
--- потому что на входе это байты чужого файла, а на выходе — знаки текста.
local NO_SUCH_BYTES = 'в тексте есть байты не из кодировки %s'
local NO_SUCH_CHARACTER = 'в тексте есть знак, которого нет в кодировке %s'

--- Конвертер из одной кодировки в другую либо причина, почему его нет.
---
--- Ядро принимает и пустое имя — оно значит «кодировка локали», то есть
--- скрытую настройку машины, — и суффиксы `//TRANSLIT`/`//IGNORE`,
--- которые портят соседние конвертеры (см. шапку). И то и другое
--- отвергается здесь, до ядра.
---@param to string
---@param from string
---@param encoding string Та из двух кодировок, что назвал вызывающий
---@return TntStrConverter|nil
---@return string|nil err
local function open(to, from, encoding)
    if encoding == '' then
        return nil, 'кодировка не названа'
    end

    if encoding:match('//') ~= nil then
        return nil, ('кодировка «%s»: %s'):format(encoding, SUFFIXES)
    end

    local ok, converter = pcall(iconv.new, to, from)

    if not ok then
        return nil, ('кодировка «%s» неизвестна'):format(encoding)
    end

    -- Аннотация ядра описывает конвертер классом без `__call`, хотя
    -- зовётся он именно как функция; напрямую в функцию класс не приводится.
    ---@cast converter any

    return converter
end

--- Прогнать текст через конвертер; отказ ядра — парой с русской причиной.
---
--- Причин у ядра две: текст оборван посреди знака либо в нём есть то,
--- чего в кодировке нет. Нехватку места в буфере ядро закрывает само,
--- а других `errno` у `iconv(3)` не бывает.
---@param converter TntStrConverter
---@param text string
---@param encoding string
---@param illegal string Причина для второго случая: у каждого направления своя
---@return string|nil
---@return string|nil err
local function convert(converter, text, encoding, illegal)
    local ok, result = pcall(converter, text)

    if ok then
        return result
    end

    if result:sub(-#TRUNCATED) == TRUNCATED then
        return nil, CUT_SHORT:format(encoding)
    end

    return nil, illegal
end

--- Текст из чужой кодировки в UTF-8: `decode(bytes, 'cp1251')`.
---
--- Имя кодировки — как у `iconv --list`, регистр не важен: `cp1251`,
--- `windows-1251`, `koi8-r`, `cp866`, `utf-16le`.
---@param text string
---@param encoding string
---@return string|nil
---@return string|nil err
function Module.decode(text, encoding)
    guard.text(text)
    guard.text(encoding, 'кодировка')

    local converter, err = open(UTF8, encoding, encoding)

    if converter == nil then
        return nil, err
    end

    return convert(converter, text, encoding, NO_SUCH_BYTES:format(encoding))
end

--- Текст из UTF-8 в чужую кодировку: `encode(text, 'cp1251')`.
---
--- Годность UTF-8 проверяется до ядра: у ядра негодный байт и знак,
--- которого в кодировке нет, — одна и та же причина, а различить их
--- вызывающему нужно, потому что чинятся они в разных местах.
---@param text string
---@param encoding string
---@return string|nil
---@return string|nil err
function Module.encode(text, encoding)
    guard.text(text)
    guard.text(encoding, 'кодировка')

    local counted, position = utf8.len(text)

    if counted == nil then
        return nil, ('байт %d — не UTF-8'):format(position)
    end

    local converter, err = open(encoding, UTF8, encoding)

    if converter == nil then
        return nil, err
    end

    return convert(converter, text, encoding, NO_SUCH_CHARACTER:format(encoding))
end

return Module
