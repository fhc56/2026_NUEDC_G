#include "stm32f10x.h"
#include "HMI_UART.h"
#include "Serial.h"
#include "Spectrum.h"
#include "Display.h"
#include "Waveform.h"
#include <string.h>
#include <stdio.h>

typedef enum {
    WAVE_STATE_WAIT_DATA = 0, // 等待数据
    WAVE_STATE_DRAW,          // 绘制波形
    WAVE_STATE_HOLD           // 锁定保持
} WaveState_t;

int main(void)
{
    Serial_MeasurementTypeDef Data;
    Serial_MeasurementTypeDef Last_Drawn_Data; // 保存上一次重绘时的旧数据
    
    WaveState_t wave_state = WAVE_STATE_WAIT_DATA;

    HMI_UART_Init();
    Serial_Init();

    while(1)
    {
        /* 1. 收到 FPGA 新一帧数据 */
        if (Serial_GetMeasurement(&Data))
        {
            // 数字文本区和频谱柱状图可以继续实时更新
            Display_Update(&Data);
            Spectrum_Update(&Data);

            // 如果当前处于 HOLD 锁定状态，判断输入信号是否发生了改变
            if (wave_state == WAVE_STATE_HOLD)
            {
                if (Waveform_IsDataChanged(&Data, &Last_Drawn_Data))
                {
                    wave_state = WAVE_STATE_DRAW; // 自动触发重绘！
                }
            }
            // 如果是在等待初始数据，直接触发首次重绘
            else if (wave_state == WAVE_STATE_WAIT_DATA)
            {
                wave_state = WAVE_STATE_DRAW;
            }
        }

        /* 2. 检查串口屏按键事件 (1 Period / 3 Period 切换) */
        if (HMI_IsPeriodChanged()) {
            wave_state = WAVE_STATE_DRAW; // 手动切周期，强制触发重绘
        }

        /* 3. 波形绘制状态机处理 */
        switch (wave_state)
        {
            case WAVE_STATE_WAIT_DATA:
                break;

            /* 在 main.c 的 switch(wave_state) 中 */
						case WAVE_STATE_DRAW:
								// 1. 绘制波形
								Waveform_Draw(&Data, HMI_GetPeriods());
								
								// 2. 完整深拷贝当前数据到 Last_Drawn_Data！(关键)
								memcpy((void*)&Last_Drawn_Data, (void*)&Data, sizeof(Serial_MeasurementTypeDef));
								
								// 3. 切入 HOLD 状态，进入锁定
								wave_state = WAVE_STATE_HOLD;
								break;

            case WAVE_STATE_HOLD:
                // 锁定保持，不重复刷屏
                break;
        }
    }
}

