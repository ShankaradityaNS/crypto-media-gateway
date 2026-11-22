     # install the trap handler
     lui  x1, 0x80000
     addi x1, x1, 0x40
     csrw mtvec, x1

     # a legitimate DTCM store, should succeed
     lui  x2, 0x80010
     addi x3, x0, 77
     sd   x3, 0(x2)

     # an unmapped store, should fault
     lui  x4, 0x70000
     sd   x3, 0(x4)

     # only reached if the handler returns here
     addi x5, x0, 55

halt:
     lui  x30, 0x90000
     sd   x0, 0(x30)
1:   jal  x0, 1b

     .org 0x40
handler:
     csrr x6, mcause          # expect 7 = store access fault
     csrr x7, mepc
     addi x7, x7, 4           # skip the faulting store
     csrw mepc, x7
     mret
