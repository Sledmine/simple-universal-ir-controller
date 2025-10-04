-- irrecv.lua
-- IR Receiver module for NodeMCU (ESP8266, Lua)
-- Supports NEC, Sony SIRC12, basic raw capture + raw decode
local bit = bit or require("bit")
local irrecv = {}
local pin, cb, gap, running
local lastTime, durations, lastLevel

-- NEC decode
local function decodeNEC(d)
    if #d < 66 then
        return nil
    end
    local leadMark, leadSpace = d[1], d[2]
    if leadMark < 8500 or leadMark > 9500 then
        return nil
    end
    if leadSpace < 4000 or leadSpace > 5000 then
        return nil
    end

    local addr, cmd = 0, 0
    for i = 3, 66, 2 do
        local mark, space = d[i], d[i + 1]
        if mark < 400 or mark > 700 then
            return nil
        end
        local bitVal = (space > 1000) and 1 or 0
        if i <= 34 then
            addr = bit.bor(bit.lshift(addr, 1), bitVal)
        else
            cmd = bit.bor(bit.lshift(cmd, 1), bitVal)
        end
    end
    return {proto = "NEC", addr = addr, cmd = cmd}
end

-- Sony SIRC12 decode (simplified)
local function decodeSony(d)
    if #d < 24 then -- SIRC12 needs at least 24 transitions (12 bits * 2)
        return nil
    end
    local lead = d[1]
    if lead < 2000 or lead > 2600 then
        return nil
    end
    local value = 0
    local bitCount = 0
    -- Start from position 2 (after lead pulse)
    for i = 2, #d - 1, 2 do
        if i + 1 > #d then break end
        local mark, space = d[i], d[i + 1]
        if not mark or not space then break end
        
        -- Sony SIRC uses pulse width encoding
        local bitVal = (mark > 900) and 1 or 0  -- Adjusted threshold
        value = bit.bor(value, bit.lshift(bitVal, bitCount))
        bitCount = bitCount + 1
        
        if bitCount >= 12 then -- SIRC12 has 12 bits max
            break
        end
    end
    
    if bitCount >= 7 then -- At least 7 bits for a valid SIRC signal
        return {proto = "SIRC12", value = value, bits = bitCount}
    end
    return nil
end

-- Generic RAW-to-bits decode (simple heuristic for NEC-like pulses)
local function decodeRaw(d)
    local bits = {}
    for i = 3, #d - 1, 2 do
        local mark, space = d[i], d[i + 1]
        if not mark or not space then
            break
        end
        if mark > 300 and mark < 900 then
            if space > 300 and space < 1000 then
                bits[#bits + 1] = 0
            elseif space > 1200 and space < 1800 then
                bits[#bits + 1] = 1
            end
        end
    end
    return bits
end

-- Dispatch decoder chain
local function tryDecode(d)
    local r = decodeNEC(d) or decodeSony(d)
    if r then
        return r
    end
    -- fallback to raw
    local bits = decodeRaw(d)
    return {proto = "RAW", bits = bits, durations = d}
end

-- Edge interrupt handler
local function onChange(level)
    local now = tmr.now()
    
    if lastTime then
        local dur = now - lastTime
        -- Handle timer overflow properly
        if dur < 0 then
            dur = dur + 4294967296 -- 2^32 for proper overflow handling
        end
        
        -- Check for end of frame (long gap)
        if dur > gap then
            -- Long gap detected - end of frame
            if #durations > 4 then
                local result = tryDecode(durations)
                if cb and result then
                    cb(result)
                end
            end
            -- Reset for next frame
            durations = {}
            lastTime = now
            lastLevel = level
            return
        end
        
        -- Add duration to current frame
        durations[#durations + 1] = dur
    end
    
    lastTime = now
    lastLevel = level
end

function irrecv.setup(gpioPin, opts)
    -- Stop any existing setup first
    if pin then
        gpio.trig(pin)
    end
    
    pin = gpioPin
    cb = opts and opts.callback or nil
    gap = opts and opts.gap or 8000
    
    -- Initialize state variables
    durations = {}
    lastTime = nil
    lastLevel = nil
    
    -- Setup GPIO
    gpio.mode(pin, gpio.INT)
    gpio.trig(pin, "both", onChange)
    running = true
end

function irrecv.stop()
    if pin then
        gpio.trig(pin)
    end
    running = false
end

function irrecv.isRunning()
    return running
end

function irrecv.getStatus()
    return {
        running = running,
        pin = pin,
        gap = gap,
        durationsCount = durations and #durations or 0,
        lastTime = lastTime,
        lastLevel = lastLevel
    }
end

return irrecv
