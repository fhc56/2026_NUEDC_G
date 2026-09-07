#include "Serial.h"

#include <stdio.h>
#include <string.h>


static int FeedFrame(const char *Frame)
{
    size_t Index;

    for (Index = 0u; Index < strlen(Frame); Index++)
    {
        Serial_TestFeedByte((uint8_t)Frame[Index]);
    }
    return 0;
}


int main(void)
{
    static const char ValidFrame[] =
        "$G,VP=0123,RM=0045,F0=00002710,N=3,F1=00002710,A1=000A,"
        "F2=00007530,A2=0014,F3=0000C350,A3=001E,ST=A5*45\r\n";
    char BadFrame[sizeof(ValidFrame)];
    Serial_MeasurementTypeDef Measurement;

    if ((sizeof(ValidFrame) - 1u) != 105u)
    {
        puts("SERIAL_TEST_BAD_VECTOR_LENGTH");
        return 1;
    }

    FeedFrame(ValidFrame);
    if (!Serial_GetMeasurement(&Measurement))
    {
        puts("SERIAL_TEST_NO_VALID_FRAME");
        return 1;
    }
    if ((Measurement.Vpp_mV != 0x0123u) ||
        (Measurement.Rms_mV != 0x0045u) ||
        (Measurement.Fundamental_Hz != 10000u) ||
        (Measurement.ComponentCount != 3u) ||
        (Measurement.Frequency_Hz[0] != 10000u) ||
        (Measurement.Frequency_Hz[1] != 30000u) ||
        (Measurement.Frequency_Hz[2] != 50000u) ||
        (Measurement.Amplitude_mV[0] != 10u) ||
        (Measurement.Amplitude_mV[1] != 20u) ||
        (Measurement.Amplitude_mV[2] != 30u) ||
        (Measurement.Status != 0xA5u))
    {
        puts("SERIAL_TEST_DECODE_MISMATCH");
        return 1;
    }

    memcpy(BadFrame, ValidFrame, sizeof(ValidFrame));
    BadFrame[6] = '1';
    FeedFrame(BadFrame);
    if ((Serial_GetMeasurement(&Measurement) != 0u) ||
        (Serial_GetErrorCount() != 1u))
    {
        puts("SERIAL_TEST_BAD_CHECKSUM_ACCEPTED");
        return 1;
    }

    /* Noise and a partial frame must be discarded when the next '$' arrives. */
    FeedFrame("noise$G,VP=0000");
    FeedFrame(ValidFrame);
    if ((!Serial_GetMeasurement(&Measurement)) ||
        (Serial_GetFrameCount() != 2u) ||
        (Measurement.Fundamental_Hz != 10000u))
    {
        puts("SERIAL_TEST_RESYNC_FAIL");
        return 1;
    }

    puts("STM32_SERIAL_PROTOCOL_PASS");
    return 0;
}
