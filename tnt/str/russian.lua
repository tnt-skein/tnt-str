--- Русский язык: транслитерация и согласование слова с числом.
---
--- Готовых средств для того и другого нет: строковые библиотеки считают
--- морфологию английской, где «1 node» и «5 nodes» разбираются одним
--- правилом. У нас без этих двух вещей пакет бесполезен:
--- `slug('Список узлов')` без транслитерации пуст, а панель
--- без согласования пишет «5 узел».
---
--- ## Какая транслитерация
---
--- Практическая, близкая к BGN/PCGN: `ж → zh`, `х → kh`, `ц → ts`,
--- `ч → ch`, `ш → sh`, `щ → shch`, `ю → yu`, `я → ya`, `ё → yo`, `й → y`,
--- твёрдый и мягкий знаки опускаются. «Список узлов» → `spisok-uzlov`,
--- «Яндекс» → `yandeks`.
---
--- Выбрана она, а не государственная, потому что нужна читаемость адреса,
--- а не соответствие паспорту:
---
--- - **ИКАО** (Doc 9303, загранпаспорт) даёт `я → ia`, `ю → iu`, `й → i`:
---   «Юрия» превращается в `iuriia`, и прочесть это обратно уже нельзя.
--- - **ГОСТ 7.79-2000, система Б** даёт `ц → cz`, `щ → shh`, `й → j`:
---   «Цех» → `czex`. Однозначно, но не для человека.
---
--- Транслитерация необратима: `ё` и `йо` дают одно и то же `yo`. Обратного
--- перевода здесь нет и не будет — адрес не источник, а ссылка на него.
---
--- ## Согласование с числом
---
--- Три формы и одна ловушка: одиннадцать–четырнадцать не слушаются
--- последней цифры («11 узлов», а не «11 узел»). Дробное число всегда берёт
--- вторую форму: «1,5 узла», «0,5 узла».

local utf8 = require('utf8')

local case = require('tnt.str.case')
local chars = require('tnt.str.chars')
local guard = require('tnt.str.guard')

local Module = {}

--- Первый знак, который уже не ASCII.
local ASCII_LIMIT = 0x80

--- Кириллица латиницей; ключи — строчные, прописные выводятся из них.
---
--- Кроме русских букв тут украинские и белорусская «ў»: имена узлов
--- и заголовки приходят и с ними, а знак без перевода просто исчез бы
--- из адреса, склеив соседние слова.
local TRANSLIT = {
    ['а'] = 'a',
    ['б'] = 'b',
    ['в'] = 'v',
    ['г'] = 'g',
    ['д'] = 'd',
    ['е'] = 'e',
    ['ё'] = 'yo',
    ['ж'] = 'zh',
    ['з'] = 'z',
    ['и'] = 'i',
    ['й'] = 'y',
    ['к'] = 'k',
    ['л'] = 'l',
    ['м'] = 'm',
    ['н'] = 'n',
    ['о'] = 'o',
    ['п'] = 'p',
    ['р'] = 'r',
    ['с'] = 's',
    ['т'] = 't',
    ['у'] = 'u',
    ['ф'] = 'f',
    ['х'] = 'kh',
    ['ц'] = 'ts',
    ['ч'] = 'ch',
    ['ш'] = 'sh',
    ['щ'] = 'shch',
    ['ъ'] = '',
    ['ы'] = 'y',
    ['ь'] = '',
    ['э'] = 'e',
    ['ю'] = 'yu',
    ['я'] = 'ya',
    ['і'] = 'i',
    ['ї'] = 'yi',
    ['є'] = 'ye',
    ['ґ'] = 'g',
    ['ў'] = 'u',
}

--- Прописная ли буква у знака; за краем строки знака нет.
---@param piece { text: string, code: integer|nil }|nil
---@return boolean
local function shouted(piece)
    return piece ~= nil and piece.code ~= nil and utf8.isupper(piece.code)
end

--- Латиница для одного знака.
---
--- Регистр переносится с исходной буквы. Внутри сплошного куска прописных
--- («ЖУК») замена целиком прописная, иначе только первая буква: «Жук» →
--- `Zhuk`, а не `ZHuk`, и «ЖУК» → `ZHUK`, а не `ZhUK`.
---@param piece { text: string, code: integer|nil }
---@param previous { text: string, code: integer|nil }|nil
---@param following { text: string, code: integer|nil }|nil
---@param unknown string|nil Чем заменять то, для чего перевода нет
---@return string
local function converted(piece, previous, following, unknown)
    if piece.code ~= nil and piece.code < ASCII_LIMIT then
        return piece.text
    end

    local latin = TRANSLIT[utf8.lower(piece.text)]

    if latin == nil then
        return unknown or ''
    end

    if not shouted(piece) then
        return latin
    end

    if shouted(previous) or shouted(following) then
        return latin:upper()
    end

    return case.ucfirst(latin)
end

--- Кириллица латиницей.
---@param text string
---@param unknown string|nil Чем заменять знаки, которым перевода нет; умолчание — пусто
---@return string
function Module.transliterate(text, unknown)
    local pieces = chars.pieces(guard.text(text))
    local latin = {}

    for index, piece in ipairs(pieces) do
        table.insert(latin, converted(piece, pieces[index - 1], pieces[index + 1], unknown))
    end

    return table.concat(latin)
end

--- Остатки от сотни, которые не слушаются последней цифры: «11 узлов»,
--- а не «11 узел». Это не исключение, а само правило: в этом десятке
--- названия чисел кончаются на «-надцать», и счётная форма общая.
---
--- Множеством, а не диапазоном `11 <= x <= 14`: у границ сдвиг к десяти
--- и к пятнадцати ничего не менял — ноль и пятёрка и так берут третью
--- форму, — и мутанты границ были неотличимы. Сдвиг ключа множества
--- не добавляет соседа, а выбивает своё число, и это видно. Остаток сюда
--- приходит только целый: дробное уходит раньше.
local TEENS = { [11] = true, [12] = true, [13] = true, [14] = true }

--- Последние цифры, при которых берётся вторая форма: «2 узла», «4 узла».
--- Множеством по той же причине: единицу в «2-4» сдвигом нижней границы
--- было не втянуть — её забирает проверка раньше.
local FEW = { [2] = true, [3] = true, [4] = true }

--- Какая из трёх форм слова подходит числу.
---@param count number
---@return integer 1 — «узел», 2 — «узла», 3 — «узлов»
function Module.plural_form(count)
    guard.number(count, 'число')

    -- Дробное берёт вторую форму независимо от цифр: «1,5 узла»,
    -- «0,5 узла», «2,5 узла». Правило последней цифры к дробям неприменимо.
    if count ~= math.floor(count) then
        return 2
    end

    local number = math.abs(count)
    local tens = number % 100

    if TEENS[tens] then
        return 3
    end

    local ones = number % 10

    if ones == 1 then
        return 1
    end

    if FEW[ones] then
        return 2
    end

    return 3
end

--- Форма слова при числе: `plural(5, { 'узел', 'узла', 'узлов' })` → «узлов».
---@param count number
---@param forms string[] Формы при одном, при двух и при пяти
---@return string
function Module.plural(count, forms)
    -- Номер формы всегда от одного до трёх, а все три проверены: значение
    -- под этим номером есть непременно.
    local form = guard.forms(forms)[Module.plural_form(count)]
    ---@cast form string

    return form
end

--- Число вместе с согласованным словом: «5 узлов».
---@param count number
---@param forms string[]
---@return string
function Module.counted(count, forms)
    return ('%s %s'):format(count, Module.plural(count, forms))
end

return Module
