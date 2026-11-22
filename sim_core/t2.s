     nop
     nop
L8:  beq x0, x0, L16
     nop
L16: beq x0, x0, L8
L20: jal x1, L28
     nop
L28: jal x1, L20
