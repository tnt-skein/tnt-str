--- Проверка аргументов: то, за что пакет роняет вызывающего.
---
--- Отказ парой `nil, err` возвращать здесь почти не из чего: у «перевернуть
--- строку» нет исхода «не вышло», и придумывать его значило бы заставить
--- прикладной код проверять то, что не случается. Зато есть ошибка
--- программиста — число вместо строки, бесконечная ширина, дробный счёт
--- знаков, пустой список форм, кусок нулевой длины, — и она обязана
--- обнаружиться там, где её написали.
---
--- Отказ всё же встречается, и там, где смысл у него есть: `to_number`
--- на «двенадцать», `between` без второй границы, `excerpt` без искомого.
--- Разница простая: пара — «так бывает», исключение — «так быть не должно».
---
--- Отказ бросается без места в коде, общим помощником `tnt-must`:
--- текст называет сам аргумент, а приписка «guard.lua:NN:» указала бы
--- внутрь пакета, где причины нет.

local fail = require('tnt.must.fail')

local raise = fail.raise

local Module = {}

--- Строка, иначе исключение.
---@param value any
---@param name string|nil Как назвать аргумент в сообщении
---@return string
function Module.text(value, name)
    if type(value) ~= 'string' then
        raise(('%s: нужна строка, а не %s'):format(name or 'значение', type(value)))
    end

    return value
end

--- Конечное число, иначе исключение.
---
--- Числом в пакете всюду служит счёт, ширина или номер знака, и ни NaN,
--- ни бесконечность ими не бывают, хотя тип у них `number`. Пропущенные,
--- они всплывают далеко от аргумента: бесконечный счёт доходит до `rep`
--- и кончается, смотря по сборке, нехваткой памяти или молча пустой
--- строкой, а NaN ложен в любом сравнении и проскакивает любую границу.
--- Значение в тексте называет `fail.show`: NaN сборки печатают
--- по-разному — «nan», «-nan», — а текст отказа должен быть один.
---@param value any
---@param name string Как назвать аргумент в сообщении
---@return number
function Module.number(value, name)
    if type(value) ~= 'number' then
        raise(('%s: нужно число, а не %s'):format(name, type(value)))
    end

    if value ~= value or math.abs(value) == math.huge then
        raise(('%s: нужно конечное число, а не %s'):format(name, fail.show(value)))
    end

    return value
end

--- Положительное конечное число, иначе исключение.
---
--- Нужно там, где ноль уводит в бесконечный цикл: кусок нулевой длины,
--- заполнитель нулевой ширины, строка шириной в ноль ячеек.
---@param value any
---@param name string
---@return number
function Module.positive(value, name)
    if Module.number(value, name) <= 0 then
        raise(('%s: нужно число больше нуля, а не %s'):format(name, value))
    end

    return value
end

--- Конечное целое число, иначе исключение.
---
--- Нужно там, где число — счёт знаков, слов или кусков либо номер знака.
--- Дробный номер не указывает ни на какой знак: пропущенный, он падал
--- арифметикой внутри среза, далеко от аргумента, а размер куска 2.5 молча
--- отдавал строку одним куском. Округлять за вызывающего значило бы прятать
--- ошибку так же, как раньше пряталась бесконечность: дробь приходит
--- оттуда, где посчитали не то. Согласованию с числом дробь нужна —
--- «1,5 узла», — и оно берёт `number`.
---@param value any
---@param name string
---@return integer
function Module.integer(value, name)
    if Module.number(value, name) ~= math.floor(value) then
        raise(('%s: нужно целое число, а не %s'):format(name, value))
    end

    return value
end

--- Целое число не меньше нуля, иначе исключение.
---
--- Для счёта, которому отрицательное не значит ничего: предел обрезки,
--- число слов, радиус окрестности. Отсчёт с конца понимают номер знака
--- у `mask` и счёт у `take`, а «минус три знака вокруг» — нет: такой
--- радиус резал текст бессмысленно, и вызов при этом не падал.
---@param value any
---@param name string
---@return integer
function Module.count(value, name)
    if Module.integer(value, name) < 0 then
        raise(('%s: нужно число не меньше нуля, а не %s'):format(name, value))
    end

    return value
end

--- Целое число больше нуля, иначе исключение.
---
--- Для счёта, у которого и ноль не значит ничего: размер куска, длина
--- спрятанного, число кусков разбиения. Текст отказа о нуле тот же, что
--- у `positive`: причина одна — пустого куска не бывает.
---@param value any
---@param name string
---@return integer
function Module.natural(value, name)
    Module.positive(Module.integer(value, name), name)

    return value
end

--- Три формы слова при числе, иначе исключение.
---
--- Проверяется весь список целиком: пропущенная третья форма выстрелит
--- на пяти узлах, а не на одном, — то есть не там и не тогда, где её забыли.
---@param forms any
---@return string[]
function Module.forms(forms)
    if type(forms) ~= 'table' then
        raise(
            ('формы слова: нужен список из трёх строк, а не %s'):format(type(forms))
        )
    end

    for index = 1, 3 do
        if type(forms[index]) ~= 'string' or forms[index] == '' then
            raise(
                ('формы слова: %d-я форма должна быть непустой строкой'):format(
                    index
                )
            )
        end
    end

    return forms
end

--- Список из значения: многие действия принимают и одну строку, и список.
---@param value any
---@return any[]
function Module.many(value)
    if type(value) == 'table' then
        return value
    end

    return { value }
end

return Module
