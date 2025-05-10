--!optimize 2
--!strict


type Rule = {
    kind: "Nonterminal",
    label: string,
    probability: number,
    symbol: string
} | {
    kind: "TerminalProduct",
    label: string,
    probability: number,
    ruleA: string, -- Label of ruleA
    ruleB: string, -- Label of ruleB
} | {
    kind: "Start",
    label: string,
    probability: number,
    rule: string -- Label of rule
}

type RuleSet = {[number]: Rule}


-- Table reverser from https://stackoverflow.com/questions/72783502/how-does-one-reverse-the-items-in-a-table-in-lua
local function reverse(tab)
    for i = 1, #tab//2, 1 do
        tab[i], tab[#tab-i+1] = tab[#tab-i+1], tab[i]
    end
    return tab
end

local function tabulate(tab: {{string}}): string
    local tabulated = {}

    -- Find the element in tab that is the largest in length
    local maxElementSize = 0
    for _, intab in tab do 
        for _, key in intab do 
            maxElementSize = math.max(#key, maxElementSize)
        end
    end

    for i, intab in tab do 
        -- Code here
        local tabs = {}
        for _, key in intab do 
            -- Padding + String + Padding = MaxElementSize
            -- Padding = (MaxElementSize - String) / 2
            local s = key .. string.rep(" ", maxElementSize - #key)
            tabs[#tabs + 1] = s
        end

        tabulated[#tabulated + 1] = "|" .. table.concat(tabs, "|") .. "|"
    end

    return table.concat(tabulated, "\n")
end

local function cyk(inputString: string, grammarRules: RuleSet, print: (...any) -> (), debug: boolean?): number? 
    -- Find all nonterminal rules first
    local nonterminalRules = {}
    for i, rule in grammarRules do 
        if rule.kind == "Nonterminal" then 
            nonterminalRules[#nonterminalRules + 1] = rule
        end
    end

    if debug then 
        print("Nonterminal rules", #nonterminalRules)
    end

    -- Same with terminal rules
    local terminalRules: {Rule} = {}
    for i, rule in grammarRules do 
        if rule.kind == "TerminalProduct" then 
            terminalRules[#terminalRules + 1] = rule
        end
    end

    local function findTerminalRulesTo(ruleA: string, ruleB: string): {Rule} 
        local rules = {}
        for _, rule in terminalRules do 
            assert(rule.kind == "TerminalProduct")
            if rule.ruleA == ruleA and rule.ruleB == ruleB then rules[#rules + 1] = rule end
        end
        return rules
    end

    local function findRulesWithSymbolMap(symbol: string): {[string]: RuleMap} 
        local foundRules: {[string]: RuleMap} = {}
        for _, rule in nonterminalRules do 
            rule = rule :: Rule
            assert(rule.kind == "Nonterminal")
            if foundRules[rule.label] then continue end
            if rule.symbol == symbol then foundRules[rule.label] = {a = rule.symbol, b = "", prob = rule.probability} end
        end
        return foundRules
    end

    -- Given two sets of rule labels, finds all rules which could have made up that rule
    local function findRulesWithSymbol(symbol: string): {string} 
        local foundRules: {[string]: RuleMap} = findRulesWithSymbolMap(symbol)

        local rules = {}
        for rule in foundRules do 
            rules[#rules + 1] = rule
        end

        return rules
    end

    type RuleMap = {
        a: string,
        b: string,
        prob: number
    }

    -- Given two sets of rule labels, finds all rules which could have made up that rule
    local function findRulesMakingRuleMap(a: {string}, b: {string}): {[string]: RuleMap} 
        local foundRules: {[string]: RuleMap} = {}
        for _, ruleA in a do 
            for _, ruleB in b do 
                for _, newRule in findTerminalRulesTo(ruleA, ruleB) do 
                    if foundRules[newRule.label] then continue end
                    foundRules[newRule.label] = {a = ruleA, b = ruleB, prob = newRule.probability}
                end
            end
        end

        return foundRules
    end

    -- Given two sets of rule labels, finds all rules which could have made up that rule
    local function findRulesMakingRule(a: {string}, b: {string}): {string} 
        local foundRules: {[string]: RuleMap} = findRulesMakingRuleMap(a, b)

        local rules = {}
        for rule in foundRules do 
            rules[#rules + 1] = rule
        end

        return rules
    end

    if debug then 
        print("Rules making LS", findRulesMakingRule({"L"}, {"S"}))
        print("Rules from {L,M} and {S,Q}", findRulesMakingRule({"L", "M"}, {"S", "Q"}))
    end

    -- Make a N by N grid where i is the the index of the row (horizontal), j is the vertical
    local grid = {}

    -- Set all to empty initially
    for i = 1, #inputString do 
        grid[i] = {}
        for j = 1, (#inputString - i + 1) do 
            grid[i][j] = {}
        end
    end 

    type BackTrace = {
        rules: RuleMap,
        i1: number,
        j1: number,
        i2: number,
        j2: number
    }

    -- A second back grid for backtracing
    local back: {{{[string]: BackTrace}}} = {}

    -- Set all to empty initially
    for i = 1, #inputString do 
        back[i] = {}
        for j = 1, (#inputString - i + 1) do 
            back[i][j] = {}
        end
    end 

    -- Add in the first layer from the symbols
    for i = 1, #inputString do 
        local ch = string.sub(inputString, i, i)

        local ntRules = findRulesWithSymbolMap(ch)

        local rules = {}
        for rule in ntRules do 
            rules[#rules + 1] = rule
        end

        grid[i][1] = rules
        for rule, comesFrom in ntRules do 
            back[i][1][rule] = {
                rules = comesFrom :: RuleMap,
                i1 = i,
                i2 = 0,
                j1 = 1,
                j2 = 0,
            }
        end
    end

    if debug then 
        print("GRID", grid)
    end

    -- Go layer by layer, to construct the DP Table
    for level = 2, #inputString do -- The level
        -- Start from 1 and go up to inputString - the level + 1 (for string of length 3, does 3, 2, 1)
        for start = 1, (#inputString - level + 1) do 
            if debug then
                print("At level " .. level .. " and start " .. start)
            end
            -- Start conditions
            local j1 = 1
            local i1 = start
            local j2 = level - 1
            local i2 = start + 1

            local ruleMap: {[string]: boolean} = {}
            while j1 < level do
                if debug then
                    print(i1, j1, " | ", i2, j2)
                end

                local a = grid[i1][j1]
                local b = grid[i2][j2]

                if debug then
                    print(table.concat(a, "") .. " " ..  table.concat(b, ""))
                end

                for rule, comesFrom in findRulesMakingRuleMap(a, b) do 
                    ruleMap[rule] = true
                    back[start][level][rule] = {
                        rules = comesFrom :: RuleMap,
                        i1 = i1,
                        i2 = i2,
                        j1 = j1,
                        j2 = j2,
                    }
                end

                -- Go to next box
                j1 += 1 -- cursor A moves up 1
                i2 += 1
                j2 -= 1
            end

            local rules = {}
            for rule in ruleMap do 
                rules[#rules + 1] = rule
            end

            if debug then 
                print("Got rules", rules)
            end
            grid[start][level] = rules
        end
    end

    -- Print final DP grid
    if debug then 
        local finalGrid = {}
        for i = 1, #inputString do 
            local row = {}
            for j = 1, #inputString do 
                row[#row + 1] = (if grid[j][i] then table.concat(grid[j][i], "") else "")
            end
            finalGrid[#finalGrid + 1] = row
        end 

        local gridStr = (tabulate)(reverse(finalGrid))

        print("")
        print(tostring(gridStr))    

        local finalBack = {}
        for i = 1, #inputString do 
            local row = {}
            for j = 1, (#inputString - i + 1) do 
                local backStr = {}
                for rule, rulerow in back[j][i] do
                    print(i, j, rulerow)
                    -- string.format("%s: %s, ", rule, table.concat(rulerow.rules))
                    backStr[#backStr + 1] = string.format("%s: %s (%d%d%d%d), ", rule, table.concat({rulerow.rules.a, rulerow.rules.b}), rulerow.i1, rulerow.j1, rulerow.i2, rulerow.j2)
                end

                row[#row + 1] = (if backStr then table.concat(backStr, "") else "")
            end

            for j = (#inputString - i + 2), #inputString do
                row[#row + 1] = ""
            end

            finalBack[#finalBack + 1] = row
        end 

        local backStr = (tabulate)(reverse(finalBack))

        print("")
        print(tostring(backStr))

        local finalBack2 = {}
        for i = 1, #inputString do 
            local row = {}
            for j = 1, (#inputString - i + 1) do 
                local backStr2 = {}
                for rule, rulerow in back[j][i] do
                    backStr2[#backStr2 + 1] = string.format("%s: %s, ", rule, table.concat({rulerow.rules.a, rulerow.rules.b}))
                end

                row[#row + 1] = (if backStr then table.concat(backStr2, "") else "")
            end

            for j = (#inputString - i + 2), #inputString do
                row[#row + 1] = ""
            end

            finalBack2[#finalBack2 + 1] = row
        end 

        local backStr2 = (tabulate)(reverse(finalBack2))

        print("")
        print(tostring(backStr2))
    end

    local startLabel = nil
    for _, rule in grammarRules do 
        if rule.kind == "Start" then 
            startLabel = rule.rule 
            break
        end
    end

    assert(startLabel, "No `Start` rule found")

    local foundStart = false
    for _, element in grid[1][#inputString] do
        if element == startLabel then 
            foundStart = true
            break
        end
    end

    if not foundStart then 
        return nil
    end

    -- Backtrace the rules
    local prob = 1
    local function backTraceRule(i: number, j: number, rule: string, parent: string) 
        local backtrace = back[i][j][rule]
        if not backtrace then return end
        if debug then
            print("root: " .. rule .. " | left: " .. backtrace.rules.a .. " | right: " .. backtrace.rules.b .. " (" .. backtrace.rules.prob .. ") | parent: " .. parent)
        end

        prob *= backtrace.rules.prob

        if backtrace.rules.a ~= "" then
            backTraceRule(backtrace.i1, backtrace.j1, backtrace.rules.a, rule) 
        end

        if backtrace.rules.b ~= "" then
            backTraceRule(backtrace.i2, backtrace.j2, backtrace.rules.b, rule) 
        end
    end

    backTraceRule(1, #inputString, startLabel, "")

    if debug then
        print("Probability: " .. prob)
    end

    return prob
end

--KH
local p1 = 0.869
local q1 = 0.131
local p2 = 0.895
local q2 = 0.105
local p3 = 0.788
local q3 = 0.212

local grammarRules_in: RuleSet = {
    {
        kind = "Start",
        label = "S0",
        rule = "S",
        probability = 1
    },
    -- S = LS|MQ|s
    {
        kind = "TerminalProduct",
        label = "S",
        probability = p1,
        ruleA = "L",
        ruleB = "S",
    },
    {
        kind = "TerminalProduct",
        label = "S",
        probability = q1*p2,
        ruleA = "M",
        ruleB = "Q",
    },
    {
        kind = "Nonterminal",
        label = "S",
        probability = q1*q2,
        symbol = "s"
    },
    -- L = MQ|s
    {
        kind = "TerminalProduct",
        label = "L",
        probability = p2,
        ruleA = "M",
        ruleB = "Q"
    },
    {
        kind = "Nonterminal",
        label = "L",
        probability = q2,
        symbol = "s"
    },
    -- F = MQ|LS
    {
        kind = "TerminalProduct",
        label = "F",
        probability = p3,
        ruleA = "M",
        ruleB = "Q"
    },
    {
        kind = "TerminalProduct",
        label = "F",
        probability = q3,
        ruleA = "L",
        ruleB = "S"
    },
    -- M = PF
    {
        kind = "TerminalProduct",
        label = "M",
        probability = 1,
        ruleA = "P",
        ruleB = "F"
    },
    -- P = d
    {
        kind = "Nonterminal",
        label = "P",
        probability = 1,
        symbol = "d"
    },
    -- Q = e
    {
        kind = "Nonterminal",
        label = "Q",
        probability = 1,
        symbol = "e"
    }
}

local inputString_in = "dsse"

-- Part A
cyk(inputString_in, grammarRules_in, print :: any, true)

-- Part B
local function dummyPrint(...) end
local maxProb = 0

-- Fast algo adopted from https://stackoverflow.com/questions/71683221/generation-of-all-sequences-of-length-n-from-numbers-0-1-k-1-with-minimal-change
local n = 19

local totalPermutes = 3^n
local shownPermutes = 0
local lastShownProgress = 0

local s = {}
for i = 1, n do 
    s[#s + 1] = "s"
end
while true do
    shownPermutes += 1
    local str = table.concat(s)
    local prob = cyk(table.concat(s), grammarRules_in, dummyPrint :: any, false)
    if prob and prob > maxProb then 
        lastShownProgress = (shownPermutes / totalPermutes) * 100
        print("New max prob of " .. prob .. " with string " .. str .. " with progress of [" .. lastShownProgress .. "%]")
    end
    --print(table.concat(s))

    local k = n
    while k >= 1 and s[k] == "e" do 
        s[k] = "s"
        k-=1
    end

    if k == 0 then break end

    if s[k] == "s" then 
        s[k] = "d"
    elseif s[k] == "d" then
        s[k] = "e" 
    end

    local newLastShownProgress = (shownPermutes / totalPermutes) * 100
    if newLastShownProgress - lastShownProgress > 5 then 
        print("Status update: " .. newLastShownProgress .. "%")
        lastShownProgress = newLastShownProgress
    end
end

--[[
-- Initial slow algorithm (same base idea except uses more memory/time and generates from bottom up instead)
-- d, s -> add d, s
-- dd, ds, de, sd, ss, se -> take existing d, s and add d, s, e
local basePairs = {"s", "d", "e"}
local nucleotides = {"s", "d"} -- {"d", "s"}
for i = 1, 3 do -- For each iteration
    print("Iteration " .. i)

    local newNucleotides = {}
    local nucleotidesLen = #nucleotides
    for j = 1, nucleotidesLen do 
        local baseNucleotide = nucleotides[j]
        for _, base in basePairs do
            --if baseNucleotide.hasD < baseNucleotide.hasE and base == 'e' then continue end
            --if baseNucleotide.hasD > baseNucleotide.hasE and base == 'd' then continue end
            newNucleotides[#newNucleotides + 1] = (baseNucleotide .. base) :: any
        end
    end

    nucleotides = newNucleotides
end

print(nucleotides)
print("Number of nucleotides: " .. #nucleotides)
]]