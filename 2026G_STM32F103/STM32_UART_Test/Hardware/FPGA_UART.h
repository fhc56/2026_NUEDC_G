#ifndef __FPGA_UART_H
#define __FPGA_UART_H


#include "stm32f10x.h"



typedef struct
{

    uint16_t Vpp;

    uint16_t RMS;

    uint32_t F_base;

    uint16_t V_base;


    uint32_t F_harm1;

    uint16_t V_harm1;


    uint32_t F_harm2;

    uint16_t V_harm2;


}FPGA_DataTypeDef;



/*
    USART1
    PA10 RX

    接收FPGA数据
*/

void FPGA_UART_Init(void);



/*
    主循环调用
    负责接收解析数据
*/

void FPGA_UART_Process(void);



/*
    获取最新数据

    返回1表示有新数据
*/

uint8_t FPGA_GetData(
    FPGA_DataTypeDef *data
);



#endif
