/*
Byte Handling Utilities
*/

HI_NYB(b) { ;sb
    return b & 0x0F
}

LO_NYB(b) { ;sb
    return (b >> 4) & 0x0F
}

NYB(b, n) { ;sb
    return (b >> (n * 4)) & 0xF
}

BYTE(b, n) { ;b
    return (b >> (n * 8)) & 0xFF
}
