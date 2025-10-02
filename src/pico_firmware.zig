const std = @import("std");
const microzig = @import("microzig");
const time = microzig.drivers.time;
const basic = @import("zigbasic");

const rp2xxx = microzig.hal;
const gpio = rp2xxx.gpio;
const clocks = rp2xxx.clocks;

const uart = rp2xxx.uart.instance.num(0);

const pin_cfg = rp2xxx.pins.GlobalConfiguration{ .GPIO15 = .{
    .name = "led",
    .function = .SIO,
    .direction = .out,
}, .GPIO0 = .{
    .name = "uart0tx",
    .function = .UART0_TX,
}, .GPIO1 = .{
    .name = "uart0rx",
    .function = .UART0_RX,
} };

const pins = pin_cfg.pins();

const src =
    \\10 FOR I = 0 TO 20000
    \\20 PRINT I
    \\35 POKE (I % 300) TO 1
    \\40 NEXT I
    \\50 GOTO 10
;

pub fn main() !void {
    pin_cfg.apply();

    uart.apply(.{
        .clock_config = rp2xxx.clock_config,
    });

    const out = uart.writer();
    var out_handle = out.any().adaptToNewApi(&.{});
    const in = uart.reader();
    var in_handle = in.any().adaptToNewApi(&.{});

    const io = basic.IO{
        .out = &out_handle.new_interface,
        .in = &in_handle.new_interface,
    };

    var mem: [4096]u8 = undefined;
    var a = std.heap.FixedBufferAllocator.init(&mem);
    var alloc = a.allocator();

    var int = try basic.Interpreter.init(&alloc, io, src);
    defer int.deinit();

    try int.state.registerExtension(.{
        .address = 1,
        .getValue = getGPIO,
        .setValue = setGPIO,
    });

    pins.led.toggle();
    int.run() catch {};

    var data: [1]u8 = .{0};
    while (true) {
        // Read one byte, timeout disabled
        uart.read_blocking(&data, null) catch {
            // You need to clear UART errors before making a new transaction
            uart.clear_errors();
            continue;
        };

        //tries to write one byte with 100ms timeout

        uart.write_blocking("cycle\r\n", time.Duration.from_ms(100)) catch {
            uart.clear_errors();
        };
        pins.led.toggle();

        rp2xxx.time.sleep_ms(1000);
    }
}

fn getGPIO(_: usize) f64 {
    return basic.Value.TRUE.number;
}

fn setGPIO(_: usize, v: f64) void {
    if (@abs(v - 1) < std.math.floatEps(f64))
        pins.led.toggle();
}
