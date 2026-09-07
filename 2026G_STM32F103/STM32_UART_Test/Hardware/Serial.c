#include "Serial.h"

#include <string.h>

/*
 * FPGA frame, exactly 105 ASCII bytes:
 *
 * $G,VP=hhhh,RM=hhhh,F0=hhhhhhhh,N=h,F1=hhhhhhhh,A1=hhhh,
 * F2=hhhhhhhh,A2=hhhh,F3=hhhhhhhh,A3=hhhh,ST=hh*hh\r\n
 *
 * VP/RM/A1/A2/A3 are integer millivolts. F0/F1/F2/F3 are
 * integer hertz. All numeric characters are uppercase hexadecimal.
 * The final checksum is the XOR of bytes 1 through 99 inclusive.
 */
#define SERIAL_FRAME_BYTES 105u

static volatile Serial_MeasurementTypeDef Serial_LatestMeasurement;
static volatile uint8_t Serial_MeasurementFlag = 0u;

static volatile uint32_t Serial_FrameCount = 0u;
static volatile uint32_t Serial_ErrorCount = 0u;
static volatile uint32_t Serial_ByteCount = 0u;

/* Only USART1_IRQHandler accesses the parser working state. */
static uint8_t Serial_FrameBuffer[SERIAL_FRAME_BYTES];
static uint16_t Serial_FrameLength = 0u;
static uint8_t Serial_Receiving = 0u;


static int Serial_HexNibble(uint8_t Value)
{
    if ((Value >= (uint8_t)'0') && (Value <= (uint8_t)'9'))
    {
        return (int)(Value - (uint8_t)'0');
    }
    if ((Value >= (uint8_t)'A') && (Value <= (uint8_t)'F'))
    {
        return (int)(Value - (uint8_t)'A') + 10;
    }
    return -1;
}


static uint8_t Serial_ParseHex(const uint8_t *Text,
                               uint8_t Digits,
                               uint32_t *Value)
{
    uint8_t Index;
    uint32_t Parsed = 0u;
    int Nibble;

    for (Index = 0u; Index < Digits; Index++)
    {
        Nibble = Serial_HexNibble(Text[Index]);
        if (Nibble < 0)
        {
            return 0u;
        }
        Parsed = (Parsed << 4) | (uint32_t)Nibble;
    }

    *Value = Parsed;
    return 1u;
}


static uint8_t Serial_LiteralsValid(const uint8_t *Frame)
{
    static const uint8_t Prefix[] = "$G,VP=";
    static const uint8_t Rm[] = ",RM=";
    static const uint8_t F0[] = ",F0=";
    static const uint8_t Count[] = ",N=";
    static const uint8_t F1[] = ",F1=";
    static const uint8_t A1[] = ",A1=";
    static const uint8_t F2[] = ",F2=";
    static const uint8_t A2[] = ",A2=";
    static const uint8_t F3[] = ",F3=";
    static const uint8_t A3[] = ",A3=";
    static const uint8_t Status[] = ",ST=";

    return (memcmp(Frame + 0u, Prefix, sizeof(Prefix) - 1u) == 0) &&
           (memcmp(Frame + 10u, Rm, sizeof(Rm) - 1u) == 0) &&
           (memcmp(Frame + 18u, F0, sizeof(F0) - 1u) == 0) &&
           (memcmp(Frame + 30u, Count, sizeof(Count) - 1u) == 0) &&
           (memcmp(Frame + 34u, F1, sizeof(F1) - 1u) == 0) &&
           (memcmp(Frame + 46u, A1, sizeof(A1) - 1u) == 0) &&
           (memcmp(Frame + 54u, F2, sizeof(F2) - 1u) == 0) &&
           (memcmp(Frame + 66u, A2, sizeof(A2) - 1u) == 0) &&
           (memcmp(Frame + 74u, F3, sizeof(F3) - 1u) == 0) &&
           (memcmp(Frame + 86u, A3, sizeof(A3) - 1u) == 0) &&
           (memcmp(Frame + 94u, Status, sizeof(Status) - 1u) == 0) &&
           (Frame[100] == (uint8_t)'*') &&
           (Frame[103] == (uint8_t)'\r') &&
           (Frame[104] == (uint8_t)'\n');
}


static uint8_t Serial_DecodeFrame(const uint8_t *Frame,
                                  Serial_MeasurementTypeDef *Measurement)
{
    uint8_t Checksum = 0u;
    uint8_t Index;
    uint32_t Parsed;
    uint32_t ReceivedChecksum;

    if (!Serial_LiteralsValid(Frame))
    {
        return 0u;
    }

    for (Index = 1u; Index <= 99u; Index++)
    {
        Checksum ^= Frame[Index];
    }
    if ((!Serial_ParseHex(Frame + 101u, 2u, &ReceivedChecksum)) ||
        (Checksum != (uint8_t)ReceivedChecksum))
    {
        return 0u;
    }

    if (!Serial_ParseHex(Frame + 6u, 4u, &Parsed)) return 0u;
    Measurement->Vpp_mV = (uint16_t)Parsed;
    if (!Serial_ParseHex(Frame + 14u, 4u, &Parsed)) return 0u;
    Measurement->Rms_mV = (uint16_t)Parsed;
    if (!Serial_ParseHex(Frame + 22u, 8u, &Parsed)) return 0u;
    Measurement->Fundamental_Hz = Parsed;
    if ((!Serial_ParseHex(Frame + 33u, 1u, &Parsed)) || (Parsed > 3u))
        return 0u;
    Measurement->ComponentCount = (uint8_t)Parsed;

    if (!Serial_ParseHex(Frame + 38u, 8u, &Parsed)) return 0u;
    Measurement->Frequency_Hz[0] = Parsed;
    if (!Serial_ParseHex(Frame + 50u, 4u, &Parsed)) return 0u;
    Measurement->Amplitude_mV[0] = (uint16_t)Parsed;
    if (!Serial_ParseHex(Frame + 58u, 8u, &Parsed)) return 0u;
    Measurement->Frequency_Hz[1] = Parsed;
    if (!Serial_ParseHex(Frame + 70u, 4u, &Parsed)) return 0u;
    Measurement->Amplitude_mV[1] = (uint16_t)Parsed;
    if (!Serial_ParseHex(Frame + 78u, 8u, &Parsed)) return 0u;
    Measurement->Frequency_Hz[2] = Parsed;
    if (!Serial_ParseHex(Frame + 90u, 4u, &Parsed)) return 0u;
    Measurement->Amplitude_mV[2] = (uint16_t)Parsed;
    if (!Serial_ParseHex(Frame + 98u, 2u, &Parsed)) return 0u;
    Measurement->Status = (uint8_t)Parsed;

    return 1u;
}


static void Serial_CommitMeasurement(
    const Serial_MeasurementTypeDef *Measurement)
{
    uint8_t Index;

    Serial_LatestMeasurement.Vpp_mV = Measurement->Vpp_mV;
    Serial_LatestMeasurement.Rms_mV = Measurement->Rms_mV;
    Serial_LatestMeasurement.Fundamental_Hz = Measurement->Fundamental_Hz;
    Serial_LatestMeasurement.ComponentCount = Measurement->ComponentCount;
    for (Index = 0u; Index < 3u; Index++)
    {
        Serial_LatestMeasurement.Frequency_Hz[Index] =
            Measurement->Frequency_Hz[Index];
        Serial_LatestMeasurement.Amplitude_mV[Index] =
            Measurement->Amplitude_mV[Index];
    }
    Serial_LatestMeasurement.Status = Measurement->Status;
    Serial_MeasurementFlag = 1u;
}


static void Serial_ParseByte(uint8_t RxByte)
{
    Serial_MeasurementTypeDef Decoded;

    /* '$' always starts a fresh frame, allowing rapid resynchronisation. */
    if (RxByte == (uint8_t)'$')
    {
        Serial_FrameLength = 0u;
        Serial_Receiving = 1u;
    }

    if (!Serial_Receiving)
    {
        return;
    }

    if (Serial_FrameLength >= SERIAL_FRAME_BYTES)
    {
        Serial_ErrorCount++;
        Serial_FrameLength = 0u;
        Serial_Receiving = 0u;
        return;
    }

    Serial_FrameBuffer[Serial_FrameLength++] = RxByte;

    if (RxByte == (uint8_t)'\n')
    {
        if ((Serial_FrameLength == SERIAL_FRAME_BYTES) &&
            Serial_DecodeFrame(Serial_FrameBuffer, &Decoded))
        {
            Serial_CommitMeasurement(&Decoded);
            Serial_FrameCount++;
        }
        else
        {
            Serial_ErrorCount++;
        }

        Serial_FrameLength = 0u;
        Serial_Receiving = 0u;
    }
    else if (Serial_FrameLength == SERIAL_FRAME_BYTES)
    {
        /* A valid 105-byte frame must end in LF. */
        Serial_ErrorCount++;
        Serial_FrameLength = 0u;
        Serial_Receiving = 0u;
    }
}


#ifndef SERIAL_HOST_TEST
void Serial_Init(void)
{
    GPIO_InitTypeDef GPIO_InitStructure;
    USART_InitTypeDef USART_InitStructure;
    NVIC_InitTypeDef NVIC_InitStructure;
    volatile uint16_t Dummy;

    RCC_APB2PeriphClockCmd(
        RCC_APB2Periph_GPIOA | RCC_APB2Periph_USART1,
        ENABLE
    );

    /* Keep the original hardware connection: USART1_RX is PA10. */
    GPIO_InitStructure.GPIO_Pin = GPIO_Pin_10;
    GPIO_InitStructure.GPIO_Mode = GPIO_Mode_IPU;
    GPIO_InitStructure.GPIO_Speed = GPIO_Speed_50MHz;
    GPIO_Init(GPIOA, &GPIO_InitStructure);

    USART_InitStructure.USART_BaudRate = 115200;
    USART_InitStructure.USART_WordLength = USART_WordLength_8b;
    USART_InitStructure.USART_StopBits = USART_StopBits_1;
    USART_InitStructure.USART_Parity = USART_Parity_No;
    USART_InitStructure.USART_HardwareFlowControl =
        USART_HardwareFlowControl_None;
    USART_InitStructure.USART_Mode = USART_Mode_Rx;
    USART_Init(USART1, &USART_InitStructure);

    Serial_MeasurementFlag = 0u;
    Serial_FrameCount = 0u;
    Serial_ErrorCount = 0u;
    Serial_ByteCount = 0u;
    Serial_FrameLength = 0u;
    Serial_Receiving = 0u;

    /* Clear any stale status/data before enabling RX interrupts. */
    Dummy = USART1->SR;
    Dummy = USART1->DR;
    (void)Dummy;

    NVIC_PriorityGroupConfig(NVIC_PriorityGroup_2);
    NVIC_InitStructure.NVIC_IRQChannel = USART1_IRQn;
    NVIC_InitStructure.NVIC_IRQChannelPreemptionPriority = 1u;
    NVIC_InitStructure.NVIC_IRQChannelSubPriority = 0u;
    NVIC_InitStructure.NVIC_IRQChannelCmd = ENABLE;
    NVIC_Init(&NVIC_InitStructure);

    USART_ITConfig(USART1, USART_IT_RXNE, ENABLE);
    USART_Cmd(USART1, ENABLE);
}


/* USART interrupt reception prevents the bit-banged OLED update and key
 * debounce delays from losing bytes at 115200 bit/s. */
void USART1_IRQHandler(void)
{
    uint16_t Status;
    uint8_t RxByte;

    Status = USART1->SR;

    if (Status & (USART_SR_ORE | USART_SR_NE | USART_SR_FE | USART_SR_PE))
    {
        RxByte = (uint8_t)USART1->DR;
        (void)RxByte;
        Serial_ErrorCount++;
        Serial_FrameLength = 0u;
        Serial_Receiving = 0u;
        return;
    }

    if (Status & USART_SR_RXNE)
    {
        RxByte = (uint8_t)USART1->DR;
        Serial_ByteCount++;
        Serial_ParseByte(RxByte);
    }
}
#else
void Serial_TestFeedByte(uint8_t Byte)
{
    Serial_ByteCount++;
    Serial_ParseByte(Byte);
}
#endif


void Serial_Process(void)
{
    /* Reception is interrupt driven. Kept to preserve the original API. */
}


uint8_t Serial_GetMeasurement(Serial_MeasurementTypeDef *Measurement)
{
    uint8_t Available = 0u;
    uint8_t Index;

    if (Measurement == 0)
    {
        return 0u;
    }

#ifndef SERIAL_HOST_TEST
    NVIC_DisableIRQ(USART1_IRQn);
#endif
    if (Serial_MeasurementFlag)
    {
        Measurement->Vpp_mV = Serial_LatestMeasurement.Vpp_mV;
        Measurement->Rms_mV = Serial_LatestMeasurement.Rms_mV;
        Measurement->Fundamental_Hz =
            Serial_LatestMeasurement.Fundamental_Hz;
        Measurement->ComponentCount =
            Serial_LatestMeasurement.ComponentCount;
        for (Index = 0u; Index < 3u; Index++)
        {
            Measurement->Frequency_Hz[Index] =
                Serial_LatestMeasurement.Frequency_Hz[Index];
            Measurement->Amplitude_mV[Index] =
                Serial_LatestMeasurement.Amplitude_mV[Index];
        }
        Measurement->Status = Serial_LatestMeasurement.Status;
        Serial_MeasurementFlag = 0u;
        Available = 1u;
    }
#ifndef SERIAL_HOST_TEST
    NVIC_EnableIRQ(USART1_IRQn);
#endif

    return Available;
}


uint32_t Serial_GetFrameCount(void)
{
    return Serial_FrameCount;
}


uint32_t Serial_GetErrorCount(void)
{
    return Serial_ErrorCount;
}


uint32_t Serial_GetByteCount(void)
{
    return Serial_ByteCount;
}
