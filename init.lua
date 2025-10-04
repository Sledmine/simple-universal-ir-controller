local irrecv = require("irrecv")

-- Define the IR receiver pin (adjust based on your NodeMCU wiring)
local IR_PIN = 5  -- GPIO5 (D1 on NodeMCU)

-- IR command handler
local function onIRReceived(result)
    print("IR Command Received:")
    print("  Command: " .. tostring(result.command))
    print("  Hex: " .. result.hex)
    print("  Raw durations: " .. table.concat(result.raw, ", "))
end

-- Setup IR receiver
print("Starting IR receiver on pin " .. IR_PIN)
irrecv.setup(IR_PIN, {
    callback = onIRReceived,
    gap = 5000
})

print("IR receiver ready. Point your remote and press buttons.")
print("Status: " .. (irrecv.isRunning() and "Running" or "Stopped"))

