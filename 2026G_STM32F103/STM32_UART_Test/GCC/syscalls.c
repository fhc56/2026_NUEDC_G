#include <errno.h>
#include <stddef.h>

extern char _end;
extern char _estack;


void _init(void)
{
}


void *_sbrk(ptrdiff_t Increment)
{
    static char *HeapEnd;
    char *Previous;
    char *HeapLimit = &_estack - 0x400;

    if (HeapEnd == 0)
    {
        HeapEnd = &_end;
    }

    Previous = HeapEnd;
    if ((HeapEnd + Increment) > HeapLimit)
    {
        errno = ENOMEM;
        return (void *)-1;
    }

    HeapEnd += Increment;
    return Previous;
}
