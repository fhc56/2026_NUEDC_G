#ifndef __WAVEFORM_H
#define __WAVEFORM_H

#include "stm32f10x.h"
#include "Serial.h"

void Waveform_Update(const Serial_MeasurementTypeDef *M, uint8_t periods);
/* 波形绘制函数声明 */
void Waveform_Draw(const Serial_MeasurementTypeDef *M, uint8_t periods);
uint8_t Waveform_IsDataChanged(const Serial_MeasurementTypeDef *new_data, 
                               const Serial_MeasurementTypeDef *old_data);
#endif
