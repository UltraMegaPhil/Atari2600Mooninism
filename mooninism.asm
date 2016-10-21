;----------------------------------------------;
;                                              ;
;                  MOONINISM                   ;
;                 -----------                  ;
;                                              ;
; Philip Bull 2016                             ;
;                                              ;
;----------------------------------------------;


;
; First inform the assembler which processor we are coding for
; The 2600 uses a 6507, which is basically a 6502, with fewer address lines and
; interrupts disabled
;
    PROCESSOR 6502

;
; Now include all the Atari support stuff
;
    INCLUDE "vcs.h"
    INCLUDE "macro.h"


;
; Constants
;
BG_COLOR                        = $00
PLAYFIELD_COLOR                 = $3F
ERR_SPRITE_HEIGHT               = 17
ERR_SPRITE_FACE_DURATION        = 4     ; Duration (in frames) player sprite face is on screen
NUM_ERR_SPRITE_ANIMATION_FACES  = 3     ; Number of animation frames.
SCREEN_WIDTH                    = 160
SCREEN_HEIGHT                   = 192
SCREEN_CENTER_X                 = (SCREEN_WIDTH / 2)
SCREEN_CENTER_Y                 = (SCREEN_HEIGHT / 2)


;
; Variables
;
; (the ORG (origin) directive tells the assembler where in memory to place
; all the code that follows - $F000 is the preferred address for Atari programs)
;

    SEG.U variables
    ORG $80

playerPosY                      ds 1    ; Y-position of player sprite
playerPosX                      ds 1    ; The actual X-position of the player
playerPosXCoarseFine            ds 1    ; Byte containing both the coarse (low nibble)
                                        ; and fine (high nibble) position values for the 
                                        ; player sprite

playerSpriteCurrentLine         ds 1    ; The line we are currently drawing of the player sprite
playerSpriteCurrentLineColor    ds 1    ; The color of the line we are currently drawing
playerSpriteCurrentLineGraphic  ds 1    ;

playerFaceDuration              ds 1    ; Duration (in frames) player sprite face is on screen
playerFaceDelay                 ds 1    ;
playerSpriteMoving              ds 1    ; Whether the player sprite is actually moving


;
; Start of program code
;
    SEG
    ORG $F000

Start

;
; When the Atari starts up, all its memory is uninitialized. 
; Do the following to tidy everything up
;
    SEI             ; Disable interrupts
    CLD             ; Clear BCD math bit.
    LDX #$FF        ; set X to the top of the memory we have,
    TXS             ; ...and set the stack pointer to what X is...i.e. #$FF aka 255
    
;
; Walk through our memory and zero it all out
;
    LDA #0          ; Put Zero into A (X is at $FF)
ClearMem
    STA 0,X         ; Store accumulator into location X (offset by 0)
    DEX             ; Decrement X
    BNE ClearMem    ; If the last command resulted in something
                    ; non-zero, branch to "ClearMem"

;
; Game setup
;
    LDA #BG_COLOR
    STA COLUBK      ; Store color into background color register

    LDA #SCREEN_CENTER_X
    STA playerPosX

    LDA #SCREEN_CENTER_Y
    STA playerPosY

    LDA #PLAYFIELD_COLOR
    STA COLUPF

    LDA #ERR_SPRITE_FACE_DURATION
    STA playerFaceDuration
    STA playerFaceDelay

    LDA #0
    STA NUSIZ0
    STA REFP0

; -----------------------------------------------------------------------------


;
; Start of main loop (one game frame occurs here)
;
; We have four distinct sections:
;   Vertical Sync - starts up new frame
;   Vertical Blank - 37 scanlines during we which we can do game logic
;   Horizontal Blank/Scanline drawing (we have some hblank time for game code here,
;                                       but it's mainly for rendering)
;   Overscan - 30 scanlines for game logic
;
    LDA #%00000010  ; First time through, blank the screen. Once we are in the main loop
    STA VBLANK      ; this will be done in our overscan section

MainLoop

;
; Vertical Sync
; -------------
; 
; According to SPG, bit D1 of VSYNC needs to be set to 1 for at least two scanlines
; and then set back to 0 to trigger a new frame
;
    LDA #%00000010
    STA VSYNC

    STA WSYNC   ; Hold it for two scanlines...we could do something in this period
    STA WSYNC   ; but for now just hold.

    LDA #%00000000
    STA VSYNC   ; Turn off VSYNC

; -----------------------------------------------------------------------------


;
; Vertical Blank (37 scanlines)
; -----------------------------
;
; We will probably want to do some game logic execution during the 37 scanline period
; we have available here. The best way to do this is to fire off a timer which will run
; in the background and then execute our code. The code we execute should take no longer
; than 37 scanlines. Once we have done everything we want to do we sit in a loop waiting
; for the timer to complete.
;
; Each scanline takes 76 cycles (which are the same thing our clock is geared to)
; The VBLANK period therefore amounts to 2812 cycles (37 x 76)
; However, we need to account for the 6 cycles it takes to set the timer. Plus the 
; checking loop is only accurate to 6 cycles, which gives us 12 cycles subtracted
; from the 2812.
; (2812 - 12) = 2800.
;
; The timer we are going to use is TIM64T, which performs one tick every 64 cycles. 
; Therefore we require (2800 / 64) = 43.75 ticks (but we round down to 43)
;
    LDA #43     ; Load "43" into the accumulator
    STA TIM64T  ; Store the accumulated value in the TIM64T register

;
; This is now the area in which we can execute our code, provided it doesn't take any 
; longer than 37 scanlines
;
    ;
    ; Horizontal player sprite positioning
    ;
    LDX playerPosX
    LDA xPositionTable,x
    STA playerPosXCoarseFine
    AND #$0F                    ; Accumulator contains coarse position
    TAX                         ; X-register now contains coarse position
    STA WSYNC

Position                        ; Coarse positioning loop
    DEX
    BNE Position
    STA RESP0                   ; Strobe RESP0
    STA WSYNC

                                ; Now do fine positioning adjustment
    LDA playerPosXCoarseFine
    AND #$F0                    ; Clear coarse positioning nibble
    STA HMP0


;
; Once we've done our stuff, we are going to sit in a tight loop and wait for the timer
; to end
;
VBlankLoop
    LDA INTIM           ; Load timer value into accumulator
    BNE VBlankLoop      ; Loop back if the timer value is not zero

    ; Timer has expired but there's a good chance we'll be some way through a scanline
    ; here, so sit tight until we get to the end and then turn off the VBLANK
    STA WSYNC
    STA HMOVE    
    STA VBLANK          ; End VBLANK period with the zero we have in the accumulator

; -----------------------------------------------------------------------------


;
; Horizontal Blank/Scanline draw
; ------------------------------
;
; Here we are going to manually count down each scanline. The Y register will hold
; the current scanline value
;   

    LDY #192        ; Using Y register as scanline counter and counting off 192 scanlines

    LDA #228
    STA TIM64T      ; 1 scanline = 228 color clocks
                    ; 192 scanlines = 43,776 color clocks = 14,592 machine cycles (43,776 / 3)
                    ; 14,592 = 228 timer ticks (14,592 / 64)


ScanLoop

Picture	

    LDA playerSpriteCurrentLineGraphic      ; Load player sprite graphics and color
    STA GRP0
    LDA playerSpriteCurrentLineColor
    STA COLUP0

    LDA #0
    STA playerSpriteCurrentLineGraphic      ; Clear player graphics buffer

    CPY playerPosY                          ; Check if this is the line where we draw the player sprite
    BNE SkipLineInit                        ;
    LDA (#ERR_SPRITE_HEIGHT - 1)            ; Setup our sprite line counter
    STA playerSpriteCurrentLine

SkipLineInit
    
    LDA playerSpriteCurrentLine
    BMI SkipPlayerDraw
    
    TAX
    
    LDA ErrSpriteGraphicTable,x
    STA playerSpriteCurrentLineGraphic
    
    LDA ErrSpriteColorTable,x
    STA playerSpriteCurrentLineColor
    
    DEC playerSpriteCurrentLine
    
SkipPlayerDraw

    DEY         ; Decrement scanline counter
    STA WSYNC

    LDA INTIM
    BNE ScanLoop


    STA HMOVE

; -----------------------------------------------------------------------------


;
; Overscan
; --------
;
; Same deal as the VBLANK timer, except we have 30 scanlines to work with.
; We will set up the timer accordingly. Our two loads (one for the VBLANK and
; one to set the timer value) take up 5 and 6 clock cycles respectively (11 in total) and the
; timer check loop requires 6.
;
;   (30 * 76) = 2280 clock cycles
; (2280 - 17) = 2263
; (2263 / 64) = 35.359
; ~35 timer ticks 
;
    LDA #2          ; Write "2" for the VBLANK
    STA VBLANK      ; Make TIA output invisible for the overscan,
                    ; (and keep it that way for the vsync and vblank)

    LDA #35         ; Load "35" into the accumulator
    STA TIM64T      ; Store the accumulated value in the TIM64T register


;
; This is now the area in which we can execute more of our code, provided it
; doesn't take any longer than 30 scanlines
;

;
; Read joystick input and setup player movement/action vars
;
    LDA #0                      ; Clear player movement flag
    STA playerSpriteMoving

;
; Horizontal motion check
;
HorizontalCheck
    LDA #%10000000
    BIT SWCHA
    BEQ PlayerRight
    LSR
    BIT SWCHA
    BEQ PlayerLeft
    JMP VerticalCheck

PlayerRight
    LDX playerPosX
    CPX (#SCREEN_WIDTH - #8)
    BEQ HorizontalMove
    
    INX                         ; Increment X-position
    INC playerSpriteMoving      ; Set player move flag
    JMP HorizontalMove

PlayerLeft
    LDX playerPosX
    CPX #0
    BEQ HorizontalMove
    
    DEX                         ; Decrement Y-position
    INC playerSpriteMoving      ; Set player move flag
    JMP HorizontalMove

HorizontalMove
    STX playerPosX

VerticalCheck
    LDA #%00100000
    BIT SWCHA
    BEQ PlayerDown
    LSR
    BIT SWCHA
    BEQ PlayerUp
    JMP OverscanLoop
    
PlayerDown
    LDX playerPosY
    CPX #ERR_SPRITE_HEIGHT + 2
    BCC OverscanLoop
    DEC playerPosY
    INC playerSpriteMoving
    JMP OverscanLoop
    
PlayerUp
    LDX playerPosY
    CPX #SCREEN_HEIGHT
    BEQ OverscanLoop
    INC playerPosY
    INC playerSpriteMoving


;
; Once we've done our stuff, we are going to sit in a tight loop and wait for the timer
; to end
;
OverscanLoop
    LDA INTIM           ; Load timer value into accumulator
    BNE OverscanLoop    ; Loop back if the timer value is not zero

    STA WSYNC           ; Again, we're probably in the middle of a scanline here. Wait
                        ; for it to complete
    JMP MainLoop        ; END OF FRAME - jump back to main game loop

; -----------------------------------------------------------------------------


;
; Import graphics data
;
        ORG $FE00
        INCLUDE "err_sprite.asm"


;
; X-position coarse/fine value lookup table
;
xPositionTable
    .byte                       $34, $24, $14, $04, $F4, $E4, $D4, $C4, $B4, $A4, $94   ; Pixels 0-10
    .byte   $75, $65, $55, $45, $35, $25, $15, $05, $F5, $E5, $D5, $C5, $B5, $A5, $95   ; Pixels 11-25
    .byte   $76, $66, $56, $46, $36, $26, $16, $06, $F6, $E6, $D6, $C6, $B6, $A6, $96   ; Pixels 26-40
    .byte   $77, $67, $57, $47, $37, $27, $17, $07, $F7, $E7, $D7, $C7, $B7, $A7, $97   ; Pixels 41-55
    .byte   $78, $68, $58, $48, $38, $28, $18, $08, $F8, $E8, $D8, $C8, $B8, $A8, $98   ; Pixels 56-70
    .byte   $79, $69, $59, $49, $39, $29, $19, $09, $F9, $E9, $D9, $C9, $B9, $A9, $99   ; Pixels 71-85
    .byte   $7A, $6A, $5A, $4A, $3A, $2A, $1A, $0A, $FA, $EA, $DA, $CA, $BA, $AA, $9A   ; Pixels 86-100
    .byte   $7B, $6B, $5B, $4B, $3B, $2B, $1B, $0B, $FB, $EB, $DB, $CB, $BB, $AB, $9B   ; Pixels 101-115
    .byte   $7C, $6C, $5C, $4C, $3C, $2C, $1C, $0C, $FC, $EC, $DC, $CC, $BC, $AC, $9C   ; Pixels 116-130
    .byte   $7D, $6D, $5D, $4D, $3D, $2D, $1D, $0D, $FD, $ED, $DD, $CD, $BD, $AD, $9D   ; Pixels 131-145
    .byte   $7E, $6E, $5E, $4E, $3E, $2E, $1E, $0E, $FE, $EE, $DE, $CE, $BE, $AE        ; Pixels 146-159


;
; Final housekeeping
;
; There are two special memory locations, $FFFC and $FFFE.
; When the atari starts up, a "reset" is done. When this happens, the 6502 looks at
; memory location defined by the bytes $FFFC and $FFFD and then goes to that 
; location. The first .word Start tells DASM to put the binary data that we labeled 
; "Start" at the location we established with org. 
;
; This is repeated for $FFFE/$FFFF, which is for a special event called a BRK
;
    ORG $FFFC
    .word Start
    .word Start
