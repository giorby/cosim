SECTIONS
{
  .vectors 0x00000000 : {KEEP(*(.vectors))}
  .exceptions 0x00000020 : {KEEP(*(.exceptions))}
}
