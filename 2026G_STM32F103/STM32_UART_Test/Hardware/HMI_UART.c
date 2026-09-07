#include "HMI_UART.h"
#include <stdio.h>

/* 周期控制相关变量 */
static volatile uint8_t g_Display_Periods = 1;     // 默认 1 个周期
static volatile uint8_t g_Period_Changed_Flag = 0; // 按键切换标志位

/*
    USART2 初始化
    PA2 TX
    PA3 RX
*/
void HMI_UART_Init(void)
{
    GPIO_InitTypeDef GPIO_InitStructure;
    USART_InitTypeDef USART_InitStructure;
    NVIC_InitTypeDef NVIC_InitStructure;

    /* 使能 GPIOA 和 USART2 时钟 */
    RCC_APB2PeriphClockCmd(RCC_APB2Periph_GPIOA, ENABLE);
    RCC_APB1PeriphClockCmd(RCC_APB1Periph_USART2, ENABLE);

    /* PA2 TX (复用推挽输出) */
    GPIO_InitStructure.GPIO_Pin = GPIO_Pin_2;
    GPIO_InitStructure.GPIO_Mode = GPIO_Mode_AF_PP;
    GPIO_InitStructure.GPIO_Speed = GPIO_Speed_50MHz;
    GPIO_Init(GPIOA, &GPIO_InitStructure);

    /* PA3 RX (浮空输入) */
    GPIO_InitStructure.GPIO_Pin = GPIO_Pin_3;
    GPIO_InitStructure.GPIO_Mode = GPIO_Mode_IN_FLOATING;
    GPIO_Init(GPIOA, &GPIO_InitStructure);

    /* USART2 参数配置 */
    USART_InitStructure.USART_BaudRate = 115200;
    USART_InitStructure.USART_WordLength = USART_WordLength_8b;
    USART_InitStructure.USART_StopBits = USART_StopBits_1;
    USART_InitStructure.USART_Parity = USART_Parity_No;
    USART_InitStructure.USART_HardwareFlowControl = USART_HardwareFlowControl_None;
    USART_InitStructure.USART_Mode = USART_Mode_Tx | USART_Mode_Rx;
    USART_Init(USART2, &USART_InitStructure);

    /* NVIC 配置：开启 USART2 接收中断 */
    NVIC_PriorityGroupConfig(NVIC_PriorityGroup_2);
    NVIC_InitStructure.NVIC_IRQChannel = USART2_IRQn;
    NVIC_InitStructure.NVIC_IRQChannelPreemptionPriority = 2; // 优先级低于 FPGA(USART1)
    NVIC_InitStructure.NVIC_IRQChannelSubPriority = 0;
    NVIC_InitStructure.NVIC_IRQChannelCmd = ENABLE;
    NVIC_Init(&NVIC_InitStructure);

    /* 使能 USART2 接收中断与串口 */
    USART_ITConfig(USART2, USART_IT_RXNE, ENABLE);
    USART_Cmd(USART2, ENABLE);
}

/* 字符串发送 */
void HMI_UART_SendString(char *str)
{
    while (*str)
    {
        USART_SendData(USART2, *str++);
        while (USART_GetFlagStatus(USART2, USART_FLAG_TXE) == RESET);
    }
}

/* 设置文本控件属性 */
void HMI_SetText(char *obj, char *text)
{
    char buf[100];

    sprintf(buf, "%s.txt=\"%s\"", obj, text);
    HMI_UART_SendString(buf);

    /* 串口屏结束符 */
    HMI_UART_SendString("\xFF\xFF\xFF");
}

/* 设置数值控件/进度条属性 */
void HMI_SetVal(const char *objName, uint8_t val)
{
    char buf[32];

    sprintf(buf, "%s.val=%d", objName, val);
    HMI_UART_SendString(buf);

    /* 串口屏结束符 */
    HMI_UART_SendString("\xFF\xFF\xFF");
}

/* 获取当前设定的显示周期数 (1 或 3) */
uint8_t HMI_GetPeriods(void) {
    return g_Display_Periods;
}

/* 检查是否有按键切换事件 (查询后自动清除标志位) */
uint8_t HMI_IsPeriodChanged(void) {
    if (g_Period_Changed_Flag) {
        g_Period_Changed_Flag = 0;
        return 1;
    }
    return 0;
}

/* USART2 接收中断服务函数：解析串口屏 printh 01 / printh 03 按键事件 */
void USART2_IRQHandler(void)
{
    if (USART_GetITStatus(USART2, USART_IT_RXNE) != RESET)
    {
        uint8_t rx = (uint8_t)USART_ReceiveData(USART2);
        
        if (rx == 0x01) {
            if (g_Display_Periods != 1) {
                g_Display_Periods = 1;
                g_Period_Changed_Flag = 1; // 触发刷新标记
            }
        } 
        else if (rx == 0x03) {
            if (g_Display_Periods != 3) {
                g_Display_Periods = 3;
                g_Period_Changed_Flag = 1; // 触发刷新标记
            }
        }
        
        USART_ClearITPendingBit(USART2, USART_IT_RXNE);
    }
}

