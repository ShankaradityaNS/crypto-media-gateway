     # install the trap handler
     lui  x1, 0x80000
     addi x1, x1, 0x40        # handler at 0x80000040
     csrrw x0, mtvec, x1

     addi x2, x0, 11          # marker: before the trap
     ecall                    # should trap to the handler
     addi x4, x0, 44          # runs after mret returns here+4

halt:
     lui  x30, 0x90000
     sd   x0, 0(x30)       # signal completion, exit code 0
1:   jal x0, 1b            # backstop

     .org 0x40
handler:
     addi x3, x0, 22          # marker: handler ran
     csrrs x5, mepc, x0       # read the faulting pc
     addi x5, x5, 4           # skip past the ecall
     csrrw x0, mepc, x5
     csrrs x6, mcause, x0     # read the cause (should be 11)
     mret
