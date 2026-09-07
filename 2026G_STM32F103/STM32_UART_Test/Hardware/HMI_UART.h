#ifndef __HMI_UART_H
#define __HMI_UART_H

#include "stm32f10x.h"

void HMI_UART_Init(void);
void HMI_UART_SendString(char *str);
void HMI_SetText(char *obj, char *text);
void HMI_SetVal(const char *objName, uint8_t val);

uint8_t HMI_GetPeriods(void);
uint8_t HMI_IsPeriodChanged(void);

#endif

