#ifndef __SERIAL_H
#define __SERIAL_H

#ifdef SERIAL_HOST_TEST
#include <stdint.h>
#else
#include "stm32f10x.h"
#endif

/* One checksum-verified measurement snapshot from the FPGA. */
typedef struct
{
    uint16_t Vpp_mV;
    uint16_t Rms_mV;
    uint32_t Fundamental_Hz;
    uint8_t ComponentCount;
    uint32_t Frequency_Hz[3];
    uint16_t Amplitude_mV[3];
    uint8_t Status;
} Serial_MeasurementTypeDef;

/* USART1 RX on PA10, 115200 bit/s, 8-N-1. */
void Serial_Init(void);

/* Kept for compatibility with the original polling project; reception is now
 * interrupt driven, so this function intentionally performs no work. */
void Serial_Process(void);

/* Atomically copy the newest complete frame. Returns 1 only once per update. */
uint8_t Serial_GetMeasurement(Serial_MeasurementTypeDef *Measurement);

uint32_t Serial_GetFrameCount(void);
uint32_t Serial_GetErrorCount(void);
uint32_t Serial_GetByteCount(void);

#ifdef SERIAL_HOST_TEST
/* Parser-only desktop regression hook; not present in STM32 firmware. */
void Serial_TestFeedByte(uint8_t Byte);
#endif

#endif
