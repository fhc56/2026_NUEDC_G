#include "Waveform.h"
#include "HMI_UART.h"
#include <stdlib.h> // 使用 abs() 函数
#include <math.h>
#include <stdio.h>

#define WAVE_W       541.0f  // 控件宽度
#define WAVE_H       186.0f  // 控件高度
#define PI           3.1415926535f

void Waveform_Draw(const Serial_MeasurementTypeDef *M, uint8_t periods)
{
    uint16_t x;
    uint8_t i;
    char cmd[32];

    if (M->Fundamental_Hz == 0) return;

    /* 1. 清空 signal 控件波形 (id 为 1，通道 0) */
    HMI_UART_SendString("cle 1,0");
    HMI_UART_SendString("\xFF\xFF\xFF");

    /* 2. 计算各成分叠加后的理论最大峰值，避免溢出 */
    float v_total_peak = 0.0f;
    uint8_t count = M->ComponentCount;
    if (count > 3) count = 3;

    for (i = 0; i < count; i++) {
        v_total_peak += (float)M->Amplitude_mV[i];
    }
    if (v_total_peak < 1.0f) v_total_peak = 100.0f; 

    /* 
     * 3. 几何限制：
     * 屏幕中心零线坐标 y_center = 186 / 2 = 93
     * 为了保证不超界，最大正负幅值只允许占用 (186/2 - 10) = 83 个像素的上下空间
     */
    float y_center = WAVE_H / 2.0f; // 93
    float max_amplitude_pixels = (WAVE_H / 2.0f) - 10.0f; // 83 像素

    /* 4. 逐点推算并发送 */
    for (x = 0; x < (uint16_t)WAVE_W; x++)
    {
        float sample_val = 0.0f;

        for (i = 0; i < count; i++)
        {
            if (M->Frequency_Hz[i] == 0) continue;

            float freq_ratio = (float)M->Frequency_Hz[i] / (float)M->Fundamental_Hz;
            float angle = 2.0f * PI * freq_ratio * (float)periods * ((float)x / (WAVE_W - 1.0f));
            
            sample_val += (float)M->Amplitude_mV[i] * sinf(angle);
        }

        /* 
         * 串口屏 Y 轴坐标系注意：
         * 0 是最顶端，186 是最底端。
         * 正弦波正半周（sample_val > 0）应该向上移动，即 y 坐标减小。
         */
        float y_pixel = y_center - (sample_val / v_total_peak) * max_amplitude_pixels;

        // 严格限制在控件高度 [0, 186] 内，绝不溢出
        if (y_pixel < 2.0f) y_pixel = 2.0f;
        if (y_pixel > (WAVE_H - 2.0f)) y_pixel = WAVE_H - 2.0f;

        sprintf(cmd, "add 1,0,%d", (uint8_t)y_pixel);
        HMI_UART_SendString(cmd);
        HMI_UART_SendString("\xFF\xFF\xFF");
    }
}

#include <stdlib.h> // 使用 abs()

/**
 * @brief  极简稳定判定：仅检测基波及谐波幅值 Amplitude_mV 是否发生真实改变
 * @param  new_data 当前最新数据
 * @param  old_data 上一次绘制波形时保留的数据
 * @return 1: 谐波幅值有明显改变，需重新画图; 0: 信号稳定，保持静止
 */
uint8_t Waveform_IsDataChanged(const Serial_MeasurementTypeDef *new_data, 
                               const Serial_MeasurementTypeDef *old_data)
{
    uint8_t i;

    // 仅检测前 3 个最稳定的谐波/基波幅值
    for (i = 0; i < 3; i++)
    {
        // 只要有任意一个分量的幅值变化超过 5mV（可根据需求调为 3mV 或 5mV）
        if (abs((int16_t)new_data->Amplitude_mV[i] - (int16_t)old_data->Amplitude_mV[i]) > 5) 
        {
            return 1; // 触发重新画波形
        }
    }

    return 0; // 稳定静止，绝不重复刷新
}

