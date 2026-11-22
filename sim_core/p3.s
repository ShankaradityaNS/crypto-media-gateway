     # install the trap handler
     lui  x1, 0x80000
     addi x1, x1, 0x40
     csrw mtvec, x1

     addi x2, x0, 33          # marker: reached before the jump

     # jump far outside the ITCM
     lui  x3, 0x60000
     jalr x0, 0(x3)           # should raise an instruction access fault

     addi x4, x0, 99          # never reached

halt:
     lui  x30, 0x90000
     sd   x0, 0(x30)
1:   jal  x0, 1b

     .org 0x40
handler:
     csrr x5, mcause          # expect 1 = instruction access fault
     addi x6, x0, 44          # marker: handler ran
     # do not return: the faulting pc is outside the ITCM, so
     # resuming there would fault again. Halt from the handler.
     lui  x30, 0x90000
     sd   x0, 0(x30)
2:   jal  x0, 2b
