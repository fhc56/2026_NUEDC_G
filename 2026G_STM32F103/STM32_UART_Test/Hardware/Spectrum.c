#include "Spectrum.h"
#include "HMI_UART.h"
#include <stdio.h>
#include <math.h>
#include <stdlib.h>

#define BAR_COUNT 10  // 进度条总数

// 静态数组：记录上一次各谐波分量落在哪根柱子上，用于粘滞锁定
static uint8_t s_last_bar[3] = {0, 0, 0};

void Spectrum_Update(const Serial_MeasurementTypeDef *M)
{
    uint8_t i;
    char bar_name[16];
    uint8_t bar_val[BAR_COUNT] = {0};

    uint8_t count = M->ComponentCount;
    if (count > 3) count = 3;
    if (count == 0)
    {
        for (i = 1; i <= BAR_COUNT; i++) {
            sprintf(bar_name, "harm%d", i);
            HMI_SetVal(bar_name, 0);
        }
        s_last_bar[0] = s_last_bar[1] = s_last_bar[2] = 0;
        return;
    }

    /* 1. 找最大频率与最大幅值 */
    uint32_t f_max = 0;
    uint16_t v_max = 0;

    for (i = 0; i < count; i++) {
        if (M->Frequency_Hz[i] > f_max) f_max = M->Frequency_Hz[i];
        if (M->Amplitude_mV[i] > v_max) v_max = M->Amplitude_mV[i];
    }

    if (f_max == 0 || v_max == 0) return;

    /* 2. 带有粘滞锁定的归一化映射 */
    for (i = 0; i < count; i++)
    {
        uint32_t f = M->Frequency_Hz[i];
        uint16_t v = M->Amplitude_mV[i];

        if (f == 0 || v == 0) continue;

        /* 计算连续小数位置：1.00 ~ 10.00 */
        float exact_pos = ((float)f / (float)f_max) * 9.0f + 1.0f;
        
        uint8_t target_bar;
        float frac = exact_pos - (float)((int)exact_pos); // 获取小数部分 (0.0 ~ 0.99)

        /* 
         * 锁定算法逻辑：
         * 如果之前已经有锁定的位置，且本次计算结果与上次只差 ±1 根柱子，
         * 并且小数部分刚好落在 0.40 ~ 0.60 临界死区内，强行锁定在上一次的柱子上！
         */
        uint8_t raw_round = (uint8_t)(exact_pos + 0.5f); // 标准四舍五入
        
        if (s_last_bar[i] >= 1 && s_last_bar[i] <= BAR_COUNT && 
            abs((int)raw_round - (int)s_last_bar[i]) <= 1)
        {
            if (frac >= 0.40f && frac <= 0.60f)
            {
                // 踩在临界死区，直接锁定在上一次的柱子，绝对不跳！
                target_bar = s_last_bar[i];
            }
            else
            {
                target_bar = raw_round;
            }
        }
        else
        {
            // 第一次或者信号幅度/频率发生了巨大的真实改变，直接取四舍五入
            target_bar = raw_round;
        }

        /* 边界保护 */
        if (target_bar < 1) target_bar = 1;
        if (target_bar > BAR_COUNT) target_bar = BAR_COUNT;

        /* 记忆本次确定的柱子位置 */
        s_last_bar[i] = target_bar;

        /* 幅值归一化 (0~100%) */
        uint32_t val = (uint32_t)(((float)v / (float)v_max) * 100.0f + 0.5f);
        if (val > 100) val = 100;

        if (val > bar_val[target_bar - 1]) {
            bar_val[target_bar - 1] = (uint8_t)val;
        }
    }

    /* 3. 刷新串口屏 */
    for (i = 1; i <= BAR_COUNT; i++)
    {
        sprintf(bar_name, "harm%d", i);
        HMI_SetVal(bar_name, bar_val[i - 1]);
    }
}

