// -- Notes -------------------------------------------------------------------
// The addresses on page zero, from $02 to $06, are used to store the driver's
// “global” variables.

// -- Hardware addresses ------------------------------------------------------
.var ACIA_BASE_LOW      = $05       // ACIA base (low)
.var ACIA_BASE_HIGH     = $06       // ACIA base (high)
.var ACIA_BASE          = ACIA_BASE_LOW

// -- Buffers -----------------------------------------------------------------
// Each buffer can hold a string of up to 255 characters (the maximum string
// length in standard C64 BASIC)
.var TX_BUFFER          = $C000     // TX top-down buffer
.var RX_BUFFER          = $C100     // RX circular buffer

// -- SYS addresses (to be adjusted according to the assembly) ----------------
// These routines are called by the BASIC program
.var INIT_ADDR          = $C200     // INIT_ACIA
.var TRANSMIT_ADDR      = $C230     // TRANSMIT
.var RECEIVE_ADDR       = $C260     // RECEIVE

// PTR = $61 (Source pointer, temporaire)
.var PTR = $61

DETECT_ACIA:
    lda #$80
    ldx #$DF
    jsr TEST_AT
    bcs DA_FOUND

    lda #$00
    ldx #$DE
    jsr TEST_AT
    bcs DA_FOUND

    lda #$00
    ldx #$DF
    jsr TEST_AT
    bcs DA_FOUND

    clc
    rts

DA_FOUND:
    sta ACIA_BASE_LOW
    stx ACIA_BASE_HIGH
    sec
    rts

TEST_AT:
    sta PTR
    stx PTR+1
    ldy #1
    lda (PTR),Y
    cmp #$FF
    beq TA_NO
    ldy #3
    lda (PTR),Y
    pha
    lda #$5A
    sta (PTR),Y
    dey
    lda (PTR),Y
    iny
    lda (PTR),Y
    cmp #$5A
    bne TA_RESTORE
    lda #$A5
    sta (PTR),Y
    dey
    lda (PTR),Y
    iny
    lda (PTR),Y
    cmp #$A5
    bne TA_RESTORE
    pla
    ldy #3
    sta (PTR),Y
    lda PTR
    ldx PTR+1
    sec
    rts

TA_RESTORE:
    pla
    ldy #3
    sta (PTR),Y
TA_NO:
    clc
    rts

INIT_ACIA:
    // Check if driver is already installed
    lda $0318
    cmp _chain+1
    bne _install
    lda $0319
    cmp _chain+2
    beq _uninstall

_install:
    // Détecter l'ACIA
    jsr DETECT_ACIA
    bcc _error

    // Save NMI original vector
    lda $0318
    sta _chain+1
    lda $0319
    sta _chain+2

    // Install dispatcher
    lda #<NMI_DISPATCHER
    sta $0318
    lda #>NMI_DISPATCHER
    sta $0319

    // Configure ACIA (8N1, IRQ RX/TX)
    ldy #$02                        // ACIA Command Register
    lda #$15
    sta (ACIA_BASE),Y
    ldy #$03                        // ACIA Control Register
    lda #$00
    sta (ACIA_BASE),Y

    // Reset pointers
    //lda #$00
    sta $02                         // TX : count
    sta $03                         // RX : head
    sta $04                         // RX : tail
    //rts

_error:
    rts

NMI_DISPATCHER:
    ldy #$01                        // ACIA Status Register
    lda (ACIA_BASE),Y
    and #$03
    beq _chain

    lsr
    bcs ISR_RX
    jmp ISR_TX

_chain:
    jmp $0000                       // Patched with original NMI vector

_uninstall:
    // Restore original NMI vector
    lda _chain+1
    sta $0318
    lda _chain+2
    sta $0319

    // Reset pointers (optional but clean)
    lda #$00
    sta $02
    sta $03
    sta $04
    rts

ISR_TX:
    ldx $02               // X = compteur TX
    beq _tx_done
    ldy #$00
    lda TX_BUFFER,X          // Lire buffer[X]
    ldy #$00
    sta (ACIA_BASE),Y  // Écrire dans DATA
    dec $02               // Décrémenter compteur
    bne _tx_exit
    ldy #$02
    lda #$09              // Désarmer IRQ TX
    sta (ACIA_BASE),Y  // CMD
_tx_done:
_tx_exit:
    rti

ISR_RX:
    ldy #$00
    lda (ACIA_BASE),Y  // Lire DATA
    ldx $03               // X = head
    sta RX_BUFFER,X          // buffer[head] = octet
    inx
    cpx $04               // head+1 == tail ?
    beq _rx_drop
    stx $03               // head = head+1
_rx_drop:
    rti

FIND_VAR:
    sta $63               // Octet nom 0 (Scratchpad)
    sty $64               // Octet nom 1
    lda $2D               // VARTAB low
    sta $61
    lda $2E               // VARTAB high
    sta $62

_floop:
    lda $2F               // ARYTAB low
    cmp $61
    bne _fcmp
    lda $30               // ARYTAB high
    cmp $62
    beq _fnotfound

_fcmp:
    ldy #$00
    lda ($61),Y           // Entrée[0]
    cmp $63
    bne _fnext
    iny
    lda ($61),Y           // Entrée[1]
    cmp $64
    beq _ffound

_fnext:
    lda $61
    clc
    adc #$07
    sta $61
    bcc _floop
    inc $62
    bcs _floop

_ffound:
    lda $61
    clc
    adc #$02
    sta $61               // Descripteur ptr low
    lda $62
    adc #$00
    sta $62               // Descripteur ptr high
    sec
    rts

_fnotfound:
    clc
    rts

TRANSMIT:
    lda #$54              // 'T'
    ldy #$D8              // 'X' | $80
    jsr FIND_VAR
    bcc _t_done

    ldy #$00
    lda ($61),Y           // Longueur
    beq _t_done
    sta $02               // Compteur TX

    iny
    lda ($61),Y           // Ptr données low
    sta $61
    iny
    lda ($61),Y           // Ptr données high
    sta $62

    ldx $02               // X = longueur
    ldy #$00
_t_copy:
    lda ($61),Y           // Source[Y]
    sta TX_BUFFER,X          // Dest[X] (inversé)
    iny
    dex
    bne _t_copy

    ldy #$02
    lda #$05              // RX + TX IRQ
    sta (ACIA_BASE),Y  // CMD
_t_done:
    rts

RECEIVE:
    lda #$52              // 'R'
    ldy #$D8              // 'X' | $80
    jsr FIND_VAR
    bcc _r_done

    lda $03               // Head
    sec
    sbc $04               // A = head - tail
    beq _r_empty

    sta $63               // Sauver count

    lda $61               // Sauver descripteur ptr
    pha
    lda $62
    pha

    // Allouer : FRETOP = FRETOP - count
    sec
    lda $33               // FRETOP low
    sbc $63
    sta $61               // Dest low (FAC1)
    lda $34               // FRETOP high
    sbc #$00
    sta $62               // Dest high

    // Copier buffer → zone allouée
    ldx $04               // Tail
    ldy #$00
_r_copy:
    lda RX_BUFFER,X          // Lire buffer[Tail]
    sta ($61),Y          // Écrire dest[Y]
    inx
    iny
    cpy $63
    bne _r_copy

    stx $04               // Tail = Head

    lda $61
    sta $33               // FRETOP low
    lda $62
    sta $34               // FRETOP high

    pla
    sta $62
    pla
    sta $61

    lda $63               // Count = longueur
    ldy #$00
    sta ($61),Y           // Descripteur[0] = longueur
    iny
    lda $33               // FRETOP low (ptr données)
    sta ($61),Y           // Descripteur[1] = ptr low
    iny
    lda $34
    sta ($61),Y           // Descripteur[2] = ptr high
    rts

_r_empty:
    lda #$00
    ldy #$00
    sta ($61),Y
    rts

_r_done:
    rts