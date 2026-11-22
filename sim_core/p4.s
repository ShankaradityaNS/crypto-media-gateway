     # write a value into the DTCM
     lui  x1, 0x80010
     addi x2, x0, 0x111
     sd   x2, 0(x1)

     # write a different value into the signature region
     lui  x3, 0x80020
     addi x4, x0, 0x222
     sd   x4, 0(x3)

     # read both back; they must be independent
     ld   x5, 0(x1)           # expect 0x111
     ld   x6, 0(x3)           # expect 0x222

     # a second signature word, to check indexing
     addi x7, x0, 0x333
     sd   x7, 8(x3)
     ld   x8, 8(x3)           # expect 0x333

     # and confirm the first is untouched
     ld   x9, 0(x3)           # expect 0x222

halt:
     lui  x30, 0x90000
     sd   x0, 0(x30)
1:   jal  x0, 1b
