-- irrecv.lua  
-- IR Receiver module for NodeMCU (ESP8266, Lua)
-- Based on Arduino IRRemoteDecoder implementation
local bit = bit or require("bit")
local irrecv = {}
local pin, cb, gap, running
local lastTime, durations, lastLevel, isFirstTrigger

-- Decode IR command
-- Expects 32 time periods between falling edges (microseconds)
local function decodeCommand(d)
    if #d ~= 32 then
        return nil -- Must have exactly 32 time periods
    end
    
    local receiveStream = 0
    
    for i = 1, 32 do
        local timePeriod = d[i]
        
        -- Check for gap/reset condition
        if timePeriod > gap then
            return nil -- Reset condition, invalid frame
        end
        
        -- Decode based on time period thresholds
        -- 1000-1300us = '0' bit, 2000-2500us = '1' bit
        if timePeriod > 1000 and timePeriod < 1300 and i ~= 32 then
            -- '0' bit: just shift left
            receiveStream = bit.lshift(receiveStream, 1)
        elseif timePeriod > 2000 and timePeriod < 2500 then
            -- '1' bit: OR with 1, then shift (except for last bit)
            receiveStream = bit.bor(receiveStream, 1)
            if i ~= 32 then
                receiveStream = bit.lshift(receiveStream, 1)
            end
        else
            -- Invalid timing, reject frame
            return nil
        end
    end
    
    return {
        command = receiveStream,
        hex = string.format("0x%08X", receiveStream),
        raw = d
    }
end

-- Edge interrupt handler (falling edge trigger like Arduino)
local function onChange(level)
    local now = tmr.now()
    
    -- Only trigger on falling edge (level = 0), matching Arduino behavior
    if level ~= 0 then
        return
    end
    
    if lastTime then
        local dur = now - lastTime
        -- Handle timer overflow properly
        if dur < 0 then
            dur = dur + 4294967296 -- 2^32 for proper overflow handling
        end
        
        if isFirstTrigger then
            -- Start capturing after first falling edge detected
            -- Check for gap/reset condition (>2.5ms = 2500us)
            if dur > gap then
                -- Reset capture
                durations = {}
                isFirstTrigger = false
            else
                -- Add duration to capture buffer
                durations[#durations + 1] = dur
                
                -- Check if we have captured 32 time periods
                if #durations == 32 then
                    local result = decodeCommand(durations)
                    if cb and result then
                        cb(result)
                    end
                    -- Reset for next capture
                    durations = {}
                    isFirstTrigger = false
                end
            end
        else
            -- First falling edge occurred, start capturing from next edge
            isFirstTrigger = true
        end
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
    gap = opts and opts.gap or 2500
    
    -- Initialize state variables
    durations = {}
    lastTime = nil
    lastLevel = nil
    isFirstTrigger = false
    
    -- Setup GPIO with pullup
    gpio.mode(pin, gpio.INT, gpio.PULLUP)
    gpio.trig(pin, "both", onChange)  -- Monitor both edges for proper timing
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
        lastLevel = lastLevel,
        isFirstTrigger = isFirstTrigger
    }
end

return irrecv
