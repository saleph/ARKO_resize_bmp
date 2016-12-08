########################################## DEFINES ##############################################################
		.eqv	BUFFER_SIZE	1600000
		.eqv	B_INWIDTH	$t9	# input img width in bytes
		.eqv	INHEIGHT	$t8	# input img height (no of rows)
		.eqv	INROWSIZE	$s7	# input img row size (with padding)
		.eqv	B_OUTWIDTH	$s6	# output img width in bytes
		.eqv	OUTHEIGHT	$s5	# output img height (no of rows)
		.eqv	OUTROWSIZE	$s4	# output img row size (with padding)
		
########################################## DATA ##############################################################
		.data
in_file_desc:	.space	4		# input image file descriptor
out_file_desc:	.space	4		# output image file descriptor
INWIDTH:	.space	4		# input image width in pixels
OUTWIDTH:	.space	4		# output image width in pixels
fin:		.asciiz	"image2.bmp"
fout:		.asciiz	"image_scaled.bmp"
		.align 	4
inimg:		.space 	2		# for buffer shift
inheader:	.space 	BUFFER_SIZE	# 1,6 MB for input
		.align	4
outimg:		.space 	2		# for header shift
outheader:	.space 	BUFFER_SIZE	# 1,6 MB for output

        .text
########################################## MACROS ##############################################################

	##################### COMMON MACROS #####################
	.macro exit()
	li	$v0, 10
	syscall
	.end_macro
	
	##########################################
	.macro printStr (%str)
	.data
str:	.asciiz %str
	.text
	li $v0, 4
	la $a0, str
	syscall
	.end_macro
	
	##########################################
	.macro printInt (%x)
	li $v0, 1
	add $a0, $zero, %x
	syscall
	.end_macro
	
	##########################################
	.macro debugStr (%str)
	printStr("##### ")
	printStr(%str)
	printStr("\n")
	.end_macro
	
	##########################################
	.macro debug (%str, %x)
	printStr("##### ")
	printStr(%str)
	printInt(%x)
	printStr("\n")
	.end_macro
	
	##########################################
	.macro forN (%regIterator, %from, %bodyMacroName)
	add 	%regIterator, $zero, %from
Loop:	%bodyMacroName ()
	add 	%regIterator, %regIterator, -1
	bnez 	%regIterator, Loop
	.end_macro
	
	##########################################
	.macro for (%regIterator, %from, %to, %bodyMacroName)
	add %regIterator, $zero, %from
	Loop:
	%bodyMacroName ()
	add %regIterator, %regIterator, 1
	ble %regIterator, %to, Loop
	.end_macro
	
	##########################################
	.macro openInputImg
	li   	$v0, 13			# system call for open file
  	la   	$a0, fin		# output file name
  	li   	$a1, 0			# Open for read
  	syscall			
  	sw 	$v0, in_file_desc	# save the file descriptor 
	.end_macro
	
	##########################################
	.macro closeInputImg
	li   	$v0, 16       		# system call for close file
  	lw 	$a0, in_file_desc      	# file descriptor to close
  	syscall            		# close file
  	.end_macro
  	
	##########################################
        .macro readFromImg (%dest, %size)
        li	$v0, 14			# read from file
  	lw	$a0, in_file_desc	# file descriptor
  	la	$a1, %dest		# destination	
  	li	$a2, %size		# max file size
  	syscall
        .end_macro
        
        ##########################################
	.macro openOutputImg
	li   	$v0, 13			# system call for open file
  	la   	$a0, fout		# output file name
  	li   	$a1, 1			# Open for write
  	syscall			
  	sw 	$v0, out_file_desc	# save the file descriptor 
	.end_macro
	
	##########################################
	.macro closeOutputImg
	li   	$v0, 16       		# system call for close file
  	lw 	$a0, out_file_desc     	# file descriptor to close
  	syscall            		# close file
  	.end_macro
        
	##########################################
	.macro storeToImg (%source, %size)
        li	$v0, 15			# write to file
  	lw	$a0, out_file_desc	# file descriptor
  	la	$a1, %source		# source	
  	li	$a2, %size		# max file size
  	syscall
	.end_macro
	
	##########################################
	.macro readNewImgSize()
	printStr("[width]")
	li	$v0, 5			# load int
	syscall
	sw	$v0, OUTWIDTH
	multBy3($v0)
	add	B_OUTWIDTH, $zero, $v0	# copy width
	printStr("[height]")
	li	$v0, 5			# load int
	syscall
	add	OUTHEIGHT, $zero, $v0	# copy height
	.end_macro
	
	##################### FIXED POINT ARITHMETIC #####################
	.macro fixedFromInt (%source)
	sll	%source, %source, 16
	.end_macro
	
	##########################################
	.macro fixedToInt (%source)
	srl	%source, %source, 16
	.end_macro
	
	##########################################
	.macro fixedAdd (%dest, %first, %second)
	addu	%dest, %first, %second
	.end_macro
	
	##########################################
	.macro fixedMult (%dest, %first, %second)
	# HI: | significant | LO: | fraction |, do mult = (HI << 16) | (LO >> 16)
	multu	%first, %second
	mflo	%dest
	srl	%dest, %dest, 16	# 16 bits for fraction
	mfhi	$a0
	sll	$a0, $a0, 16		# 16 bits for significant
	or	%dest, %dest, $a0	
	.end_macro
	
	##########################################
	.macro fixedDiv (%dest, %first, %second)
	divu	%dest, %second
	mflo	%dest
	sll	%dest, %first, 16	# expand first arg
	.end_macro
	
	##################### IMAGE COMPUTING MACROS #####################
	.macro multBy3 (%reg)
	move	$a0, %reg
	sll	%reg, %reg, 1		# multiple by 2
	addu	%reg, %reg, $a0
	.end_macro
	
	##########################################
	.macro computeInputRowSize()
	# rowSize = [(WIDTH_IN_BITS + 31) / 32]*4
	move	$a0, B_INWIDTH
	sll	$a0, $a0, 3	# *8
	addiu	$a0, $a0, 31
	sra	$a0, $a0, 5	# /32
	sll	INROWSIZE, $a0, 2	# *4
	.end_macro
	
	##########################################
	.macro computeOutputRowSize()
	# rowSize = [(WIDTH_IN_BITS + 31) / 32]*4
	move	$a0, B_OUTWIDTH
	sll	$a0, $a0, 3	# *8
	addiu	$a0, $a0, 31
	sra	$a0, $a0, 5	# /32
	sll	OUTROWSIZE, $a0, 2	# *4
	.end_macro
########################################## MAIN PROGRAM ##############################################################
debugStr("Fixed point arithmetic debug")
	.macro dload (%first, %second)
	add	$a0, $zero, %first
	move	$t0, $a0
	add	$a0, $zero, %second
	move	$t1, $a0
	.end_macro
	
	dload(98304, 917635)
	fixedMult($t2, $t0, $t1)
	fixedAdd($t3, $t0, $t1)
	fixedDiv($t4, $t0, $t1)
	debug("1.5 x 14.002 = ", $t2)
	debug("1.5 + 14.002 = ", $t3)
	debug("1.5 / 14.002 = ", $t4)
	
	dload(65536, 65536)
	fixedMult($t2, $t0, $t1)
	fixedAdd($t3, $t0, $t1)
	fixedDiv($t4, $t0, $t1)
	debug("1 x 1 = ", $t2)
	debug("1 + 1 = ", $t3)
	debug("1 / 1 = ", $t4)
	
	

debugStr("\n")
##################### FILE & HEADER LOAD ###############################
	openInputImg()
	openOutputImg()
	readFromImg(inheader, 54)	# load bmp and DIB header
  	
##################### HEADER PARSING #####################
debugStr(">> INPUT HEADER PARSING")
	lw	$t0, inheader + 0x2
	debug("BMP size: ", $t0)
	
	lw	$t0, inheader + 0xA
	debug("IMG array offset: ", $t0)
	
	lw	$t0, inheader + 0x12
	debug("Width: ", $t0)
	sw	$t0, INWIDTH
	multBy3($t0)
	move	B_INWIDTH, $t0
	debug("Width in bytes: ", B_INWIDTH)
	
	lw	$t0, inheader + 0x16
	debug("Height: ", $t0)
	move	INHEIGHT, $t0
	
	lw	$t0, inheader + 0x22
	debug("IMG size: ", $t0)
	
	computeInputRowSize()
	debug("Computed row size: ", INROWSIZE)
	
debugStr("<< INPUT HEADER PARSING")
debugStr("")
	
##################### OUTPUT HEADER PREPARATION #####################
debugStr(">> OUTPUT HEADER PREPARATION")
	printStr("Enter new image size:\n")
	#readNewImgSize()
	computeOutputRowSize()
	
	lw	$t0, OUTWIDTH
	debug("Read output width: ", $t0)
	debug("Read output height: ", OUTHEIGHT)
	
	lhu	$t0, inheader
	sh	$t0, outheader 			# store first halfword of 54 bytes of header
	la	$t0, inheader + 2
	la	$t1, outheader + 2
	
	.macro copy()				# macro for dummy copy of input img header
	lw	$a0, ($t0)
	sw	$a0, ($t1)
	addiu	$t0, $t0, 4
	addiu	$t1, $t1, 4
	.end_macro
	
	forN ($t2, 13, copy)			# copy 13*4=52 bytes of header to outheader
	
	move	$t0, OUTROWSIZE
	multu	$t0, OUTHEIGHT
	mflo	$t0
	debug("New writed color table size: ", $t0)
	sw	$t0, outheader + 0x22
	
	addiu	$t0, $t0, 54			# add header length
	debug("New writed bmp size: ", $t0)
	sw	$t0, outheader + 0x2
	
	lw	$t0, OUTWIDTH
	debug("New writed width: ", $t0)
	sw	$t0, outheader + 0x12
	
	debug("New writed height: ", OUTHEIGHT)
	sw	OUTHEIGHT, outheader + 0x16
	
	storeToImg(outheader, 54)		# save to file parsed header
	
debugStr("<< OUTPUT HEADER PREPARATION")
debugStr("")

########################################## IMAGE PROCESSING ##########################################
debugStr(">>>>> IMAGE PROCESSING")




debugStr("<<<<< IMAGE PROCESSING")
debugStr("")

##################### EPILOGUE #####################
epilogue:
	closeInputImg()
	closeOutputImg()
	exit()





