--- Общие средства тестов пакета строк.
---
--- Исходники грузятся с диска, а не через `require`: у Tarantool свой
--- загрузчик `.rocks`, он идёт раньше `package.path` и подсунул бы
--- установленную копию пакета, если она есть. Проверки тогда шли бы
--- против вчерашнего кода, а покрытие считалось бы по нему. Поэтому
--- файлы читаются сами, в порядке зависимостей, и кладутся
--- в `package.loaded` под именами модулей: `require` изнутри пакета
--- находит их первыми. Зависимости — `tnt.must.fail` и `tnt.external` —
--- берутся установленными из `.rocks`: они не этого пакета, и покрытие
--- по ним не считается.

local fio = require('fio')

local helper = {}

--- Модули пакета в порядке зависимостей.
helper.MODULES = {
    { name = 'tnt.str.chars', path = 'tnt/str/chars.lua' },
    { name = 'tnt.str.guard', path = 'tnt/str/guard.lua' },
    { name = 'tnt.str.json', path = 'tnt/str/json.lua' },
    { name = 'tnt.str.case', path = 'tnt/str/case.lua' },
    { name = 'tnt.str.edit', path = 'tnt/str/edit.lua' },
    { name = 'tnt.str.cut', path = 'tnt/str/cut.lua' },
    { name = 'tnt.str.checks', path = 'tnt/str/checks.lua' },
    { name = 'tnt.str.russian', path = 'tnt/str/russian.lua' },
    { name = 'tnt.str.convert', path = 'tnt/str/convert.lua' },
    { name = 'tnt.str.encoding', path = 'tnt/str/encoding.lua' },
    { name = 'tnt.str.regex', path = 'tnt/str/regex.lua' },
    { name = 'tnt.str.fluent', path = 'tnt/str/fluent.lua' },
    { name = 'tnt.str', path = 'tnt/str.lua' },
}

--- Части пакета из последней загрузки этого помощника.
---@type table<string, any>
local parts = {}

--- Собирает фасад пакета из исходников заново и запоминает его части.
---@return any str
function helper.load()
    for _, module in ipairs(helper.MODULES) do
        local chunk, failure = loadfile(fio.abspath(module.path))

        if chunk == nil then
            error(('исходник %s не читается: %s'):format(module.name, tostring(failure)))
        end

        local value = chunk()

        -- Пустое значение в `package.loaded` для `require` значит «не загружен»,
        -- и следующий модуль списка молча взял бы зависимость из `.rocks`.
        if value == nil then
            error(('исходник %s не вернул модуль'):format(module.name))
        end

        package.loaded[module.name] = value
        parts[module.name] = value
    end

    helper.str = parts['tnt.str']

    return helper.str
end

--- Фасад пакета, собранный из исходников.
---
--- Грузится один раз на файл проверок, а не перед каждой проверкой: своего
--- состояния у пакета нет — ни настроек, ни подменяемых средств, — и
--- перезагружать его незачем. А вот цена перезагрузки заметная:
--- мутационный прогон гоняет набор тысячи раз.
helper.load()

--- Отдельный модуль пакета из той же загрузки, что и фасад.
---@param name string
---@return any
function helper.part(name)
    local part = parts[name]

    if part == nil then
        error(('модуль %s не из пакета tnt-str'):format(name))
    end

    return part
end

--- Неразрывный пробел: из-за него в пакете и заведён свой список пробельных.
helper.NBSP = '\194\160'

--- Три формы слова — то, чем проверяется согласование с числом.
helper.FORMS = { 'узел', 'узла', 'узлов' }

--- Флаги двойника движка регулярных выражений: числа свои, важна только
--- их сумма в компиляции.
helper.FAKE_REGEX_FLAGS = { UTF = 1, UCP = 2, DOLLAR_ENDONLY = 4, CASELESS = 8 }

--- Двойник движка регулярных выражений: вызовы `rex_pcre2` поверх
--- шаблонов Lua.
---
--- Им проверяется обвязка — аргументы, порядок проверок, вид ответа, — а не
--- PCRE2: сам движок проверяется живыми проверками с настоящим роком.
---@param seen table Сюда пишется, с чем звали `new` и сколько раз спрашивали флаги
---@param failure string|nil Текст, которым отказывает каждый шаг движка
---@return table engine
function helper.fake_regex_engine(seen, failure)
    local engine = {}

    local function step(action)
        if failure ~= nil then
            error(failure, 0)
        end

        return action()
    end

    local methods = {}

    function methods:find(subject)
        return step(function()
            return subject:find(self.pattern)
        end)
    end

    function methods:match(subject)
        return step(function()
            return subject:match(self.pattern)
        end)
    end

    function engine.flags()
        seen.flags_asked = (seen.flags_asked or 0) + 1

        return helper.FAKE_REGEX_FLAGS
    end

    function engine.new(pattern, options)
        seen.pattern = pattern
        seen.options = options

        -- Негодный шаблон — исключение, как у настоящего движка.
        local ok, err = pcall(string.find, '', pattern)

        if not ok then
            error(err, 0)
        end

        return setmetatable({ pattern = pattern }, { __index = methods })
    end

    function engine.gsub(subject, compiled, replacement)
        return step(function()
            return subject:gsub(compiled.pattern, replacement)
        end)
    end

    function engine.gmatch(subject, compiled)
        local iterator = subject:gmatch(compiled.pattern)

        return function()
            return step(iterator)
        end
    end

    function engine.split(subject, compiled)
        local from = 1
        local finished = false

        return function()
            if finished then
                return nil
            end

            return step(function()
                local at, to = subject:find(compiled.pattern, from)

                if at == nil then
                    finished = true

                    return subject:sub(from)
                end

                local piece = subject:sub(from, at - 1)

                from = to + 1

                return piece
            end)
        end
    end

    return engine
end

--- Ставит модулю с внешними зависимостями двойник движка и отдаёт его записи.
---@param module table Модуль, которому объявление внешних зависимостей дало `_set_source`
---@param failure string|nil Текст, которым отказывает каждый шаг движка
---@return table seen С чем звали `new`, сколько раз спрашивали флаги и какой рок спросили
function helper.install_fake_regex(module, failure)
    local seen = {}
    local engine = helper.fake_regex_engine(seen, failure)

    module._set_source({
        load = function(name)
            seen.asked = name

            return true, engine
        end,
    })

    return seen
end

--- Оставляет модуль с внешними зависимостями без рока: узел собран без движка.
---@param module table Модуль, которому объявление внешних зависимостей дало `_set_source`
function helper.uninstall_regex(module)
    module._set_source({
        load = function()
            return false, "module 'rex_pcre2' not found"
        end,
    })
end

return helper
