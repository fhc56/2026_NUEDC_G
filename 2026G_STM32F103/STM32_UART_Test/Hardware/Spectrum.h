#ifndef __SPECTRUM_H
#define __SPECTRUM_H

#include "stm32f10x.h"
#include "Serial.h"

/* 刷新频谱显示 */
void Spectrum_Update(const Serial_MeasurementTypeDef *M);

#endif
