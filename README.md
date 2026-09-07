\# 2026 NUEDC Problem G - Periodic Signal Measurement and Analysis System



> \*\*🏆 Award: First Prize at the Provincial Level (省一等奖), 2026 National Undergraduate Electronics Design Contest\*\*



2026 年全国大学生电子设计竞赛 G 题——\*\*周期信号测量分析装置\*\*。



本项目基于 \*\*STM32F103 + Zynq-7020 FPGA\*\* 实现周期信号采集、处理、频谱分析以及测量结果显示。



!\[System](Fig1.jpg)



!\[Device](Fig2.jpg)



\## Award



\- \*\*2026 全国大学生电子设计竞赛\*\*

\- \*\*G 题：周期信号测量分析装置\*\*

\- \*\*省一等奖\*\*



\## Project Overview



系统主要由 STM32 控制部分、Zynq-7020 FPGA 信号处理部分以及人机交互界面组成。



FPGA 部分负责高速数字信号处理，包括采样数据处理、FFT、频谱特征提取等功能；STM32 部分负责系统控制、数据交互及外围设备管理。



\## Hardware Platform



\- STM32F103

\- Zynq-7020 FPGA

\- ADC signal acquisition

\- Display / HMI interface

\- Custom signal processing system



\## FPGA



FPGA 部分使用 Verilog HDL 开发，主要包含：



\- ADC data acquisition

\- Offset binary conversion

\- FIFO data synchronization

\- 8192-point FFT processing

\- FFT power calculation

\- Spectrum analysis

\- Peak detection

\- Waveform characteristic measurement

\- UART communication

\- Digital signal processing modules



主要源码位于：



```text

2026G\_Zynq7020\_FPGA/

```



部分核心模块：



```text

ad9226\_clock\_capture.v

adc\_offset\_binary.v

adc\_overrange\_frame.v

axis\_sync\_fifo.v

fft\_8192\_wrapper.v

fft\_power\_calc.v

fir\_output\_scale.v

g\_fft\_8192\_core.v

integer\_sqrt\_u64.v

measurement\_uart.v

peak\_detector\_3.v

spectrum\_metrics.v

top\_fft\_g.v

top\_fft\_g\_board.v

top\_fft\_sd.v

uart\_tx\_byte.v

unsigned\_divider\_48\_24.v

waveform\_metrics.v

window\_8192.v

```



\## STM32



STM32 控制程序位于：



```text

2026G\_STM32F103/

```



主要用于系统控制、外围设备驱动、数据通信以及测量结果交互。



\## Repository Structure



```text

2026\_NUEDC\_G/

├── 2026G\_STM32F103/

│   └── STM32 firmware

│

├── 2026G\_Zynq7020\_FPGA/

│   └── FPGA Verilog source code

│

├── Screen/

│   └── HMI / display resources

│

├── Fig1.jpg

├── Fig2.jpg

│

├── G题 周期信号测量分析装置.pdf

├── 2026年电赛设计报告.pdf

│

└── README.md

```



\## Development Tools



\- Vivado 2018.3

\- Keil MDK

\- Verilog HDL

\- C

\- STM32 Standard Peripheral Library



\## Result



该项目完成了 2026 全国大学生电子设计竞赛 G 题要求，并获得：



\*\*🏆 省一等奖（Provincial First Prize）\*\*



\## Notes



This repository contains the main STM32 firmware, FPGA Verilog source code, HMI resources, competition problem statement, and project documentation.

