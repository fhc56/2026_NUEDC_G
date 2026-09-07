#include "FPGA_UART.h"

#include <stdio.h>
#include <string.h>



char rxbuf[100];

uint8_t rx_index=0;


uint8_t data_flag=0;



FPGA_DataTypeDef FPGA_Data;



/*
    USART1 初始化

    RX:
    PA10

*/

void FPGA_UART_Init(void)
{


GPIO_InitTypeDef GPIO_InitStructure;

USART_InitTypeDef USART_InitStructure;



/******** GPIO ********/


RCC_APB2PeriphClockCmd(
    RCC_APB2Periph_GPIOA |
    RCC_APB2Periph_USART1,
    ENABLE
);



GPIO_InitStructure.GPIO_Pin =
    GPIO_Pin_10;


GPIO_InitStructure.GPIO_Mode =
    GPIO_Mode_IN_FLOATING;


GPIO_Init(GPIOA,&GPIO_InitStructure);




/******** USART ********/


USART_InitStructure.USART_BaudRate =
    115200;


USART_InitStructure.USART_WordLength =
    USART_WordLength_8b;


USART_InitStructure.USART_StopBits =
    USART_StopBits_1;


USART_InitStructure.USART_Parity =
    USART_Parity_No;


USART_InitStructure.USART_HardwareFlowControl =
    USART_HardwareFlowControl_None;


USART_InitStructure.USART_Mode =
    USART_Mode_Rx;



USART_Init(
    USART1,
    &USART_InitStructure
);



USART_Cmd(
    USART1,
    ENABLE
);


}




/*
    主循环调用

    接收格式：

    Vpp,RMS,F_base,V_base,F_harm1,V_harm1,F_harm2,V_harm2\n


例如：

200,70,10000,500,20000,100,30000,50

*/


void FPGA_UART_Process(void)
{


char c;



while(
USART_GetFlagStatus(
USART1,
USART_FLAG_RXNE
)
!=RESET
)
{


c =
USART_ReceiveData(
USART1
);



if(c=='\n')
{


rxbuf[rx_index]=0;



sscanf(
rxbuf,
"%hu,%hu,%lu,%hu,%lu,%hu,%lu,%hu",
&FPGA_Data.Vpp,
&FPGA_Data.RMS,
&FPGA_Data.F_base,
&FPGA_Data.V_base,
&FPGA_Data.F_harm1,
&FPGA_Data.V_harm1,
&FPGA_Data.F_harm2,
&FPGA_Data.V_harm2
);



rx_index=0;



data_flag=1;



}


else
{


if(rx_index<99)
{

rxbuf[rx_index++]=c;

}

else
{

rx_index=0;

}


}



}


}




uint8_t FPGA_GetData(
FPGA_DataTypeDef *data
)
{


if(data_flag)
{


*data=FPGA_Data;


data_flag=0;


return 1;


}


return 0;


}
