.org $080D
.segment "STARTUP"
.segment "INIT"
.segment "ONCE"
.segment "CODE"

.macro increment_address address ; overwrites A
.scope
    inc address
    bne @continue
    inc address + 1
@continue:
.endscope
.endmacro

.macro add_to_address address, increment ; overwrites A, C flag
.scope
    lda increment
    clc
    adc address
    sta address
    bcc @continue
    inc address + 1
@continue:
.endscope
.endmacro

.macro set_vera_port port ; overwrites A
.scope
    VERA_CONTROL = $9F25
    .IF port = 0
        lda #%11111110
        and VERA_CONTROL
    .ELSEIF port = 1
        lda #%00000001
        ora VERA_CONTROL
    .ELSE
        .FATAL "Port must be 0 or 1."
    .ENDIF
.endscope
.endmacro

; TODO: include bank bit
.macro set_vera_address address ; overwrites A
.scope
    VERA_ADDRESS_REGISTER = $9F20
    lda #<address
    sta VERA_ADDRESS_REGISTER
    lda #>address
    sta VERA_ADDRESS_REGISTER + 1
.endscope
.endmacro

.macro set_vera_address_zp_ptr zp_ptr
.scope
    VERA_ADDRESS_REGISTER = $9F20
    lda zp_ptr
    sta VERA_ADDRESS_REGISTER
    lda zp_ptr + 1
    sta VERA_ADDRESS_REGISTER + 1
.endscope
.endmacro

.macro set_stride stride ; overwrites A
.scope
    VERA_HIGH_REGISTER = $9F22
    .IF stride = 0
        STRIDE_MASK = %00000000
    .ELSEIF stride = 1
        STRIDE_MASK = %0001 << 4
    .ELSEIF stride = 2
        STRIDE_MASK = %0010 << 4
    .ELSEIF stride = 4
        STRIDE_MASK = %0011 << 4
    .ELSEIF stride = 8
        STRIDE_MASK = %0100 << 4
    .ELSEIF stride = 16
        STRIDE_MASK = %0101 << 4
    .ELSEIF stride = 32
        STRIDE_MASK = %0110 << 4
    .ELSEIF stride = 64
        STRIDE_MASK = %0111 << 4
    .ELSEIF stride = 128
        STRIDE_MASK = %1000 << 4
    .ELSEIF stride = 256
        STRIDE_MASK = %1001 << 4
    .ELSEIF stride = 512
        STRIDE_MASK = %1010 << 4
    .ELSEIF stride = 40
        STRIDE_MASK = %1011 << 4
    .ELSEIF stride = 80
        STRIDE_MASK = %1100 << 4
    .ELSEIF stride = 160
        STRIDE_MASK = %1101 << 4
    .ELSEIF stride = 320
        STRIDE_MASK = %1110 << 4
    .ELSEIF stride = 640
        STRIDE_MASK = %1111 << 4
    .ELSE
        .FATAL "Wrong stride value."
    .ENDIF
    lda  VERA_HIGH_REGISTER
    and  #%00001111
    ora  #STRIDE_MASK
    sta  VERA_HIGH_REGISTER 
.endscope
.endmacro

.macro copy_tiles ; Overwrites A, X
.scope
   set_vera_port 0
   set_vera_address $F800
   set_stride 1
   ldx #0
loop:
   lda empty_tile, X
   sta VERA_data_0
   inx
   cpx #tile_end - empty_tile
   bne loop
.endscope
.endmacro

.macro init_buffer ; Overwrites A, X, Y, $02-$03
.scope
   ; fill buffer with 0s
   current_cell = $02
   lda #<buffer_start
   sta current_cell
   lda #>buffer_start
   sta current_cell+1
   ldx 0
row_loop:
   ldy 0
   lda 0
column_loop:
   sta (current_cell), y
   iny
   cpy #COLUMNS + 2
   bne column_loop
   clc
   add_to_address current_cell, #COLUMNS + 2
@continue:
   inx
   cpx #ROWS + 2
   bne row_loop
   ; write border pattern
   lda #<top_left
   sta current_cell
   lda #>top_left
   sta current_cell+1
   lda #1
   ldy 0
fill_top_row:
   sta (current_cell), y
   iny
   cpy #COLUMNS
   bne fill_top_row
   ldx #1
fill_first_last_columns:
   add_to_address current_cell, #COLUMNS + 2
   ldy #0
   lda #1
   sta (current_cell), y
   ldy #COLUMNS-1
   sta (current_cell), y
   inx
   cpx #ROWS
   bne fill_first_last_columns
   ldy 0
fill_bottom_row:
   sta (current_cell), y
   iny
   cpy #COLUMNS
   bne fill_bottom_row
.endscope
.endmacro

.macro transfer_buffer ; overwrites A, X, Y, $02-$05
.scope
   current_cell = $02
   vera_address = $04
   stz vera_address
   stz vera_address + 1
   lda #<top_left
   sta current_cell
   lda #>top_left
   sta current_cell+1
   set_vera_address_zp_ptr vera_address
   set_stride 1
   ldx #0
row_loop:
   ldy #0
column_loop:
   lda (current_cell), y
   and #$01
   sta VERA_data_0
   lda #AMBER_ON_BLACK
   sta VERA_data_0
   iny
   cpy #COLUMNS
   bne column_loop
; add 256 to the VERA memory address to move to the next line
   inc vera_address + 1 
   set_vera_address_zp_ptr vera_address
   clc
   lda #COLUMNS + 2
   adc current_cell
   sta current_cell
   bcc @continue
   inc current_cell + 1
@continue:
   inx
   cpx #ROWS + 2
   bne row_loop
.endscope
.endmacro

.macro count_neighbours ; overwrites A, X, Y, $02-$04
.scope
   bra start
SELF_OFFSET = COLUMNS + 2 + 1
END_ADDRESS = buffer_end - (COLUMNS + 2 + 1)
offsets:
   .byte 0
   .byte 1
   .byte 2
   .byte COLUMNS + 2 + 0
   .byte COLUMNS + 2 + 2
   .byte (COLUMNS + 2) * 2 + 0
   .byte (COLUMNS + 2) * 2 + 1
   .byte (COLUMNS + 2) * 2 + 2
start:
   current_cell = $02
   neighbour_count = $04
   lda #<buffer_start
   sta current_cell
   lda #>buffer_start
   sta current_cell+1
main_loop:
   ldx #0
   stz neighbour_count
count_loop:
   ldy offsets, x
   lda (current_cell), y
   and #1
   beq @no_increment
   inc neighbour_count
@no_increment:
   inx
   cpx #8
   bne count_loop
   ; store neighbour_count as high nibble in current_cell
   lda neighbour_count
   asl 
   asl
   asl
   asl
   sta neighbour_count
   ldy #SELF_OFFSET
   lda #%00001111
   and (current_cell), y
   ora neighbour_count
   sta (current_cell), y
   ; increment current_cell and check if we are done yet
   increment_address current_cell 
   lda #<END_ADDRESS
   cmp current_cell
   bne main_loop
   lda #>END_ADDRESS
   cmp current_cell + 1
   bne main_loop
.endscope
.endmacro

.macro update_buffer ; overwrites A, X, Y, $02-$03
.scope
   current_row = $02
   lda #<top_left
   sta current_row
   lda #>top_left
   sta current_row+1
   ldx #0
row_loop:
   ldy #0
column_loop:
   lda (current_row), y
   and #%11110000
   cmp #$20
   beq continue
   cmp #$30
   beq birth
   sta (current_row), y
   bra continue 
birth:
   lda #1
   ora (current_row), y
   sta (current_row), y
continue:
   iny
   cpy #COLUMNS
   bne column_loop
   add_to_address current_row, #COLUMNS + 2
   inx
   cpx #ROWS
   bne row_loop
.endscope
.endmacro

VERA_data_0 = $9F23

COLUMNS = 80
ROWS    = 60

AMBER_ON_BLACK = $08
GETIN          = $FFE4
Q_CHAR         = $51

jmp start

tiles:
empty_tile:
    .byte %10000000
    .byte %10000000
    .byte %10000000
    .byte %10000000
    .byte %10000000
    .byte %10000000
    .byte %10000000
    .byte %11111111
full_tile:
    .byte %11111111
    .byte %11111111
    .byte %11111111
    .byte %11111111
    .byte %11111111
    .byte %11111111
    .byte %11111111
    .byte %11111111
tile_end:    


start:
   copy_tiles
   init_buffer
main_loop:
   transfer_buffer
@key_loop:
   jsr GETIN
   cmp #0
   beq @key_loop
   cmp #Q_CHAR
   bne @continue
   jmp end
@continue:
   count_neighbours
   update_buffer
   jmp main_loop
end:
   rts

buffer_start: 
buffer_end = buffer_start + (ROWS + 2) * (COLUMNS + 2)
top_left = buffer_start + COLUMNS + 2 + 1
