do
    local monitor = peripheral.find("monitor")
    if monitor then term.redirect(monitor) end
end

function printError(...)
    term.setTextColor(colors.red)
    print(...)
end

function print(...)
    term.setTextColor(colors.cyan)
    print(...)
end

local function dumpError(msg)
  local dump = assert(fs.open("error.log", "w"))
  dump.write(msg)
  dump.close()
end

print("Initializing Metal Mixing Fluid Manager")

local runFluidManager = require("fluidManager")

while true do
      local success, retval = xpcall(runFluidManager, debug.traceback)
      if not success then
        dumpError(tostring(success)..":::"..tostring(retval))
        printError("An unexpected error was thrown whilst trying to run the fluid manager, the exception was logged. Retrying in 10 seconds")
      end
    os.sleep(10)
end