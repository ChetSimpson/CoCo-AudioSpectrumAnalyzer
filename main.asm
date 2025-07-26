
;****************************************************
;* Used Labels                                      *
;****************************************************

Basic.TopRam            	EQU     $0074
Basic.ConsoleOutVector  	EQU     $0167

; -----------------------------------------------------
; - Constant address and values
; -----------------------------------------------------
Graph.PeriodStateArray  		EQU     $0200
Graph.Const.UpdateRate.Slow 	EQU     $0301
Graph.Const.UpdateRate.Fast 	EQU     $030C
StackBottom             		EQU     $03FF
FrameBuffer.Start       		EQU     $0400
FrameBuffer.Graph.TitleBox 		EQU     $0404
FrameBuffer.Graph.Title 		EQU     $0405
FrameBuffer.Graph.Bar.Limit 	EQU     $0520
FrameBuffer.Graph.Column1Top 	EQU     $0569
FrameBuffer.Graph.DecibelText 	EQU     $059D
FrameBuffer.TextEnd     		EQU     $0600
FrameBuffer.Graph.Bar.Resting 	EQU     $0C00
FrameBuffer.Graph.Column1Base 	EQU     $0C09
FrameBuffer.Graph.Column2Base 	EQU     $0C13
FrameBuffer.Graph.FirstLabel 	EQU     $0C40
App.Const.DataBufferSize 		EQU     $0E00
FrameBuffer.End         		EQU     $1000
Const.PIAInitValues     		EQU     $3C34
Basic.Functions.InKey   		EQU     $A1C1
Basic.Functions.PrintChar 		EQU     $A30A
Basic.Functions.ClearTextScreen EQU     $A928
MMIO.PIA0.A.Control     		EQU     $FF01
MMIO.PIA0.B.Data        		EQU     $FF02
MMIO.PIA0.B.Control     		EQU     $FF03
MMIO.PIA1.A.Data        		EQU     $FF20
MMIO.PIA1.B.Data        		EQU     $FF22
MMIO.PIA1.B.Control     		EQU     $FF23
MMIO.SAM.Mode.V0.Clear  		EQU     $FFC0
MMIO.SAM.Mode.V1.Clear  		EQU     $FFC2
MMIO.SAM.Mode.V1.Set    		EQU     $FFC3
MMIO.SAM.Mode.V2.Clear  		EQU     $FFC4
MMIO.SAM.Mode.V2.Set    		EQU     $FFC5

;****************************************************
;* Program Code / Data Areas                        *
;****************************************************

                        ORG     $00EE

KScope.State.InputColorIndex 	RMB     $0001                            ; 00EE: 
KScope.State.BlockColor 		RMB     $0001                            ; 00EF: 
KScope.State.IsActive   		RMB     $0001                            ; 00F0: 
KScope.State.BlockOffset.Temp 	RMB     $0001                            ; 00F1: 
KScope.State.BlockOffset.X 		RMB     $0001                            ; 00F2: 
KScope.State.BlockOffset.Y 		RMB     $0001                            ; 00F3: 
Graph.State.GrowthRateFraction 	RMB     $0001                            ; 00F4: 
Graph.State.ShrinkRateFraction 	RMB     $0001                            ; 00F5: 
Graph.State.DetailMode  		RMB     $0001                            ; 00F6: 
Graph.State.TempByteValue 		RMB     $0002                            ; 00F7: 
Graph.State.HoldPeakMode 		RMB     $0001                            ; 00F9: 
App.State.TempColorBlock 		RMB     $0001                            ; 00FA: 
App.State.SampleCount   		RMB     $0002                            ; 00FB: 
App.State.PeriodStatesPtr 		RMB     $0002                            ; 00FD: 
App.State.TempByteValue 		RMB     $0001                            ; 00FF: 

                        ORG     $C000 

EntryPoint              JMP     Main                             ; C000: 

; -----------------------------------------------------------------------
; -
; - Sample the cassette audio input bit and measure the width of the
; - pulse.
; -
; - The loop to measure the width of the pulse will poll the audio input
; - bit up to 1024 times with each check taking 12 cycles and an
; - additional 9 cycles every 256th check for a maximum of 12,324 cycles.
; -
; - For the Color Computer 1 and 2 running at .89mhz the highest
; - frequency it should be able to measure is around 73.95khz. However
; - because of the 16 cycles taken between the change of the input audio
; - and the start of measuring the pulse the higher frequencies cannot
; - be measured. This could be optimized to increase the number of higher
; - frequencies that can be measured but there does not appear to be any
; - value in it.
; -
; - General Register Usage:
; -
; -	A = Read the PIA and checking the audio input bit for changes.
; -	B = LSB of the poll count for measuring the width of the pulse.
; -	X = Address of PIA 1.
; -	Y = poll count for waiting on the input bit to change.
; -	U = Unused
; -
; -----------------------------------------------------------------------
SampleAudio             LEAX    MMIO.PIA1.A.Data,PCR             ; C003: Get address of PIA1 MMIO ports.
                        LDD     #$0400                           ; C007: Get the maximum number of times to poll the audio input bit to measure the pulse width.
                        TFR     D,Y                              ; C00A: Move maximum number of times to poll the audio input bit into Y for later.
                        STA     App.State.TempByteValue          ; C00C: Save MSB of poll count.
                        LDA     ,X                               ; C00E: Read data from PIA1.A.
                        ANDA    #$01                             ; C010: Keep the audio input bit.
                        STA     ,-S                              ; C012: Save the audio input bit on the stack.
@loop_wait_for_change   LDA     ,X                               ; C014: Read data from PIA1.A.
                        ANDA    #$01                             ; C016: Keep the audio input bit.
                        EORA    ,S                               ; C018: XOR with previous audio input bit.
                        BNE     @check_audio_ready               ; C01A: If the value of the audio input has changed, go measure the width of the pulse
                        LEAY    -$02,Y                           ; C01C: Decrement the polling counter by 2 (half the time to measure the width of the pulse).
                        BNE     @loop_wait_for_change            ; C01E: The polling counter has not reached zero, keep polling for change.
                        LEAS    $01,S                            ; C020: Adjust the system stack down by 1 byte.
                        BRA     @exit_fail                       ; C022: No change in audio detected, assume silence and exit.
@check_audio_ready      LDA     #$01                             ; C024: Get the audio input bit mask (bit 0)
                        TST     ,S+                              ; C026: Test the original audio input bit.
                        BNE     SampleAudio                      ; C028: The original audio input bit was not 0, retry without decrementing the retry count.
@loop_measure_audio     BITA    ,X                               ; C02A: Check the current value of the the audio input bit.
                        BEQ     @find_period_state               ; C02C: The current value of the audio input bit is not set, go process the result.
                        INCB                                     ; C02E: The current value of the audio input bit is still set, increment the LSB of the polling count.
                        BNE     @loop_measure_audio              ; C02F: The LSB of the pooling count has not reached 0, keep checking.
                        DEC     App.State.TempByteValue          ; C031: Decrement the MSB of the polling count.
                        BNE     @loop_measure_audio              ; C033: The MSB of the polling count has not reached 0, keep checking.
; If the polling count reaches zero, fall through to exit with failure.
@exit_fail              CLRA                                     ; C035: Set ACCA to 0 to let the call site know the sample failed and...
                        RTS                                      ; C036: Return.
; -----------------------------------------------------------------------
; -
; - Searches the period state table to find the first one assigned a
; - pulse width value that is less than or equal to the pulse width
; - passed to the local function.
; -
; - Entry:
; -
; -	ACCB - The LSB of the pulse width counter.
; -	Graph.State.TempByteValue - The MSB of the pulse width counter.
; -
; - General Register Usage:
; -
; -	D = The pulse width counter.
; -	U = Address of the next period state to check.
; -
; - General Variable Usage:
; -
; -	Graph.State.TempByteValue - The number of remaining period states
; -								to check.
; -
; -----------------------------------------------------------------------
@find_period_state      LDA     #$1B                             ; C037: Get the number of period states to search.
                        STA     Graph.State.TempByteValue        ; C039: Save the number of period states to search.
                        LDA     #$04                             ; C03B: Get the maximum number of iterations to sample.
                        SUBA    App.State.TempByteValue          ; C03D: Subtract from the number of iterations remaining from the last sample.
                        LDU     App.State.PeriodStatesPtr        ; C03F: Get the address of the period state for the first period state in the collection.
@loop_find_match        CMPD    ,U                               ; C041: Does the pulse width assigned to this period state belong to the sampled pulse?
                        BCC     @found_match                     ; C044: Yes, go update the period state.
                        LEAU    $0C,U                            ; C046: Move to the next period state in the collection.
                        DEC     Graph.State.TempByteValue        ; C048: Decrement the number of period states to search.
                        BNE     @loop_find_match                 ; C04A: There are still period states to search, keep searching.
                        BRA     SampleAudio                      ; C04C: No period state found in the collection that matches the sampled pulse. Keep sampling.
@found_match            TST     KScope.State.IsActive            ; C04E: Is the Kaleidoscope active?
                        BEQ     IncreaseEnergyLevel              ; C050: No, Kaleidoscope is not active, go update the period state and graph.
                        LDA     Graph.State.TempByteValue        ; C052: Get the the number of period states remaining in the search.
                        INCA                                     ; C054: Increment the number of period states remaining by 1. This lets the call site know we found one but did not process it.
                        RTS                                      ; C055: Return from the sampling.

; -----------------------------------------------------------------------
; -
; - Increase the energy level of a period state.
; -
; - This will increase the energy level, update the peak energy level
; - marker, and update the display to reflect the change. Once the level
; - has been increased, it will check to see if another audio sample
; - should be performed and if so, jump to SampleAudio.
; -
; - The maximum amount to increase the energy level is calculated as
; - follows:
; -
; -	(255 - int(level) * 2) * growthFraction + level - int(level)
; -
; - Entry:
; -
; -	U = Address of the period state to update.
; -
; - General Register Usage:
; -
; -	U = Address of the period state to update.
; -	X = Address in frame buffer to draw the next the energy level part.
; -	A = The maximum amount the increase the energy level.
; -	B = The color block value to draw to the frame buffer.
; -
; -----------------------------------------------------------------------
IncreaseEnergyLevel     LDA     #$FF                             ; C056: Get the maximum integer value of the energy level.
                        SUBA    $04,U                            ; C058: Subtract the whole number of the current energy level of the period state.
                        SUBA    $04,U                            ; C05A: Subtract the whole number of the current energy level of the period state again.
                        LDB     Graph.State.GrowthRateFraction   ; C05C: Get the growth rate fraction.
                        MUL                                      ; C05E: Multiply the result with the growth rate fraction.
                        ADDD    $04,U                            ; C05F: Add the current energy level to the result.
                        STB     $05,U                            ; C061: Save the fraction of the result in the energy level of the period state.
                        SUBA    $04,U                            ; C063: Subtract the whole number of the current energy level from the whole number of the result.
                        BEQ     @continue_sampling               ; C065: The growth value is zero, go exit sampling.
                        LDX     $02,U                            ; C067: Get the current address in the frame buffer of the top of the bar.
                        LDB     $08,U                            ; C069: Get the color block to draw with.
@loop_draw              CMPX    #FrameBuffer.Graph.Bar.Limit     ; C06B: Is the address of the top of the bar outside the bounds of the vis area?
                        BCS     @done                            ; C06E: Yes, skip increasing the energy level of the period.
                        INC     $04,U                            ; C070: Increment the energy level of the period
                        LEAX    -$20,X                           ; C072: Adjust the address of the top of the bar in the frame buffer up one row.
                        STX     $02,U                            ; C075: Save the address in the frame buffer of the top of the bar in the period state.
                        STB     ,X                               ; C077: Set the color block in frame buffer at the top of the bar level.
                        DECA                                     ; C079: Decrement the number of energy levels the bar has increased.
                        BNE     @loop_draw                       ; C07A: The number of energy levels is not zero, keep drawing.
                        LDX     $06,U                            ; C07C: Get the current address in the frame buffer of the peak energy level.
                        CMPX    $02,U                            ; C07E: Compare against the current address of the top of the bar.
                        BCS     @set_peak_marker                 ; C080: The address in the frame buffer of the peak is higher or the same as the current energy level. Skip setting a new peak.
                        LDX     $02,U                            ; C082: Get the address in the frame buffer of the top of the bar.
                        STX     $06,U                            ; C084: Set the new address in the frame buffer of the peak level in the period state.
@set_peak_marker        TST     Graph.State.HoldPeakMode         ; C086: Is the peak level displayed?
                        BEQ     @continue_sampling               ; C088: No, skip drawing the peak level.
                        STB     ,X                               ; C08A: Set the peak of the bar in the frame buffer.
@continue_sampling      DEC     App.State.SampleCount            ; C08C: Decrement the number of times to sample audio.
                        LBNE    SampleAudio                      ; C08E: We are not done, keep sampling.
@done                   RTS                                      ; C092: Done. Return from sampling.

; -----------------------------------------------------------------------
; -
; - Pulse Width Value Table
; -
; - Each entry represents the number of polling iterations that must
; - occur before the edge of the input signal changes.
; -
; - NOTE: The label values (in Hz) are not accurate based on the polling
; - values below. 
; -
; -----------------------------------------------------------------------
PulseWidthTable         FDB     $03D1                            ; C093: - 31.5hz
                        FDB     $02F8                            ; C095: - 40hz
                        FDB     $026D                            ; C097: - 50hz
                        FDB     $01E8                            ; C099: - 63hz
                        FDB     $017C                            ; C09B: - 80hz
                        FDB     $0136                            ; C09D: - 100hz
                        FDB     $00F4                            ; C09F: - 125hz
                        FDB     $00BE                            ; C0A1: - 160hz
                        FDB     $009B                            ; C0A3: - 200hz
                        FDB     $007A                            ; C0A5: - 250hz
                        FDB     $005F                            ; C0A7: - 315hz
                        FDB     $004D                            ; C0A9: - 400hz
                        FDB     $003D                            ; C0AB: - 500hz
                        FDB     $002F                            ; C0AD: - 630hz
                        FDB     $0026                            ; C0AF: - 800hz
                        FDB     $001E                            ; C0B1: - 1000hz
                        FDB     $0017                            ; C0B3: - 1250hz
                        FDB     $0013                            ; C0B5: - 1600hz
                        FDB     $000F                            ; C0B7: - 2000hz
                        FDB     $000B                            ; C0B9: - 2500hz
                        FDB     $0009                            ; C0BB: - 3150hz
                        FDB     $0007                            ; C0BD: - 4000hz
                        FDB     $0005                            ; C0BF: - 5000hz
                        FDB     $0004                            ; C0C1: - 6300hz
                        FDB     $0003                            ; C0C3: - 8000hz
                        FDB     $0002                            ; C0C5: - 10000hz
                        FDB     $0001                            ; C0C7: - 12500hz

; -----------------------------------------------------------------------
; -
; - Decrease the energy level of all period states.
; -
; - This will decrease the energy level, redraw the peak energy level
; - marker, and update the display to reflect the change.
; -
; - The maximum amount to decrease the energy level of a period state
; - is calculated as follows:
; -
; -	level - ((level / 4 + 10) * shrinkrate)
; -
; - General Register Usage:
; -
; -	U = Address of the period state to update.
; -	X = Address in frame buffer to erase the top energy level part.
; -	A = The maximum amount the decrease the energy level.
; -	B = The color block value to draw to the frame buffer.
; -
; -----------------------------------------------------------------------
DecreaseEnergyLevels    LDU     App.State.PeriodStatesPtr        ; C0C9: Get the address of the first period state in the collection.
                        LDB     #$1B                             ; C0CB: Get the number of period states to update.
                        STB     Graph.State.TempByteValue        ; C0CD: Save the number of period states to update.
@loop_bars              LDD     $04,U                            ; C0CF: Get the current energy level from the period state.
                        BEQ     @update_peak_marker              ; C0D1: The energy level is zero, skip and go update the energy level and continue.
                        LDA     #$40                             ; C0D3: Get [TODO] fraction.
                        LDB     $04,U                            ; C0D5: Get the whole number of energy level from the period state (It was already in ACCA. Can be optimized).
                        MUL                                      ; C0D7: Multiply the [TODO] fraction with the whole number of the energy level.
                        ADDA    #$0A                             ; C0D8: Add 10 to MSB of result (why?).
                        LDB     Graph.State.ShrinkRateFraction   ; C0DA: Get the shrink rate fraction (1 for slow, 12 for fast).
                        MUL                                      ; C0DC: Multiply the result by the shrink rate fraction.
                        PSHS    D                                ; C0DD: Save the result.
                        LDD     $04,U                            ; C0DF: Get the energy level from the period state.
                        SUBD    ,S++                             ; C0E1: Subtract the result from the energy level.
                        BCC     @check_bars_to_erase             ; C0E3: If the result is >= 0 then go try updating.
                        CLRB                                     ; C0E5: Clear the fraction of the energy level.
                        LDA     $04,U                            ; C0E6: Get the whole number of the energy level from the period state.
                        BNE     @check_bars_to_erase             ; C0E8: If the whole number of the energy level is not 0 (zero) go try updating.
                        CLR     $04,U                            ; C0EA: Set the energy level to 0 in the period state.
                        CLR     $05,U                            ; C0EC: -
                        BRA     @update_peak_marker              ; C0EE: Go update the peak energy level marker.
@check_bars_to_erase    STB     $05,U                            ; C0F0: Save the new fraction of the energy level to the period state.
                        NEGA                                     ; C0F2: Negate the whole number of the result.
                        ADDA    $04,U                            ; C0F3: Add the whole number of the energy level to the whole number of the result.
                        BEQ     @update_peak_marker              ; C0F5: If the whole number of the result is 0 there is nothing to update, go update the peak marker of the energy level.
                        LDX     $02,U                            ; C0F7: Get the address in the frame buffer of the top of the bar from the period state.
                        LDB     #$80                             ; C0F9: Get the graphics block to use for erasing (black).
@loop_erase             STB     ,X                               ; C0FB: Erase a row of the graph bar
                        LEAX    $20,X                            ; C0FD: Go to the next row in the frame buffer
                        DEC     $04,U                            ; C100: Decrement the energy level in the period state.
                        DECA                                     ; C102: Decrement number of rows to erase.
                        BNE     @loop_erase                      ; C103: The number of rows to erase is not zero, keep erasing!
                        STX     $02,U                            ; C105: Save the address of the top of the bar in frame buffer to the period state.
@update_peak_marker     TST     Graph.State.HoldPeakMode         ; C107: Is the `hold peak` feature enabled?
                        BEQ     @goto_next_period_state          ; C109: No, do not set the peak marker in the frame buffer.
                        LDX     $06,U                            ; C10B: Get address of the peak energy level in the frame buffer from the period state.
                        LDB     $08,U                            ; C10D: Get the graphics block to draw with from the period state.
                        STB     ,X                               ; C10F: Draw the peak marker in the frame buffer.
@goto_next_period_state LEAU    $0C,U                            ; C111: Go to the next period state.
                        DEC     Graph.State.TempByteValue        ; C113: Decrement the number of period states to process.
                        BNE     @loop_bars                       ; C115: The number of period states to process is not 0, keep processing.
                        RTS                                      ; C117: Return.

; -----------------------------------------------------------------------
; -
; - Main program entry point (JUMPED TO FROM $C000)
; -
; -----------------------------------------------------------------------
Main                    LDS     #StackBottom                     ; C118: Set the system stack.
                        JSR     Splash.Run                       ; C11C: Show the marquee.
                        LDD     #Graph.PeriodStateArray          ; C11F: Get the address of the buffer that will hold the period states.
                        PSHS    D                                ; C122: Save the address of the period states.
; Initialize PIA
                        LDD     #Const.PIAInitValues             ; C124: Get the PIA control values.
                        STA     MMIO.PIA0.A.Control,PCR          ; C127: Set PIA0 channel A. See MSB of Const.PIAInitValues for details.
                        STA     MMIO.PIA1.B.Control,PCR          ; C12B: Set PIA1 channel B. See MSB of Const.PIAInitValues for details.
                        STB     MMIO.PIA0.B.Control,PCR          ; C12F: Set PIA0 channel B. See LSB of Const.PIAInitValues for details.

; -
; - Set initial option flags, rates, etc.
; -
                        LDD     #Graph.Const.UpdateRate.Fast     ; C133: Get the default update speed for the graph.
                        STB     Graph.State.ShrinkRateFraction   ; C136: Set the shrink rate fraction.
                        STA     Graph.State.GrowthRateFraction   ; C138: Set the growth rate fraction.
                        CLR     Graph.State.HoldPeakMode         ; C13A: Turn peak energy level markers off.
                        CLR     Graph.State.DetailMode           ; C13C: Enable detailed mode.
                        PULS    U                                ; C13E: Restore the address of the buffer that will hold the period states.
; Clear the graph period state data BUT WHY?. COPY PROTECT: This looks like an attempt to munge the program if it's running in RAM.
                        LDA     Basic.TopRam                     ; C140: Get the MSB of the address of the top of BASIC RAM.
                        CMPA    #$10                             ; C142: Is the address of the top of BASIC RAM...
                        BCC     ZC149                            ; C144: at least 4k? Yes, for some reason skip getting the buffer size.
                        LDX     #App.Const.DataBufferSize        ; C146: Get the number of bytes to clear.
ZC149                   LDA     #$80                             ; C149: Get the byte to fill the buffer with.
@loop_erase_databuffer  STA     ,U+                              ; C14B: Fill the buffer.
                        LEAX    -$01,X                           ; C14D: Decrement the number of bytes in the buffer that need to be filled.
                        BNE     @loop_erase_databuffer           ; C14F: The number of bytes to fill is not zero, keep filling!
; Clear the frame buffer to all black.
Graph.Run               CLR     KScope.State.IsActive            ; C151: Set that Kaleidoscope is off.
                        LDX     #FrameBuffer.Start               ; C153: Get the address of the start of the frame buffer.
                        LDD     #$8080                           ; C156: Get bytes to fill the frame buffer with.
@loop_erase_framebuffer STD     ,X++                             ; C159: Fill the frame buffer.
                        CMPX    #FrameBuffer.End                 ; C15B: Are we at the end of the frame buffer?
                        BCS     @loop_erase_framebuffer          ; C15E: No, keep filling!
; Set display to semi-graphics mode 12 (64x96) and draw markers
                        STA     MMIO.SAM.Mode.V0.Clear           ; C160: Set the SAM to %100 (VDG should already be set to alphanumeric mode)
                        STA     MMIO.SAM.Mode.V1.Clear           ; C163: -
                        STA     MMIO.SAM.Mode.V2.Set             ; C166: -
                        JSR     DrawFrequencyLabels              ; C169: Print the frequency markers

; -----------------------------------------------------------------------
; - Initialize period states
; -----------------------------------------------------------------------
                        LDX     #Graph.PeriodStateArray          ; C16C: Get the address of the buffer that will hold the period states.
                        STX     App.State.PeriodStatesPtr        ; C16F: Save the address of the period states.
                        LDU     #PulseWidthTable                 ; C171: Get the address of the pulse width table.
                        LDA     #$8A                             ; C174: Get the graphic block to use for the first bar.
                        STA     App.State.TempColorBlock         ; C176: Save it for later.
                        LDY     #FrameBuffer.Graph.Bar.Resting   ; C178: Get the address in the frame buffer of the resting place of the first bar.
                        LDA     #$1B                             ; C17C: Get the number of period states to initialize.
                        STA     App.State.TempByteValue          ; C17E: Save the number of period states to initialize.
@loop_init_periodstate  LDD     ,U++                             ; C180: Get the next pulse width in the table.
                        PSHS    Y                                ; C182: Save the frame buffer address of the bars resting location.
                        STD     ,X++                             ; C184: Set (bytes 0-1) the pulse width in the period state.
                        STY     ,X++                             ; C186: Set (bytes 2-3) the address in frame buffer of the top of the bar in the period state.
                        CLR     ,X+                              ; C189: Set (bytes 4-5) the energy level to 0 in the period state.
                        CLR     ,X+                              ; C18B: -
                        STY     ,X++                             ; C18D: Set (bytes 6-7) the address in frame buffer of the peak level in the period state.
                        LDA     App.State.TempColorBlock         ; C190: Get the graphic block to use for the bar
                        STA     ,Y                               ; C192: Set the color bar block at the resting location of the bar in the frame buffer 
                        LEAY    $01,Y                            ; C194: Go to the next bar address in the frame buffer.
                        CMPY    #FrameBuffer.Graph.Column1Base   ; C196: Are we at the address in the frame buffer of the first separator column?
                        BNE     @check_if_at_column2             ; C19A: No, go check for the second separator column.
                        LEAY    $01,Y                            ; C19C: Yes, we are at the the address in the frame buffer of the first separator column. Skip over it.
@check_if_at_column2    CMPY    #FrameBuffer.Graph.Column2Base   ; C19E: Are we at the address in the frame buffer of the second separator column?
                        BNE     @set_color_block                 ; C1A2: No, we are not at the address in the frame buffer of the second separator column, go [TODO]
                        LEAY    $01,Y                            ; C1A4: Yes, we are at the address in the frame buffer of the second separator column. Skip over it.
@set_color_block        LDA     App.State.TempColorBlock         ; C1A6: Get the color block of the bar to draw.
                        STA     ,X+                              ; C1A8: Set (byte 8) the color block in the period state.
@loop_next_color_block  ADDA    #$10                             ; C1AA: Go to the next nibble in the color block.
                        ORA     #$80                             ; C1AC: Set the high bit to make sure it's a graphical block.
                        CMPA    #$BA                             ; C1AE: Is this the red color block?
                        BEQ     @loop_next_color_block           ; C1B0: Yes, skip it and go to the next block.
                        CMPA    #$CA                             ; C1B2: Is this the white color block?
                        BEQ     @loop_next_color_block           ; C1B4: Yes, skip it and go to the next block.
                        STA     App.State.TempColorBlock         ; C1B6: Save the bar color block
                        LDA     #$0F                             ; C1B8: Get [TODO]
                        STA     ,X+                              ; C1BA: Set (byte 9) the [TODO] in the period state to 15
                        PULS    D                                ; C1BC: Restore the original address in the frame buffer of the bottom of the bar into ACCD.
                        STD     ,X++                             ; C1BE: Set (bytes 10-11) the address in the frame buffer of the bottom of the bar in the period state.
                        DEC     App.State.TempByteValue          ; C1C0: Decrement the number of period states to initialize.
                        BNE     @loop_init_periodstate           ; C1C2: There are still more period states to initialize, go do them!

; -
; - Draw the application title.
; -
                        LDX     #FrameBuffer.Graph.TitleBox      ; C1C4: Get the address in the frame buffer to draw the title box.
                        LDB     #$19                             ; C1C7: Get the number of columns to fill.
                        STB     App.State.TempByteValue          ; C1C9: Save the number of columns to fill.
                        LDA     #$AF                             ; C1CB: Get the blue color block.
@loop_draw_char_cell    LDB     #$06                             ; C1CD: Get the number of rows to fill.
@loop_draw_cell_row     STA     ,X                               ; C1CF: Fill the title box area in the frame buffer.
                        LEAX    $20,X                            ; C1D1: Go to the next row in the frame buffer.
                        DECB                                     ; C1D4: Decrement the number of rows to fill.
                        BNE     @loop_draw_cell_row              ; C1D5: We not done filling this column, keep filling.
                        LEAX    $FF41,X                          ; C1D7: Move up 6 (six) rows and over 1 (one) column.
                        DEC     App.State.TempByteValue          ; C1DB: Decrement the number of columns to fill.
                        BNE     @loop_draw_char_cell             ; C1DD: We are not done filling the title box area, keep filling.
                        LDX     #Strings_AppTitle                ; C1DF: Get the address of the application title text.
                        LDU     #FrameBuffer.Graph.Title         ; C1E2: Get the address in the frame buffer to draw the title text.
                        JSR     DrawSemigraphicString            ; C1E5: Draw the text to the frame buffer.

; -
; - Draw the separator columns
; -
                        LDU     #FrameBuffer.Graph.Column1Top    ; C1E8: Get the address in the frame buffer of the first separator.
                        LDD     #$CA07                           ; C1EB: Get the color block to draw ($CA) and the number of pips to draw (7)
                        LDX     #Strings_DecibelValues           ; C1EE: FIXME: UNUSED DEAD CODE!
@loop_drawpips          STA     ,U                               ; C1F1: Set the color block for the separator in the first column.
                        STA     $0A,U                            ; C1F3: Set the color block for the separator in the second column.
                        LEAU    $0100,U                          ; C1F5: Move down 8 rows in the frame buffer.
                        DECB                                     ; C1F9: Decrement the number of pips to draw in the columns.
                        BNE     @loop_drawpips                   ; C1FA: We are not done drawing pips, keep drawing.

; -
; - Draw the decibel levels.
; -
                        LDU     #FrameBuffer.Graph.DecibelText   ; C1FC: Get the address in the frame buffer to draw the decibel levels.
                        LDX     #Strings_DecibelValues           ; C1FF: Get the address of the decibel level strings.
                        LDB     #$07                             ; C202: Get the number of decibel levels to draw.
@loop_print_strings     PSHS    U,B                              ; C204: Save the U and B registers
                        JSR     DrawSemigraphicString            ; C206: Print the string
                        PULS    U,B                              ; C209: Restore the U and B registers.
                        LEAU    $00C0,U                          ; C20B: Move down 6 rows in the frame buffer.
                        CMPB    #$05                             ; C20F: Is this the third decibel level drawn?
                        BNE     @next_decibel_string             ; C211: No, go keep drawing.
                        LEAU    $00C0,U                          ; C213: Yes, this is the third decibel level drawn, move down 6 rows in the frame buffer.
@next_decibel_string    DECB                                     ; C217: Decrement the number of decibel levels to draw.
                        BNE     @loop_print_strings              ; C218: There are still decibel levels to draw, keep drawing.

; -----------------------------------------------------------------------
; - Main Program Loop
; -----------------------------------------------------------------------
; ---
Main.Loop               LDA     #$04                             ; C21A: Get the number of times to sample frequencies before updating the graph.
                        STA     App.State.SampleCount            ; C21C: Save the number of times to sample frequencies before updating the graph.
                        JSR     SampleAudio                      ; C21E: Sample frequencies.
                        JSR     DecreaseEnergyLevels             ; C221: Update the graph bars.
                        JSR     Basic.Functions.InKey            ; C224: Grab a key from the keyboard.
                        CMPA    #'D                              ; C227: Is this the TOGGLE DETAIL key?
                        BNE     @checkForAudioToggleKey          ; C229: No, go check the next key.
                        COM     Graph.State.DetailMode           ; C22B: Toggle DETAIL flag.
                        JSR     DrawFrequencyLabels              ; C22D: Redraw the bar labels.
                        BRA     Main.Loop                        ; C230: Start over!
; ---
@checkForAudioToggleKey CMPA    #'A                              ; C232: Is this the TOGGLE AUDIO key?
                        BNE     @checkForPauseKey                ; C234: No, go check the next key.
                        LDA     MMIO.PIA1.B.Control              ; C236: Grab the PIA values.
                        EORA    #$08                             ; C239: Flip the audio enable bit.
                        STA     MMIO.PIA1.B.Control              ; C23B: Set the PIA values.
                        BRA     Main.Loop                        ; C23E: Start Over!
; ---
@checkForPauseKey       CMPA    #$20                             ; C240: Is this the PAUSE key?
                        BNE     @checkForHoldPeakKey             ; C242: No, go check the next key.
@waitForKey             JSR     Basic.Functions.InKey            ; C244: Get a key from the keyboard
                        ANDA    #$7F                             ; C247: Mask off high bit [TODO: WHY? What does BASIC do that requires this?]
                        BEQ     @waitForKey                      ; C249: If ACCA is 0 then no key pressed, go check again until we get one.
                        BRA     Main.Loop                        ; C24B: Start Over!
; ---
@checkForHoldPeakKey    CMPA    #'P                              ; C24D: Is this the TOGGLE HOLD PEAK key?
                        BNE     @checkForResetKey                ; C24F: No, go check the next key.
                        COM     Graph.State.HoldPeakMode         ; C251: Flip the HOLD PEAK flag.
                        BNE     Main.Loop                        ; C253: The HOLD PEAK flag is not zero so the feature is enabled. Go back to sampling (the sampler will draw the peak marker).
; Erase peak markers
                        LDU     App.State.PeriodStatesPtr        ; C255: Get the address of the period states.
                        LDD     #$801B                           ; C257: Get the color block to draw (MSB) and number of period states to process (LSB).
ZC25A                   LDX     $06,U                            ; C25A: Get the address in the frame buffer of the peak marker from the period state.
                        CMPX    $0A,U                            ; C25C: Is it the same as the address in the frame buffer of the peak marker?
                        BEQ     ZC266                            ; C25E: Yes, peak has not changed, go update the next period state.
                        CMPX    $02,U                            ; C260: Is it the same as the address in the frame buffer of the top of the bar?
                        BCC     ZC266                            ; C262: It's equal or higher to the top of the bar, so skip erasing the marker (it's the same or lower on screen).
                        STA     ,X                               ; C264: Erase the peak marker in the frame buffer.
ZC266                   LEAU    $0C,U                            ; C266: Go to the next period state.
                        DECB                                     ; C268: Decrement the number of period states to process.
                        BNE     ZC25A                            ; C269: The number of period states to process is not 0 (zero), go process the next period state.
                        BRA     Main.Loop                        ; C26B: Start Over!
; ---
@checkForResetKey       CMPA    #'R                              ; C26D: Is this the RESET key
                        BNE     @checkForFastModeKey             ; C26F: No, go check the next key.
                        LDU     App.State.PeriodStatesPtr        ; C271: Get the address for the first period state in the collection.
                        LDD     #$801B                           ; C273: Get the color block to draw to the frame buffer into ACCA and number of period states to process into ACCB.
                        STB     App.State.TempByteValue          ; C276: Save the number of period states to process 
ZC278                   LDB     $04,U                            ; C278: Get the energy level from the period state.
                        BEQ     ZC286                            ; C27A: The energy level is 0 (zero), skip erasing the bar and go erase the peak marker.
                        LDX     $0A,U                            ; C27C: Get the location in the frame buffer of the bottom of the bar from the period state.
ZC27E                   LEAX    -$20,X                           ; C27E: Adjust the location in the frame buffer up one row.
                        STA     ,X                               ; C281: Erase 1 (one) row of the bar
                        DECB                                     ; C283: Decrement the number of rows to erase.
                        BNE     ZC27E                            ; C284: The number of rows to erase is not 0 (zero), keep erasing.
ZC286                   LDX     $06,U                            ; C286: Get the location in the frame buffer of the peak marker.
                        CMPX    $0A,U                            ; C288: Is it the same as the location in the frame buffer of the bottom of the bar?
                        BEQ     ZC28E                            ; C28A: Yes, skip erasing.
                        STA     ,X                               ; C28C: Erase the peak marker.
ZC28E                   CLR     $04,U                            ; C28E: Set the energy level to 0 (zero) in the period state
                        CLR     $05,U                            ; C290: -
                        LDX     $0A,U                            ; C292: Get the location in the frame buffer of the bottom of the bar from the period state.
                        STX     $02,U                            ; C294: Set the location in the frame buffer of the top of the bar in the frame buffer in the period state.
                        STX     $06,U                            ; C296: Set the location in the frame buffer of the peak bar position in the period state.
                        LEAU    $0C,U                            ; C298: Go to the next period state.
                        DEC     App.State.TempByteValue          ; C29A: Decrement the number of period states to process.
                        BNE     ZC278                            ; C29C: The number of period states to process is not 0 (zero), keep processing.
                        JMP     Main.Loop                        ; C29E: Start over!
; ---
@checkForFastModeKey    CMPA    #'F                              ; C2A1: Is this the FAST UPDATE MODE select key?
                        BNE     @checkForSlowModeKey             ; C2A3: No, go check the next key.
                        LDD     #Graph.Const.UpdateRate.Fast     ; C2A5: Get the fast update rate information
                        STB     Graph.State.ShrinkRateFraction   ; C2A8: Set the shrink rate.
                        STA     Graph.State.GrowthRateFraction   ; C2AA: Set the growth rate.
                        JMP     Main.Loop                        ; C2AC: Start over!
; ---
@checkForSlowModeKey    CMPA    #'S                              ; C2AF: Is this the SLOW UPDATE MODE select key?
                        BNE     @checkForKaleidoscopeKey         ; C2B1: No, go check the next key.
                        LDD     #Graph.Const.UpdateRate.Slow     ; C2B3: Get the slow update rate information
                        STA     Graph.State.ShrinkRateFraction   ; C2B6: Set the shrink rate.
                        STB     Graph.State.GrowthRateFraction   ; C2B8: Set the growth rate.
                        JMP     Main.Loop                        ; C2BA: Start over!
; ---
@checkForKaleidoscopeKey CMPA    #'K                              ; C2BD: Is this the Kaleidoscope mode key
                        LBNE    Main.Loop                        ; C2BF: No, start over!

; -----------------------------------------------------------------------
; - Kaleidoscope
; -----------------------------------------------------------------------
                        LDX     #FrameBuffer.Start               ; C2C3: Get the address in the frame buffer of the start of the text screen.
                        LDD     #$8080                           ; C2C6: Get the black color blocks.
ZC2C9                   STD     ,X++                             ; C2C9: Draw the color blocks to the text screen.
                        CMPX    #FrameBuffer.Graph.Bar.Resting   ; C2CB: Are we at the address in the frame buffer of the end of the text screen?
                        BCS     ZC2C9                            ; C2CE: No, keep drawing.
                        COM     KScope.State.IsActive            ; C2D0: Set that the Kaleidoscope visualizer is active.
                        STA     MMIO.SAM.Mode.V2.Clear           ; C2D2: Set the display to mode to base SG.
                        STA     MMIO.SAM.Mode.V1.Set             ; C2D5: -
                        LDX     #FrameBuffer.Graph.Bar.Resting   ; C2D8: Get the address in the frame buffer of the display row at the bottom of the frequency level bars. NOTE: This appears to be used as a buffer for the scope.
                        LDB     #$28                             ; C2DB: Get the size of the TODO_KALEIDOSCOPE_LEVELS buffer.
ZC2DD                   CLR     ,X+                              ; C2DD: Clear a byte in the TODO_KALEIDOSCOPE_LEVELS buffer.
                        DECB                                     ; C2DF: Are we done initializing the TODO_KALEIDOSCOPE_LEVELS buffer?
                        BNE     ZC2DD                            ; C2E0: No, keep initializing.
                        CLR     KScope.State.InputColorIndex     ; C2E2: Reset the color index to 0.
                        CLR     KScope.State.BlockOffset.Temp    ; C2E4: Reset the [TODO] to 0.
                        CLR     App.State.TempColorBlock         ; C2E6: Reset the color block to 0.
ZC2E8                   JSR     Basic.Functions.InKey            ; C2E8: Get a key from the keyboard.
                        CMPA    #'G                              ; C2EB: Is this the GO TO GRAPH key?
                        LBEQ    Graph.Run                        ; C2ED: Yes, go run the analyzer graph.
                        LDX     #$0500                           ; C2F1: Get the value to delay before updating the Kaleidoscope.
ZC2F4                   LEAX    -$01,X                           ; C2F4: Decrement the delay counter.
                        BNE     ZC2F4                            ; C2F6: The delay counter is not zero, keep waiting.
                        LDB     KScope.State.InputColorIndex     ; C2F8: Get the current color index.
                        INCB                                     ; C2FA: Advance to the next color index.
                        CMPB    #$14                             ; C2FB: Is the new color index at the max number of entries?
                        BCS     ZC300                            ; C2FD: No, use the new color index.
                        CLRB                                     ; C2FF: Yes, the color index has reached the max number of entries, reset to the first index.
ZC300                   STB     KScope.State.InputColorIndex     ; C300: Set the new color index.
                        ASLB                                     ; C302: Multiply the color index by 2 (two) to get the offset into the color table.
                        LDX     #FrameBuffer.Graph.Bar.Resting   ; C303: Get the address of the [TODO] buffer.
                        ABX                                      ; C306: Add the color index offset to the address of the [TODO] buffer.
                        LDD     ,X                               ; C307: Get the [TODO] from the [TODO]
                        STD     KScope.State.BlockOffset.X       ; C309: [TODO]
                        CLRA                                     ; C30B: Set ACCA to 0 (zero).
                        CLRB                                     ; C30C: Set ACCB to 0 (zero).
                        STD     ,X                               ; C30D: Set the [TODO] in the [TODO] to 0 (zero).
                        LDA     #$80                             ; C30F: 
                        STA     KScope.State.BlockColor          ; C311: 
                        BSR     KScope_DrawBlocks                ; C313: 
                        JSR     SampleAudio                      ; C315: 
                        BEQ     ZC2E8                            ; C318: The sampled pulse index is 0, do nothing and loop.
                        SUBA    #$03                             ; C31A: Subtract 3 from the pulse index.
                        CMPA    #$17                             ; C31C: Compare the modified pulse index with 23
                        BCC     ZC2E8                            ; C31E: The modified pulse index is equal to or greater than 23, start over.
                        LDB     #$A6                             ; C320: Get the position scale fraction
                        MUL                                      ; C322: Multiply the pulse index with the position scale fraction to create a block offset.
                        ADDD    #$0080                           ; C323: Round block offset up (add .5)
                        STA     KScope.State.BlockOffset.X       ; C326: 
                        LDA     KScope.State.BlockOffset.Temp    ; C328: 
                        CMPA    KScope.State.BlockOffset.X       ; C32A: 
                        BCS     ZC32F                            ; C32C: 
                        CLRA                                     ; C32E: 
ZC32F                   STA     KScope.State.BlockOffset.Y       ; C32F: 
                        INCA                                     ; C331: 
                        STA     KScope.State.BlockOffset.Temp    ; C332: 
                        LDU     KScope.State.BlockOffset.X       ; C334: 
                        LDB     KScope.State.InputColorIndex     ; C336: 
                        ASLB                                     ; C338: 
                        LDX     #FrameBuffer.Graph.Bar.Resting   ; C339: 
                        STU     B,X                              ; C33C: 
                        LDA     App.State.TempColorBlock         ; C33E: 
                        ADDA    #$10                             ; C340: 
                        ORA     #$8F                             ; C342: 
                        STA     App.State.TempColorBlock         ; C344: 
                        STA     KScope.State.BlockColor          ; C346: 
                        BSR     KScope_DrawBlocks                ; C348: 
                        BRA     ZC2E8                            ; C34A: 

; -----------------------------------------------------------------------
; - Draw the Kaleidoscope
; -----------------------------------------------------------------------
KScope_DrawBlocks       LDD     KScope.State.BlockOffset.X       ; C34C: Get the X and Y offsets to draw the block.
                        EXG     A,B                              ; C34E: Swap the X and Y offsets.
                        BSR     @draw_blocks                     ; C350: Go draw the blocks.
                        LDD     KScope.State.BlockOffset.X       ; C352: Get the X and Y offsets to draw the block.
                        EXG     A,B                              ; C354: Swap the X and Y offsets (back to their original).
; [fall through to draw the blocks]
@draw_blocks            STD     KScope.State.BlockOffset.X       ; C356: Save the X and Y coordinates from ACCA and ACCB respectively.
; Draw the first block in the lower right quarter of the frame buffer.
                        LDD     #$1111                           ; C358: Get the base X and Y coordinate (17, 17) of the first block to draw.
                        ADDD    KScope.State.BlockOffset.X       ; C35B: Add the block X and Y offsets to the base X and Y coordinates.
                        BSR     @draw_block_at                   ; C35D: Draw the first block.
; Draw the second block in the upper left quarter of the frame buffer.
                        LDD     #$0F0F                           ; C35F: Get the base X and Y coordinate (15, 15) of the second block to draw.
                        SUBD    KScope.State.BlockOffset.X       ; C362: Subtract the block X and Y offsets from the base X and Y coordinate.
                        BSR     @draw_block_at                   ; C364: Draw the second block.
; Draw the third block in the upper right quarter of the frame buffer.
                        LDD     #$110F                           ; C366: Get the base X and Y coordinate (17, 15) of the third block to draw.
                        ADDA    KScope.State.BlockOffset.X       ; C369: Add the block X offset to the base X coordinate.
                        SUBB    KScope.State.BlockOffset.Y       ; C36B: Subtract the block Y offset from the base Y coordinate.
                        BSR     @draw_block_at                   ; C36D: Draw the third block.
; Draw the fourth block in the lower left quarter of the frame buffer.
                        LDD     #$0F11                           ; C36F: Get the base X and Y coordinate (15, 17) of the forth block to draw.
                        SUBA    KScope.State.BlockOffset.X       ; C372: Subtract the block X offset from the base X coordinate.
                        ADDB    KScope.State.BlockOffset.Y       ; C374: Add the block Y offset to the base Y coordinate.
; [fall through to draw the fourth block]
; ACCA = Y position, ACCB = X position
@draw_block_at          PSHS    B                                ; C376: Save the X coordinate.
                        LDB     #$40                             ; C378: Get the number of frame buffer rows for each block.
                        MUL                                      ; C37A: Multiply the number of frame buffer rows for each block by the Y coordinate.
                        ADDA    #$04                             ; C37B: Add the MSB of the start of the frame buffer to the offset calculated above.
                        TFR     D,X                              ; C37D: Move the address in the frame buffer into X
                        LDB     ,S+                              ; C37F: Get the X coordinate.
                        ABX                                      ; C381: Add the X coordinate to the address in the frame buffer to draw the block at.
                        LDB     KScope.State.BlockColor          ; C382: Get the block to draw.
                        STB     ,X                               ; C384: Draw the first block in the frame buffer.
                        STB     $20,X                            ; C386: Draw the second block down one row in the frame buffer.
                        RTS                                      ; C389: Return.

; -----------------------------------------------------------------------
; - Set of value labels for each of the frequency level bars.
; - 
; - Each entry begins with a null terminated string followed by the
; - number of rows to advance when drawing the next label. If the number
; - of columns to advance is 0 (zero) no more labels are drawn and the
; - function returns.
; -----------------------------------------------------------------------
Strings.FrequencyLabels FCC     "31.5"                           ; C38A: 31.5hz Frequency bar label.
                        FCB     $00,$01                          ; C38E: 
                        FCC     "40"                             ; C390: 40hz Frequency bar label.
                        FCB     $00,$01                          ; C392: 
                        FCC     "50"                             ; C394: 50hz Frequency bar label.
                        FCB     $00,$01                          ; C396: 
                        FCC     "63"                             ; C398: 63hz Frequency bar label.
                        FCB     $00,$01                          ; C39A: 
                        FCC     "80"                             ; C39C: 80hz Frequency bar label.
                        FCB     $00,$01                          ; C39E: 
                        FCC     "100"                            ; C3A0: 100hz Frequency bar label.
                        FCB     $00,$01                          ; C3A3: 
                        FCC     "125"                            ; C3A5: 125hz Frequency bar label.
                        FCB     $00,$01                          ; C3A8: 
                        FCC     "160"                            ; C3AA: 160hz Frequency bar label.
                        FCB     $00,$01                          ; C3AD: 
                        FCC     "200"                            ; C3AF: 200hz Frequency bar label.
                        FCB     $00,$02                          ; C3B2: 
                        FCC     "250"                            ; C3B4: 250hz Frequency bar label.
                        FCB     $00,$01                          ; C3B7: 
                        FCC     "315"                            ; C3B9: 315hz Frequency bar label.
                        FCB     $00,$01                          ; C3BC: 
                        FCC     "400"                            ; C3BE: 400hz Frequency bar label.
                        FCB     $00,$01                          ; C3C1: 
                        FCC     "500"                            ; C3C3: 500hz Frequency bar label.
                        FCB     $00,$01                          ; C3C6: 
                        FCC     "630"                            ; C3C8: 630hz Frequency bar label.
                        FCB     $00,$01                          ; C3CB: 
                        FCC     "800"                            ; C3CD: 800hz Frequency bar label.
                        FCB     $00,$01                          ; C3D0: 
                        FCC     "1000"                           ; C3D2: 1khz Frequency bar label.
                        FCB     $00,$01                          ; C3D6: 
                        FCC     "1250"                           ; C3D8: 1.25khz Frequency bar label.
                        FCB     $00,$01                          ; C3DC: 
                        FCC     "1600"                           ; C3DE: 1.6khz Frequency bar label.
                        FCB     $00,$02                          ; C3E2: 
                        FCC     "2000"                           ; C3E4: 2khz Frequency bar label.
                        FCB     $00,$01                          ; C3E8: 
                        FCC     "2500"                           ; C3EA: 2.5khz Frequency bar label.
                        FCB     $00,$01                          ; C3EE: 
                        FCC     "3150"                           ; C3F0: 3.15khz Frequency bar label.
                        FCB     $00,$01                          ; C3F4: 
                        FCC     "4000"                           ; C3F6: 4khz Frequency bar label.
                        FCB     $00,$01                          ; C3FA: 
                        FCC     "5000"                           ; C3FC: 5khz Frequency bar label.
                        FCB     $00,$01                          ; C400: 
                        FCC     "6300"                           ; C402: 6.3khz Frequency bar label.
                        FCB     $00,$01                          ; C406: 
                        FCC     "8000"                           ; C408: 8khz Frequency bar label.
                        FCB     $00,$01                          ; C40C: 
                        FCC     "10000"                          ; C40E: 10khz Frequency bar label.
                        FCB     $00,$01                          ; C413: 
                        FCC     "12500"                          ; C415: 12.5khz Frequency bar label.
                        FCB     $00,$00                          ; C41A: 

; -----------------------------------------------------------------------
; - Draw the frequency labels for each of the level bars.
; -----------------------------------------------------------------------
DrawFrequencyLabels     LDX     #Strings.FrequencyLabels         ; C41C: Get the address of the first frequency label.
                        LDB     #$01                             ; C41F: Get initial remaining number of columns per group as 1 (one) so we start out as the first column in the group when printing.
                        STB     Graph.State.TempByteValue        ; C421: Save the initial remaining number of columns per group.
                        LDU     #FrameBuffer.Graph.FirstLabel    ; C423: Get the address in the frame buffer of the first label.
                        LDD     #$AFAF                           ; C426: Get the color blocks to erase the frame buffer with.
ZC429                   STD     ,U++                             ; C429: Erase two bytes.
                        CMPU    #FrameBuffer.End                 ; C42B: Did it reach the end of the frame buffer?
                        BCS     ZC429                            ; C42F: No, keep erasing.
                        LDU     #FrameBuffer.Graph.FirstLabel    ; C431: Get the address in the frame buffer of the first label.
ZC434                   PSHS    U                                ; C434: Save the address to top of the frequency label being printed.
                        LDA     #$20                             ; C436: Get the space character.
                        DEC     Graph.State.TempByteValue        ; C438: Decrement the remaining number of columns per group.
                        BNE     ZC487                            ; C43A: The remaining number of columns per group is not zero, go print it if detailed mode is on.
                        LDB     #$03                             ; C43C: Get the number of columns per group.
                        STB     Graph.State.TempByteValue        ; C43E: Save the number of columns per group.
                        LDA     Graph.State.DetailMode           ; C440: Get the value of the detail mode.
                        ANDA    #$40                             ; C442: Keep bit 6 to create the initial fill block for the frequency label.
                        ORA     #$20                             ; C444: Set bit 5 of the fill block. It will have a value of $20 for no detail or $60 for detailed mode.
ZC446                   LDB     Graph.State.DetailMode           ; C446: Get the value of the detail mode.
                        ANDB    #$01                             ; C448: Keep bit 0 to create the initial number of character cells to fill.
                        ADDB    #$04                             ; C44A: Add 4 to the number of character cells to fill. It will have a value of $04 for no detail or $05 for detailed mode.
                        PSHS    A                                ; C44C: Save the color block to fill with.
                        LDA     #$06                             ; C44E: Get the number of rows in the frame buffer that make up a single character cell.
                        MUL                                      ; C450: Multiply the rows per character cell with the number of character cells to fill.
                        PULS    A                                ; C451: Restore the fill block.
ZC453                   STA     ,U                               ; C453: Set the fill block in the frame buffer.
                        LEAU    $20,U                            ; C455: Go to the next row in the frame buffer.
                        DECB                                     ; C458: Decrement the number of cell rows to fill.
                        BNE     ZC453                            ; C459: The number of cell rows to fill is not zero, keep filling.
                        LDU     ,S                               ; C45B: Restore the address to top of the frequency label being printed.
ZC45D                   LDA     ,X+                              ; C45D: Get a character from the string.
                        BEQ     ZC48F                            ; C45F: The character is 0 (zero), go print the next label.
                        CMPA    #$40                             ; C461: Compare the character with [TODO].
                        BCS     ZC46D                            ; C463: The character is lower than [TODO], go [TODO].
                        SUBA    #$40                             ; C465: Subtract [TODO] from the character value.
                        CMPA    #$20                             ; C467: Compare the character with [TODO].
                        BCS     ZC46D                            ; C469: The character is lower than [TODO], go [TODO].
                        SUBA    #$20                             ; C46B: Subtract [TODO] from the character value.
ZC46D                   LDB     Graph.State.TempByteValue        ; C46D: Get the number of labels left in the group to print.
                        CMPB    #$03                             ; C46F: Is it the [TODO: first or last] label in the group?
                        BNE     ZC47B                            ; C471: No, go print the character.
                        LDB     Graph.State.DetailMode           ; C473: Get the detail mode value.
                        ANDB    #$40                             ; C475: Keep bit 6, this will print the character with inverse colors.
                        PSHS    B                                ; C477: Save the result.
                        ORA     ,S+                              ; C479: Set the bit inverse character bit from the result into the character to be printed.
ZC47B                   LDB     #$06                             ; C47B: Get the number of rows per character cell.
ZC47D                   STA     ,U                               ; C47D: Write the character to the frame buffer.
                        LEAU    $20,U                            ; C47F: Go to the next row in the frame buffer.
                        DECB                                     ; C482: Decrement the number of rows to fill.
                        BNE     ZC47D                            ; C483: The number of rows to fill is not 0 (zero), keep filling.
                        BRA     ZC45D                            ; C485: Go print the next character.
ZC487                   TST     Graph.State.DetailMode           ; C487: Is detail mode enabled?
                        BNE     ZC446                            ; C489: Yes, go [TODO]
@skip_string            LDA     ,X+                              ; C48B: Get a character from the string and advance the string pointer.
                        BNE     @skip_string                     ; C48D: The character is not zero, keep skipping.
ZC48F                   PULS    U                                ; C48F: Restore the address to top of the frequency label being printed. 
                        LDA     ,X+                              ; C491: Get the next byte from the string table.
                        BEQ     ZC499                            ; C493: The byte from the string table is zero, go return.
                        LEAU    A,U                              ; C495: Move the address in the frame buffer right 10 columns.
                        BRA     ZC434                            ; C497: Continue printing.
ZC499                   RTS                                      ; C499: Return.

; -----------------------------------------------------------------------
; - Draws a null terminated string to the semigraphics display.
; -----------------------------------------------------------------------
DrawSemigraphicString   LDA     ,X+                              ; C49A: Get a character from the string.
                        BNE     ZC49F                            ; C49C: The character is not zero, go print it.
                        RTS                                      ; C49E: Return.
ZC49F                   BMI     ZC4C6                            ; C49F: If the character is less than 0 it's a color block, go draw it.
                        CMPA    #$20                             ; C4A1: Is the character a space?
                        BNE     ZC4A9                            ; C4A3: No, go prepare the character for printing.
                        LEAU    $01,U                            ; C4A5: Yes it's a space, move over 1 column without drawing anything.
                        BRA     DrawSemigraphicString            ; C4A7: Go print the next character.
ZC4A9                   CMPA    #'@                              ; C4A9: Is the character the @ symbol?
                        BCS     ZC4B5                            ; C4AB: No, it's a lower value than the @ symbol, go print it.
                        SUBA    #'@                              ; C4AD: It's the same or higher value than the @ symbol, subtract it.
                        CMPA    #$20                             ; C4AF: Is the adjusted character value 32?
                        BCS     ZC4B5                            ; C4B1: No, it's lower than 32 meaning it is upper case, go print it.
                        SUBA    #$20                             ; C4B3: Subtract 32 from the character value to make it upper case.
ZC4B5                   STA     $20,U                            ; C4B5: Store the first row of the text one row down in the frame buffer.
                        STA     $40,U                            ; C4B8: Store the next row of the text two rows down in the frame buffer.
                        STA     $60,U                            ; C4BB: Store the next row of the text three rows down in the frame buffer.
                        STA     $0080,U                          ; C4BE: Store the final row of the text four rows down in the frame buffer.
                        LEAU    $01,U                            ; C4C2: Go to the next text column.
                        BRA     DrawSemigraphicString            ; C4C4: Go print the next character.
ZC4C6                   STA     ,U                               ; C4C6: Store the color block in the top row of the text cell.
                        STA     $00A0,U                          ; C4C8: Store the color block in the bottom row of the text cell.
                        BRA     ZC4B5                            ; C4CC: Go draw the middle rows of the character cell.

; -----------------------------------------------------------------------
; - List of decibel level labels.
; -----------------------------------------------------------------------
Strings_AppTitle        FCC     "AUDIO SPECTRUM ANALYZER"        ; C4CE: 
                        FCB     0                                ; C4E5: 
Strings_DecibelValues   FCC     "  5"                            ; C4E6: 5 Decibel level.
                        FCB     0                                ; C4E9: 
                        FCC     "  3"                            ; C4EA: 3 Decibel level.
                        FCB     0                                ; C4ED: 
                        FCC     "  0"                            ; C4EE: 0 Decibel level.
                        FCB     0                                ; C4F1: 
                        FCC     " -3"                            ; C4F2: -3 Decibel level.
                        FCB     0                                ; C4F5: 
                        FCC     " -5"                            ; C4F6: -5 Decibel level.
                        FCB     0                                ; C4F9: 
                        FCC     "-10"                            ; C4FA: -10 Decibel level.
                        FCB     0                                ; C4FD: 
                        FCC     "-20"                            ; C4FE: -20 Decibel level.
                        FCB     0                                ; C501: 

; -----------------------------------------------------------------------
; - Print a null terminated string to the text display.
; -----------------------------------------------------------------------
PrintText               LDA     ,X+                              ; C502: Get a character from the string
                        BEQ     @done                            ; C504: The character is 0 (zero), go exit.
                        JSR     Basic.Functions.PrintChar        ; C506: Print the character to the current device (assumed to be the screen).
                        BRA     PrintText                        ; C509: Keep printing.
@done                   RTS                                      ; C50B: Return.

; -----------------------------------------------------------------------
; - Cycle the color of the block used for the marquee in the splash
; - screen.
; -----------------------------------------------------------------------
Splash.CycleColorBlock  ADDA    #$10                             ; C50C: Add 16 to ACCA to go to the next color set of graphics blocks.
                        ORA     #$8F                             ; C50E: Set high bit and low nibble (4 bits) to 1 to ensure it's a solid color graphics block.
                        CMPA    #$8F                             ; C510: Is the current value a solid black color block?
                        BEQ     Splash.CycleColorBlock           ; C512: Yes, this is a solid black color block skip it and go to the next one.
                        RTS                                      ; C514: Return.

; -----------------------------------------------------------------------
; - Displays the marquee and waits for a key press
; -----------------------------------------------------------------------
Splash.Run              LDA     #$34                             ; C515: Get the PIA control values.
                        STA     MMIO.PIA0.B.Control              ; C517: Set PIA0 channel B. See data sheet for details.
                        STA     MMIO.PIA0.A.Control              ; C51A: Set PIA0 channel A. See data sheet for details.
                        STA     MMIO.PIA1.B.Control              ; C51D: Set PIA1 channel B. See data sheet for details.
                        LDA     #$39                             ; C520: Get the value of the RTS instruction.
                        STA     Basic.ConsoleOutVector           ; C522: Set the console vector entry point with the RTS instruction. This prevents BASIC from printing characters to the text screen.
                        JSR     Basic.Functions.ClearTextScreen  ; C525: Clear the text screen.
                        LDA     #$0D                             ; C528: Get the values to set VDG bits to %000 and enable the alternate color set (orange).
                        STA     MMIO.PIA1.B.Data                 ; C52A: Set the PIA values.
                        LDX     #TitleScreenText                 ; C52D: Get the address of the splash screen message text.
                        JSR     PrintText                        ; C530: Print the splash screen message text.
; Draw the marquee lights around edges of screen
                        LDD     #$9F10                           ; C533: Get the first color block (MSB) to draw and the number of words (LSB) to draw.
                        LDX     #FrameBuffer.Start               ; C536: Get the address of the start of the frame buffer.
@loop_draw_top          STA     ,X+                              ; C539: Draw one color block and advance the draw pointer.
                        STA     ,X+                              ; C53B: Draw one more color block and advance the draw pointer.
                        BSR     Splash.CycleColorBlock           ; C53D: Cycle to the next color block.
                        DECB                                     ; C53F: Decrement the number of word values to draw to the frame buffer.
                        BNE     @loop_draw_top                   ; C540: The number of word values to draw to the frame buffer is not zero, keep drawing.
                        LDB     #$0E                             ; C542: Get the number of rows to draw.
                        LEAX    $1F,X                            ; C544: Move the draw pointer to the end of the second row of the frame buffer.
@loop_draw_right        STA     $00,X                            ; C547: Draw the color block at the last character of the row.
                        STA     -$01,X                           ; C549: Draw the color block at the next to last character of the row.
                        LEAX    $20,X                            ; C54B: Move the draw pointer to the next row in the frame buffer.
                        BSR     Splash.CycleColorBlock           ; C54E: Cycle to the next color block.
                        DECB                                     ; C550: Decrement the number of rows to draw.
                        BNE     @loop_draw_right                 ; C551: The number of rows to draw is not zero, keep drawing.
                        LDB     #$10                             ; C553: Get the number of words to draw on the bottom of the screen.
@loop_draw_bottom       STA     ,X                               ; C555: Draw one color block.
                        STA     -$01,X                           ; C557: Draw one more color block one block before the last color block.
                        LEAX    -$02,X                           ; C559: Adjust the draw pointer down two blocks.
                        BSR     Splash.CycleColorBlock           ; C55B: Cycle to the next color block.
                        DECB                                     ; C55D: Decrement the number of words to draw on the bottom of the screen.
                        BNE     @loop_draw_bottom                ; C55E: The number of words to draw on the bottom of the screen is not zero, keep drawing.
                        LEAX    -$1F,X                           ; C560: Move the draw pointer to the start of the next to the last row.
                        LDB     #$0E                             ; C563: Get the number of rows to draw.
@loop_draw_left         STA     ,X                               ; C565: Draw one color block at the first character of the row.
                        STA     $01,X                            ; C567: Draw one color block at the second character of the row.
                        LEAX    -$20,X                           ; C569: Adjust the draw pointer up one row.
                        BSR     Splash.CycleColorBlock           ; C56C: Cycle to the next color block.
                        DECB                                     ; C56E: Decrement the number of rows to draw.
                        BNE     @loop_draw_left                  ; C56F: The number of rows to draw is not zero, keep drawing.
                        CLRB                                     ; C571: [TODO]
; Wait for vsync ??????
ZC572                   LDA     #$09                             ; C572: Get the number of frames to delay
ZC574                   TST     MMIO.PIA0.B.Control              ; C574: Check the PIA control lines for an IRQ signal.
                        BPL     ZC574                            ; C577: Bit 7 (the IRQ bit) is not set, keep waiting.
                        TST     MMIO.PIA0.B.Data                 ; C579: Acknowledge the IRQ.
                        DECA                                     ; C57C: Decrement the number of frames to delay.
                        BNE     ZC574                            ; C57D: The number of frames to delay is not zero, keep waiting.
; Rotate the marquee lights
                        LDX     #FrameBuffer.Start               ; C57F: Get the address of the start of the frame buffer.
ZC582                   LDA     ,X+                              ; C582: Get a byte from the frame buffer.
                        BPL     ZC590                            ; C584: If it's positive (i.e. bit 7 is not set) it is not a graphics block, skip it.
ZC586                   SUBA    #$10                             ; C586: Subtract 10 from the graphics block (moves to the previous color group)
                        ORA     #$8F                             ; C588: Ensure that bit 7 is set to make it a graphics block and the pattern to draw to full color.
                        CMPA    #$8F                             ; C58A: Is this the black color block?
                        BEQ     ZC586                            ; C58C: Yes, try again!
                        STA     -$01,X                           ; C58E: Save the graphic block back to the original address in the frame buffer.
ZC590                   CMPX    #FrameBuffer.TextEnd             ; C590: Are we at the end of the text screen portion of the frame buffer?
                        BNE     ZC582                            ; C593: No, keep cycling graphic blocks.
                        JSR     Basic.Functions.InKey            ; C595: Check if a key has been pressed.
                        ANDA    #$7F                             ; C598: Mask off the high bit (bit 7) of the result [TODO: Why? what does BASIC set the high bit for?]
                        BNE     ZC59F                            ; C59A: The value is not 0 (zero) meaning a key has been pressed, go exit from the splash scene.
                        DECB                                     ; C59C: Decrement the number of times to cycle the marquee.
                        BNE     ZC572                            ; C59D: The number of times to cycle the marquee is not zero, keep cycling.
ZC59F                   RTS                                      ; C59F: Return.

; -----------------------------------------------------------------------
; - Text displayed on the splash screen.
; -----------------------------------------------------------------------
TitleScreenText         FCB     13,13                            ; C5A0: 
                        FCC     "         AUDIO SPECTRUM"        ; C5A2: 
                        FCB     13                               ; C5B9: 
                        FCC     "            ANALYZER"           ; C5BA: 
                        FCB     13,13                            ; C5CE: 
                        FCC     "               BY"              ; C5D0: 
                        FCB     13                               ; C5E1: 
                        FCC     "          STEVE BJORK"          ; C5E2: 
                        FCB     13,13                            ; C5F7: 
                        FCC     "      COPYRIGHT (C) 1981"       ; C5F9: 
                        FCB     13                               ; C611: 
                        FCC     "         DATASOFT INC."         ; C612: 
                        FCB     13,13,13                         ; C628: 
                        FCC     "     LICENSED TO TANDY CORP."   ; C62B: 
                        FCB     0                                ; C647: 

                        END
