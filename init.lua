local ir = require("irrecv")

ir.setup(5, {
    callback = function(result)
        print("Status:", ir.getStatus().durationsCount, "durations")
        if result then
            if result.proto == "SIRC12" then
                print("SIRC12:", string.format("0x%03X", result.value), "bits:", result.bits)
            elseif result.proto == "NEC" then
                print("NEC: addr=", result.addr, "cmd=", result.cmd)
            else
                print("RAW bits:")
                local value
                -- Get value form raw bits
                for i = 1, #result.bits do
                    value = (value or 0) * 2 + result.bits[i]
                end
                print(string.format("0x%X", value))
            end
        else
            print("Failed to decode")
        end
    end,
    --gap = 8000
})