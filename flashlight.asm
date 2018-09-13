
INCLUDE "hardware.inc"


SPRITE_SIZE = 8


SECTION "Header", ROM0[$0100]

EntryPoint:
    di
    jr Start
    nop

REPT $150 - $104
    db 0
ENDR



SECTION "Interrupt handlers", ROM0[$0040]

VBlankHandler::
    push af
    push bc
    ldh a, [hIsFlashlightEnabled]
    and a
    jp VBlankHandler2

STATHandler::
    push af
    push hl
    ldh a, [rSTAT]
    bit 2, a ; STATB_LYCF
    jr nz, .toggleRectangle
    ld h, a
    ; Wait for precisely Mode 2
    ; ld a, h
.triggerScanline0
    xor STATF_MODE00 | STATF_MODE10 ; Need to remove Mode 0 to avoid STAT blocking
    ldh [rSTAT], a
    ldh a, [hFlashlightCurrentLeft]
    ld l, a
    xor a
    ldh [rIF], a ; Clear IF for upcoming sync
    dec a ; ld a, $FF
    ldh [rBGP], a
    halt ; Halt with ints disabled to sync with Mode 2 perfectly
    nop ; Avoid halt bug... I'd prefer to never trigger it, though.
    ; Clear setup
    ld a, h ; Restore
    ldh [rSTAT], a
    ; Now, wait depending on the required offset (1 cycle offset per 8 pixels)
    ld h, HIGH(DelayFuncTable)
    ; l already loaded, there
    ld l, [hl]
    ld h, HIGH(DelayFunc)
    jp hl ; Ends on its own

.toggleRectangle
    xor STATF_MODE00
    ldh [rSTAT], a
    ld h, a ; For .triggerScanline0
    ; Put LYC at disable scanline (do it now to avoid STAT IRQ blocking)
    ldh a, [hFlashlightDisableScanline]
    ldh [rLYC], a
    ; Toggle sprites each time
    ldh a, [rLCDC]
    xor LCDCF_OBJON
    ldh [rLCDC], a
    ; Don't to this if disabling
    ld a, h
    and STATF_MODE00
    jr z, .done
    ; Starting on scanline 0 is extra special
    ldh a, [hFlashlightTop]
    and a
    ld a, h
    jr z, .triggerScanline0
.done
    ; Cancel IRQ bug
    ldh a, [rIF]
    and ~IEF_LCDC
    ldh [rIF], a
    pop hl
    pop af
    reti


DelayFunc:
REPT SCRN_X / 4 - 1
    nop
ENDR
    ; Do this before to save cycles after writing BGP
    ldh a, [rSTAT]
    and STATF_LYCF ; Check if we need to end in this scanline

    ; Do a thing here with BGP
    nop ; Delay to land "just right"
    ld a, $E4
    ldh [rBGP], a
    jr nz, .endRectangle

    ; Cancel IRQ bug
    ldh a, [rIF]
    and ~IEF_LCDC
    ldh [rIF], a
    pop hl
    pop af
    reti

.endRectangle
    ; We need to end this. Wait till HBlank, then set palette to black, and stop the process.
.waitHBlank
    ldh a, [rSTAT]
    and STATF_LCD
    jr nz, .waitHBlank
    dec a ; ld a, $FF
    ldh [rBGP], a
    ldh a, [rSTAT]

    ; Add some delay so VBlank doesn't trigger while removing STAT flag from IF
    ; Incredibly annoying that this falls "just right"
    ; AAAAAAAAAAAAAAAA
    nop
    nop
    nop
    nop
    jr STATHandler.toggleRectangle

SECTION "DelayFunc entry point table", ROM0,ALIGN[8]

DelayFuncTable::
DELAY_OFFSET = SCRN_X / 4 - 1
REPT SCRN_X / 4
    REPT 4
        db LOW(DelayFunc) + DELAY_OFFSET
    ENDR
DELAY_OFFSET = DELAY_OFFSET + (-1)
ENDR

SECTION "VBlank handler, second part", ROM0

VBlankHandler2:
    jr z, .noFlashlight
    ; Do not do flashlight if it's not displayed, it causes errors
    ldh a, [hFlashlightLeft]
    ldh [hFlashlightCurrentLeft], a ; This is re-read during the frame, so buffer it
    ld c, a
    cp SCRN_X
    jr nc, .oobFlashlight
    ldh a, [hFlashlightHeight]
    and a
    jr z, .oobFlashlight

    ; Set bits in STAT reg
    ldh a, [rSTAT]
    and ~STATF_MODE00
    ldh [rSTAT], a
    ; Cancel hw bug
    ldh a, [rIF]
    and ~IEF_LCDC
    ldh [rIF], a
    ; Calc WX
    ldh a, [hFlashlightWidth]
    add a, c
    jr c, .forceWX
    cp SCRN_X - 1
    jr c, .WXok
.forceWX
    ld a, SCRN_X
.WXok
    add a, 7
    ldh [rWX], a
    ; Set LYC
    ldh a, [hFlashlightTop]
    ld c, a
    and a ; Scanline 0 triggers differently, due to a lack of "previous" lines
    jr z, .specialTrigger
    dec a
.specialTrigger
    ldh [rLYC], a
    ; Set scanline where it must be disabled
    ldh a, [hFlashlightHeight]
    dec a
    add a, c
    cp $8F + 1
    jr c, .disableScanlineOK
    ld a, $8F
.disableScanlineOK
    ldh [hFlashlightDisableScanline], a
.finishOobFlashlight
    ; Transfer OAM!
    ld a, HIGH(wSievedOAM)
    call PerformDMA
    ; Set blackness for top half
    ld a, $FF
    jr .flashlightDone

.oobFlashlight
    ld a, SCRN_X + 7
    ldh [rWX], a
    ; This value can be re-used as a never-trigger LYC
    ldh [rLYC], a
    jr .finishOobFlashlight

.noFlashlight
    ld a, SCRN_X + 7
    ldh [rWX], a
    ldh [rLYC], a
    ld a, $E4
.flashlightDone
    ldh [rBGP], a

    xor a
    ldh [hVBlankFlag], a

    ; Poll joypad and update regs

    ld c, LOW(rP1)
    ld a, $20 ; Select D-pad
    ld [$ff00+c], a
REPT 6
    ld a, [$ff00+c]
ENDR
    or $F0 ; Set 4 upper bits (give them consistency)
    ld b, a
    swap b ; Put D-pad buttons in upper nibble

    ld a, $10 ; Select buttons
    ld [$ff00+c], a
REPT 6
    ld a, [$ff00+c]
ENDR

    or $F0 ; Set 4 upper bits
    xor b ; Mix with D-pad bits, and invert all bits (such that pressed=1) thanks to "or $F0"
    ld b, a

    ldh a, [hHeldButtons]
    cpl
    and b
    ldh [hPressedButtons], a

    ld a, b
    ldh [hHeldButtons], a

    ; Release joypad
    ld a, $30
    ld [$ff00+c], a

    pop bc
    pop af
    reti


SECTION "Main code", ROM0[$150]

Start::
    ld sp, $E000

.waitVBlank
    ldh a, [rLY]
    cp SCRN_Y
    jr c, .waitVBlank
    xor a
    ldh [rLCDC], a

    ; Init OAM buffers
    ld hl, wOAMBuffer
    ld de, InitialOAM
    ld c, $A0
.fillOAM
    ld a, [de]
    inc e;  inc de
    ld [hli], a
    dec c
    jr nz, .fillOAM
    ld hl, wSievedOAM
    xor a
    ld c, $A0
.fillSievedOAM
    ld [hli], a
    dec c
    jr nz, .fillSievedOAM

    ; Set up VRAM

    ; Write black tiles
    ld a, $FF
    ld hl, $8800
.nextTile
    ld c, $10
.fillBlack
    ld [hli], a
    dec c
    jr nz, .fillBlack
    srl a
    jr nz, .nextTile
    ld bc, $AA << 8 | 8
.fillGreyTile
    ld a, $FF
    ld [hli], a
    ld a, b
    cpl
    ld b, a
    ld [hli], a
    dec c
    jr nz, .fillGreyTile

    ld hl, $9C00
    ld bc, SCRN_Y_B * SCRN_VX_B
.fillWindow
    ld a, $80
    ld [hli], a
    dec bc
    ld a, b
    or c
    jr nz, .fillWindow

    ; Copy BG (font) tiles
    ld hl, $9200
    ld de, Font
    ld bc, FontEnd - Font
.copyFont
    ld a, [de]
    inc de
    ld [hli], a
    dec bc
    ld a, b
    or c
    jr nz, .copyFont

    ; Write BG tilemap
    ld hl, $9800
    ld de, BGTilemap
    ld b, SCRN_Y_B
.nextRow
    ld c, SCRN_X_B
.copyRow
    ld a, [de]
    inc de
    ld [hli], a
    dec c
    jr nz, .copyRow
    ld a, l
    add a, SCRN_VX_B - SCRN_X_B
    ld l, a
    adc a, h
    sub l
    ld h, a
    dec b
    jr nz, .nextRow

    ; Copy OAM DMA
    ld hl, OAMDMA
    ld bc, (OAMDMAEnd - OAMDMA) << 8 | LOW(PerformDMA)
.copyOAMDMA
    ld a, [hli]
    ld [$ff00+c], a
    inc c
    dec b
    jr nz, .copyOAMDMA

    xor a
    ldh [hHeldButtons], a
    ldh [hPressedButtons], a

    inc a ; ld a, 1
    ldh [hIsFlashlightEnabled], a
    ld a, 90
    ldh [hFlashlightTop], a
    ldh [hFlashlightLeft], a
    ld a, 20
    ldh [hFlashlightHeight], a
    ldh [hFlashlightWidth], a

    xor a
    ldh [rWY], a
    ldh [rSCY], a
    ldh [rSCX], a
    ld a, $E4
    ldh [rOBP0], a
    ld a, STATF_LYC
    ldh [rSTAT], a
IF SPRITE_SIZE == 8
    ld a, LCDCF_ON | LCDCF_WIN9C00 | LCDCF_WINON | LCDCF_BGON
ELIF SPRITE_SIZE == 16
    ld a, LCDCF_ON | LCDCF_WIN9C00 | LCDCF_WINON | LCDCF_OBJ16 | LDCF_BGON
ELSE
    FAIL "Sprite size must be either 8 or 16"
ENDC
    ldh [rLCDC], a

    ld a, IEF_VBLANK | IEF_LCDC
    ldh [rIE], a
    xor a
    ei ; Ensure we start on a clean basis
    ldh [rIF], a


MainLoop::
    ; Wait for VBlank
    ld a, 1
    ldh [hVBlankFlag], a
.waitVBlank
    halt
    ldh a, [hVBlankFlag]
    and a
    jr nz, .waitVBlank

    ; Check input
    ldh a, [hHeldButtons]
    ld b, a
    and PADF_A ; A edits size, not position
    add a, a
    add a, LOW(hFlashlightTop)
    ld c, a
    ld a, [$ff00+c]
    bit PADB_UP, b
    jr z, .noUp
    dec a
.noUp
    bit PADB_DOWN, b
    jr z, .noDown
    inc a
.noDown
    ld [$ff00+c], a
    inc c
    ld a, [$ff00+c]
    bit PADB_LEFT, b
    jr z, .noLeft
    dec a
.noLeft
    bit PADB_RIGHT, b
    jr z, .noRight
    inc a
.noRight
    ld [$ff00+c], a

    ; Sieve OAM
    ld hl, wSievedOAM
    ; Write left masking sprites
    ldh a, [hFlashlightHeight]
    cp SCRN_X
    jr c, .heightOk
    ld a, SCRN_X
.heightOk
    add a, SPRITE_SIZE - 1
    and -SPRITE_SIZE
IF SPRITE_SIZE == 8
    rra
    rra
    rra
ELSE
    swap a
ENDC
    ld c, a
    ld e, a ; Save this for right border, maybe
    ldh a, [hFlashlightLeft]
    and a
    jr z, .noLeftEdgeSprites
    cp SCRN_X + 8
    jr nc, .noLeftEdgeSprites
    ld b, a
    ldh a, [hFlashlightTop]
    add a, 8
.writeLeftEdgeSprite
    cp SCRN_Y + 8
    jr nc, .noLeftEdgeSprites
    add a, 8
    ld [hli], a
    ld [hl], b
    inc l ; inc hl
    ld [hl], $80
    inc l ; inc hl
    ld [hl], 0
    inc l ; inc hl
    dec c
    jr nz, .writeLeftEdgeSprite
.noLeftEdgeSprites
    ; WX = $A6 (1 px on-screen) behaves incorrectly, therefore sprites are used instead
    ldh a, [hFlashlightLeft]
    ld c, a
    ldh a, [hFlashlightWidth]
    add a, c
    cp SCRN_X - 1
    jr nz, .noRightEdgeSprites
    ; Put sprites to form right border
    ldh a, [hFlashlightWidth]
    add a, b
    add a, 8
    ld b, a
    ldh a, [hFlashlightTop]
    add a, 8
.writeRightEdgeSprite
    cp SCRN_Y + 8
    jr nc, .noRightEdgeSprites
    add a, 8
    ld [hli], a
    ld [hl], b
    inc l ; inc hl
    ld [hl], $80
    inc l ; inc hl
    ld [hl], 0
    inc l ; inc hl
    dec e
    jr nz, .writeRightEdgeSprite
.noRightEdgeSprites
    ld de, wOAMBuffer
.sieveSprite
    ; Check if sprite is fully outside of the flashlight window
    ; Check if sprite Y > flashlight Y (remember that there's a 16-px offset!)
    ldh a, [hFlashlightTop]
IF SPRITE_SIZE == 8
    add a, 9
ELSE
    inc a
ENDC
    ld b, a
    ld a, [de]
    ld c, a
    sub b
    jr c, .culledOut
    inc a ; Get offset
    ld b, a
    ; Check if sprite is within bounds (ofs < h)
    ldh a, [hFlashlightHeight]
    add a, 7
    cp b
    jr c, .culledOut
    inc e ; inc de
    ; Check if sprite X > flashlight X (again, 8-px offset)
    ldh a, [hFlashlightLeft]
    inc a
    ld b, a
    ld a, [de]
    dec e ; dec de
    sub b
    jr c, .culledOut
    inc a ; Get offset
    ld b, a
    ; Check if sprite is within bounds (ofs < w)
    ldh a, [hFlashlightWidth]
    add a, 7
    cp b
    jr c, .culledOut
    inc e ; inc de
    sub 7
    sub b
    jr nc, .notClipped
    ld b, a
    ; Add sprite on top of this one, to apply clipping
    ld a, c
    ld [hli], a
    ld a, [de]
    ld [hli], a
    ld a, b
    and %111
    add a, $80
    ld [hli], a
    xor a
    ld [hli], a
.notClipped
    ld a, c
    ld [hli], a
REPT 3
    ld a, [de]
    inc e ; inc de
    ld [hli], a
ENDR
    ld a, e
    cp $A0
    jr c, .sieveSprite
    jr .finishSieve
.culledOut
    ld a, e
    add a, 4
    ld e, a
    cp $A0
    jr c, .sieveSprite
    ; Fill rest of sieved OAM with nothing
.finishSieve
    ld a, l
    cp $A0
    jr nc, .doneSieving
    ld [hl], 0
    add a, 4
    ld l, a
    jr .finishSieve
.doneSieving

    jp MainLoop



SECTION "OAM DMA routine", ROM0

OAMDMA::
    ldh [rDMA], a
    ld a, $28
.wait
    dec a
    jr nz, .wait
    ret
OAMDMAEnd::



SECTION "OAM buffer", WRAM0,ALIGN[8]

wOAMBuffer::
    ds $A0


SECTION "Sieved OAM", WRAM0,ALIGN[8]

wSievedOAM::
    ds $A0



SECTION "Misc. variables", HRAM

hHeldButtons::
    db
hPressedButtons::
    db

hVBlankFlag::
    db


SECTION "Flashlight variables", HRAM

hIsFlashlightEnabled::
    db

hFlashlightTop::
    db
hFlashlightLeft::
    db
hFlashlightHeight::
    db
hFlashlightWidth::
    db

hFlashlightDisableScanline::
    db
hFlashlightCurrentLeft::
    db


SECTION "OAM DMA", HRAM

PerformDMA::
    ds OAMDMAEnd - OAMDMA



SECTION "Font", ROM0

Font::
	dw $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000 ; Space
	
	; Symbols 1
	dw $8000, $8000, $8000, $8000, $8000, $0000, $8000, $0000
	dw $0000, $6C00, $6C00, $4800, $0000, $0000, $0000, $0000
	dw $4800, $FC00, $4800, $4800, $4800, $FC00, $4800, $0000
	dw $1000, $7C00, $9000, $7800, $1400, $F800, $1000, $0000
	dw $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000 ; %, empty slot for now
	dw $6000, $9000, $5000, $6000, $9400, $9800, $6C00, $0000
	dw $0000, $3800, $3800, $0800, $1000, $0000, $0000, $0000
	dw $1800, $2000, $2000, $2000, $2000, $2000, $1800, $0000
	dw $1800, $0400, $0400, $0400, $0400, $0400, $1800, $0000
	dw $0000, $1000, $5400, $3800, $5400, $1000, $0000, $0000
	dw $0000, $1000, $1000, $7C00, $1000, $1000, $0000, $0000
	dw $0000, $0000, $0000, $0000, $3000, $3000, $6000, $0000
	dw $0000, $0000, $0000, $7C00, $0000, $0000, $0000, $0000
	dw $0000, $0000, $0000, $0000, $0000, $6000, $6000, $0000
	dw $0000, $0400, $0800, $1000, $2000, $4000, $8000, $0000
	dw $3000, $5800, $CC00, $CC00, $CC00, $6800, $3000, $0000
	dw $3000, $7000, $F000, $3000, $3000, $3000, $FC00, $0000
	dw $7800, $CC00, $1800, $3000, $6000, $C000, $FC00, $0000
	dw $7800, $8C00, $0C00, $3800, $0C00, $8C00, $7800, $0000
	dw $3800, $5800, $9800, $FC00, $1800, $1800, $1800, $0000
	dw $FC00, $C000, $C000, $7800, $0C00, $CC00, $7800, $0000
	dw $7800, $CC00, $C000, $F800, $CC00, $CC00, $7800, $0000
	dw $FC00, $0C00, $0C00, $1800, $1800, $3000, $3000, $0000
	dw $7800, $CC00, $CC00, $7800, $CC00, $CC00, $7800, $0000
	dw $7800, $CC00, $CC00, $7C00, $0C00, $CC00, $7800, $0000
	dw $0000, $C000, $C000, $0000, $C000, $C000, $0000, $0000
	dw $0000, $C000, $C000, $0000, $C000, $4000, $8000, $0000
	dw $0400, $1800, $6000, $8000, $6000, $1800, $0400, $0000
	dw $0000, $0000, $FC00, $0000, $FC00, $0000, $0000, $0000
	dw $8000, $6000, $1800, $0400, $1800, $6000, $8000, $0000
	dw $7800, $CC00, $1800, $3000, $2000, $0000, $2000, $0000
	dw $0000, $2000, $7000, $F800, $F800, $F800, $0000, $0000 ; "Up" arrow, not ASCII but otherwise unused :P
	
	; Uppercase
	dw $3000, $4800, $8400, $8400, $FC00, $8400, $8400, $0000
	dw $F800, $8400, $8400, $F800, $8400, $8400, $F800, $0000
	dw $3C00, $4000, $8000, $8000, $8000, $4000, $3C00, $0000
	dw $F000, $8800, $8400, $8400, $8400, $8800, $F000, $0000
	dw $FC00, $8000, $8000, $FC00, $8000, $8000, $FC00, $0000
	dw $FC00, $8000, $8000, $FC00, $8000, $8000, $8000, $0000
	dw $7C00, $8000, $8000, $BC00, $8400, $8400, $7800, $0000
	dw $8400, $8400, $8400, $FC00, $8400, $8400, $8400, $0000
	dw $7C00, $1000, $1000, $1000, $1000, $1000, $7C00, $0000
	dw $0400, $0400, $0400, $0400, $0400, $0400, $F800, $0000
	dw $8400, $8800, $9000, $A000, $E000, $9000, $8C00, $0000
	dw $8000, $8000, $8000, $8000, $8000, $8000, $FC00, $0000
	dw $8400, $CC00, $B400, $8400, $8400, $8400, $8400, $0000
	dw $8400, $C400, $A400, $9400, $8C00, $8400, $8400, $0000
	dw $7800, $8400, $8400, $8400, $8400, $8400, $7800, $0000
	dw $F800, $8400, $8400, $F800, $8000, $8000, $8000, $0000
	dw $7800, $8400, $8400, $8400, $A400, $9800, $6C00, $0000
	dw $F800, $8400, $8400, $F800, $9000, $8800, $8400, $0000
	dw $7C00, $8000, $8000, $7800, $0400, $8400, $7800, $0000
	dw $7C00, $1000, $1000, $1000, $1000, $1000, $1000, $0000
	dw $8400, $8400, $8400, $8400, $8400, $8400, $7800, $0000
	dw $8400, $8400, $8400, $8400, $8400, $4800, $3000, $0000
	dw $8400, $8400, $8400, $8400, $B400, $CC00, $8400, $0000
	dw $8400, $8400, $4800, $3000, $4800, $8400, $8400, $0000
	dw $4400, $4400, $4400, $2800, $1000, $1000, $1000, $0000
	dw $FC00, $0400, $0800, $1000, $2000, $4000, $FC00, $0000
	
	; Symbols 2
	dw $3800, $2000, $2000, $2000, $2000, $2000, $3800, $0000
	dw $0000, $8000, $4000, $2000, $1000, $0800, $0400, $0000
	dw $1C00, $0400, $0400, $0400, $0400, $0400, $1C00, $0000
	dw $1000, $2800, $0000, $0000, $0000, $0000, $0000, $0000
	dw $0000, $0000, $0000, $0000, $0000, $0000, $0000, $FF00
	dw $C000, $6000, $0000, $0000, $0000, $0000, $0000, $0000
	
	; Lowercase
	dw $0000, $0000, $7800, $0400, $7C00, $8400, $7800, $0000
	dw $8000, $8000, $8000, $F800, $8400, $8400, $7800, $0000
	dw $0000, $0000, $7C00, $8000, $8000, $8000, $7C00, $0000
	dw $0400, $0400, $0400, $7C00, $8400, $8400, $7800, $0000
	dw $0000, $0000, $7800, $8400, $F800, $8000, $7C00, $0000
	dw $0000, $3C00, $4000, $FC00, $4000, $4000, $4000, $0000
	dw $0000, $0000, $7800, $8400, $7C00, $0400, $F800, $0000
	dw $8000, $8000, $F800, $8400, $8400, $8400, $8400, $0000
	dw $0000, $1000, $0000, $1000, $1000, $1000, $1000, $0000
	dw $0000, $1000, $0000, $1000, $1000, $1000, $E000, $0000
	dw $8000, $8000, $8400, $9800, $E000, $9800, $8400, $0000
	dw $1000, $1000, $1000, $1000, $1000, $1000, $1000, $0000
	dw $0000, $0000, $6800, $9400, $9400, $9400, $9400, $0000
	dw $0000, $0000, $7800, $8400, $8400, $8400, $8400, $0000
	dw $0000, $0000, $7800, $8400, $8400, $8400, $7800, $0000
	dw $0000, $0000, $7800, $8400, $8400, $F800, $8000, $0000
	dw $0000, $0000, $7800, $8400, $8400, $7C00, $0400, $0000
	dw $0000, $0000, $BC00, $C000, $8000, $8000, $8000, $0000
	dw $0000, $0000, $7C00, $8000, $7800, $0400, $F800, $0000
	dw $0000, $4000, $F800, $4000, $4000, $4000, $3C00, $0000
	dw $0000, $0000, $8400, $8400, $8400, $8400, $7800, $0000
	dw $0000, $0000, $8400, $8400, $4800, $4800, $3000, $0000
	dw $0000, $0000, $8400, $8400, $8400, $A400, $5800, $0000
	dw $0000, $0000, $8C00, $5000, $2000, $5000, $8C00, $0000
	dw $0000, $0000, $8400, $8400, $7C00, $0400, $F800, $0000
	dw $0000, $0000, $FC00, $0800, $3000, $4000, $FC00, $0000
	
	; Symbols 3
	dw $1800, $2000, $2000, $4000, $2000, $2000, $1800, $0000
	dw $1000, $1000, $1000, $1000, $1000, $1000, $1000, $0000
	dw $3000, $0800, $0800, $0400, $0800, $0800, $3000, $0000
	dw $0000, $0000, $4800, $A800, $9000, $0000, $0000, $0000
	
	dw $C000, $E000, $F000, $F800, $F000, $E000, $C000, $0000 ; Left arrow
FontEnd::


SECTION "OAM", ROM0

InitialOAM::
    db $6A, $68, $88, $00
    db $30, $30, $88, $00
    db $30, $39, $88, $00
    db $30, $42, $88, $00
    db $30, $4B, $88, $00
    db $30, $54, $88, $00
    db $30, $5D, $88, $00
    db $30, $66, $88, $00
    db $30, $6F, $88, $00
    db $30, $78, $88, $00
    db $30, $81, $88, $00
InitialOAMEnd:
REPT $A0 - (InitialOAMEnd - InitialOAM)
    db 0
ENDR


SECTION "BG tilemap", ROM0

BGTilemap::
    db "BUP                 "
    db "                    "
    db "                    "
    db "                    "
    db "                    "
    db "                    "
    db "                    "
    db "                    "
    db "                    "
    db "                    "
    db "                    "
    db "                    "
    db "                    "
    db "                    "
    db "                    "
    db "                    "
    db "                    "
    db "                 BUP"
