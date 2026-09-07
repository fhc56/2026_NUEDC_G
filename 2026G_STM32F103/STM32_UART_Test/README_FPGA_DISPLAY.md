# STM32F103C8T6 FPGA 测量数据显示工程

本目录由用户提供的 `STM32_UART_Test.zip` 复制修改而来，原 ZIP 未改动。Keil 工程、OLED 驱动和原硬件接口均保留。

## 连接

| FPGA | STM32F103C8T6 | 说明 |
|---|---|---|
| V10 `uart_tx` | PA10 `USART1_RX` | 3.3 V UART 数据 |
| GND | GND | 必须共地 |

FPGA V10 是 LVCMOS33 输出，STM32 PA10 是 3.3 V 输入，因此不需要 TTL 转 USB 模块，也不需要电平转换。不要把 5 V 接到 PA10 或 V10。

原有外设接口保持不变：

- OLED SCL：PB8
- OLED SDA：PB9
- 上一页按键：PB1
- 下一页按键：PB11
- 串口：USART1 RX/PA10，115200 bit/s，8-N-1

## 屏幕页面

- P1：用大字显示基频 `F0`、整体峰峰值 `VPP` 和真有效值 `RMS`
- P2：显示最多三个频率分量及其峰值幅度；标题中的 `Apeak(mV)` 明确表示峰值毫伏

PB1 固定进入 P1，PB11 固定进入 P2。串口采用中断接收，因此 OLED 刷新和按键消抖期间不会因主循环阻塞而漏掉 115200 波特率的数据。

复杂状态页已经移除。P1 标题栏仅保留以下必要提示：

| 提示 | 含义 |
|---|---|
| `OK` | 数据通路正常且已标定 |
| `UNCAL` | 数据通路正常，但仍使用名义电压比例 |
| `ADC!` | ADC 出现 OTR 或满量程码，当前幅值不可信 |
| `FLOW!` | FIFO/FIR 数据流曾溢出或反压 |
| `FFT!` | FFT 帧边界异常 |

## 编译下载

用 Keil MDK5 打开 `Project.uvprojx`，执行 Rebuild，然后沿用原工程的 ST-Link 下载配置烧录 STM32F103C8T6。

当前目录也已经生成可直接烧录的 GCC 版本：

```text
Objects/gcc/FPGA_Display.hex
Objects/gcc/FPGA_Display.bin
```

如果需要重新生成，执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\GCC\build_gcc.ps1"
```

GCC 版本针对 STM32F103C8T6 的 64 KiB Flash / 20 KiB RAM 链接，向量表位于 `0x08000000`，USART1 中断向量已核对到本工程的接收函数。

FPGA 每帧发送 105 字节 ASCII 十六进制数据，STM32 会检查固定字段、长度、CR/LF 和 XOR 校验和。只有完整合法帧才会更新屏幕。

默认 FPGA BIT 尚未做实板电压标定，因此状态页通常显示 `CAL : NOMINAL`，状态字节通常至少包含 `0x40`。完成整机电压标定并重新生成 FPGA BIT 后才会显示 `CAL : OK`。
