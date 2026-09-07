#include "Serial.h"
#include "Display.h"
#include "HMI_UART.h"
#include <stdio.h>


#include <math.h>

#define PI 3.1415926535f

/**
 * @brief  根据谐波幅值与频率重构波形，并扫描计算出精确的 Vpp
 * @param  M 测量数据结构体指针
 * @return 计算出的 Vpp (单位: mV)
 */
uint16_t Calculate_Vpp_From_Harmonics(const Serial_MeasurementTypeDef *M)
{
    uint16_t x;
    uint8_t i;
    float max_val = 0.0f;

    // 基础保护：如果基波频率或幅值为 0，直接返回 0
    if (M->Fundamental_Hz == 0 || M->Amplitude_mV[0] == 0)
    {
        return 0;
    }

    uint8_t count = M->ComponentCount;
    if (count > 3) count = 3;

    /* 
     * 扫过 1 个完整基波周期
     * 将 1 个周期等分为 360 个采样点进行扫描寻找峰值
     */
    for (x = 0; x < 360; x++)
    {
        float current_sample = 0.0f;

        // 叠加各个谐波分量在当前相位点的值
        for (i = 0; i < count; i++)
        {
            if (M->Frequency_Hz[i] == 0 || M->Amplitude_mV[i] == 0) continue;

            // 谐波频率与基波频率的比值 (如 1, 3, 4)
            float freq_ratio = (float)M->Frequency_Hz[i] / (float)M->Fundamental_Hz;
            
            // 相位角 alpha = 2 * PI * ratio * (x / 360.0)
            float angle = 2.0f * PI * freq_ratio * ((float)x / 360.0f);

            current_sample += (float)M->Amplitude_mV[i] * sinf(angle);
        }

        // 记录扫描到的最大正峰值
        if (current_sample > max_val)
        {
            max_val = current_sample;
        }
    }

    /* Vpp = 2 * 最大峰值 (四舍五入转为整数 mV) */
    return (uint16_t)(max_val * 2.0f + 0.5f);
}










void Display_Update(Serial_MeasurementTypeDef *M)
{
    char buf[32];

    /* 1. 自行扫描计算精确的 Vpp */
    uint16_t calc_vpp = Calculate_Vpp_From_Harmonics(M);

    sprintf(buf, "%dmV", calc_vpp);
    HMI_SetText("Vpp", buf);

    /* 2. RMS (有效值) */
    sprintf(buf, "%dmV", M->Rms_mV);
    HMI_SetText("RMS", buf);

	
		sprintf(buf, "%lu.%02lukHz", 
            M->Fundamental_Hz / 1000, 
            (M->Fundamental_Hz % 1000) / 10);
    HMI_SetText("Base", buf);
	
	
    /* 3. 基波频率 F0 (保留2位小数，分辨率精细至 0.01kHz / 10Hz) */
    // 例如 10500 Hz -> 10.50 kHz
    sprintf(buf, "%lu.%02lukHz", 
            M->Fundamental_Hz / 1000, 
            (M->Fundamental_Hz % 1000) / 10);
    HMI_SetText("F_base", buf);

    /* 4. 基波幅值 */
    sprintf(buf, "%dmV", M->Amplitude_mV[0]);
    HMI_SetText("V_base", buf);

    /* 5. 谐波 1 频率与幅值 */
    sprintf(buf, "%lu.%02lukHz", 
            M->Frequency_Hz[1] / 1000, 
            (M->Frequency_Hz[1] % 1000) / 10);
    HMI_SetText("F_harm1", buf);

    sprintf(buf, "%dmV", M->Amplitude_mV[1]);
    HMI_SetText("V_harm1", buf);

    /* 6. 谐波 2 频率与幅值 */
    sprintf(buf, "%lu.%02lukHz", 
            M->Frequency_Hz[2] / 1000, 
            (M->Frequency_Hz[2] % 1000) / 10);
    HMI_SetText("F_harm2", buf);

    sprintf(buf, "%dmV", M->Amplitude_mV[2]);
    HMI_SetText("V_harm2", buf);
}

