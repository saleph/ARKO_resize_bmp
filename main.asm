########################################## DEFINES ##############################################################
		.eqv	BUFFER_SIZE	1600000
		
########################################## DATA ##############################################################
		.data
in_file_desc:	.space	4		# input image file descriptor
out_file_desc:	.space	4		# output image file descriptor
INWIDTH:	.space	4		# input image width in pixels
OUTWIDTH:	.space	4		# output image width in pixels
B_INWIDTH:	.space 	4		# input img width in bytes
INHEIGHT:	.space 	4		# input img height (no of rows)
INROWSIZE:	.space 	4		# input img row size (with padding)
B_OUTWIDTH:	.space 	4		# output img width in bytes
OUTHEIGHT:	.space 	4		# output img height (no of rows)
OUTROWSIZE:	.space 	4		# output img row size (with padding)
fin:		.asciiz	"image2.bmp"
fout:		.asciiz	"image_scaled.bmp"
		.align 	2
inimg:		.space 	2		# for buffer shift
inheader:	.space 	BUFFER_SIZE	# 1,6 MB for input
		.align	2
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
	.macro forN (%times, %bodyMacroName)
	add 	$v0, $zero, %times
Loop:	%bodyMacroName ()
	add 	$v0, $v0, -1
	bnez 	$v0, Loop
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
	sw	$v0, B_OUTWIDTH
	printStr("[height]")
	li	$v0, 5			# load int
	syscall
	sw	 $v0, OUTHEIGHT		# copy height
	.end_macro
	
	##################### FIXED POINT ARITHMETIC #####################
	.macro fixedFromInt (%source)
	sll	%source, %source, 16
	.end_macro
	
	##########################################
	.macro fixedToInt (%source)
	sra	%source, %source, 16
	.end_macro
	
	##########################################
	.macro fixedAdd (%dest, %first, %second)
	addu	%dest, %first, %second
	.end_macro
	
	##########################################
	.macro fixedSub (%dest, %first, %second)
	subu	%dest, %first, %second
	.end_macro
	
	##########################################
	.macro fixedMult (%dest, %first, %second)
	# HI: | significant | LO: | fraction |, do mult = (HI << 16) | (LO >> 16)
	multu	%first, %second
	mflo	%dest
	srl	%dest, %dest, 16	# 16 bits for fraction
	mfhi	$v0
	sll	$v0, $v0, 16		# 16 bits for significant
	or	%dest, %dest, $v0	
	.end_macro
	
	##########################################
	.macro fixedDiv (%dest, %first, %second)
	sll	%dest, %first, 8	# expand first arg
	addu	$v0, $zero, %second
	sra	$v0, $v0, 8
	div	%dest, $v0
	mflo	%dest
	.end_macro
	
	##################### IMAGE COMPUTING MACROS #####################
	.macro multBy3 (%reg)
	move	$v0, %reg
	sll	%reg, %reg, 1		# multiple by 2
	addu	%reg, %reg, $v0
	.end_macro
	
	##########################################
	.macro computeInputRowSize()
	# rowSize = [(WIDTH_IN_BITS + 31) / 32]*4
	lw	$v0, B_INWIDTH
	sll	$v0, $v0, 3	# *8
	addiu	$v0, $v0, 31
	sra	$v0, $v0, 5	# /32
	sll	$v0, $v0, 2	# *4
	sw	$v0, INROWSIZE
	.end_macro
	
	##########################################
	.macro computeOutputRowSize()
	# rowSize = [(WIDTH_IN_BITS + 31) / 32]*4
	lw	$v0, B_OUTWIDTH
	sll	$v0, $v0, 3	# *8
	addiu	$v0, $v0, 31
	sra	$v0, $v0, 5	# /32
	sll	$v0, $v0, 2	# *4
	sw	$v0, OUTROWSIZE
	.end_macro
########################################## MAIN PROGRAM ##############################################################

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
	sw	$t0, B_INWIDTH
	debug("Width in bytes: ", $t0)
	
	lw	$t0, inheader + 0x16
	debug("Height: ", $t0)
	sw	$t0, INHEIGHT
	
	lw	$t0, inheader + 0x22
	debug("IMG size: ", $t0)
	
	computeInputRowSize()
	lw	$t0, INROWSIZE
	debug("Computed row size: ", $t0)
	
debugStr("<< INPUT HEADER PARSING")
debugStr("")
	
##################### OUTPUT HEADER PREPARATION #####################
debugStr(">> OUTPUT HEADER PREPARATION")
	printStr("Enter new image size:\n")
	readNewImgSize()
	computeOutputRowSize()
	
	lw	$t0, OUTWIDTH
	debug("Read output width: ", $t0)
	lw	$t0, OUTHEIGHT
	debug("Read output height: ", $t0)
	
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
	
	forN (13, copy)			# copy 13*4=52 bytes of header to outheader
	
	lw	$t0, OUTROWSIZE
	lw	$t1, OUTHEIGHT
	multu	$t0, $t1
	mflo	$t0
	debug("New writed color table size: ", $t0)
	sw	$t0, outheader + 0x22
	
	addiu	$t0, $t0, 54			# add header length
	debug("New writed bmp size: ", $t0)
	sw	$t0, outheader + 0x2
	
	lw	$t0, OUTWIDTH
	debug("New writed width: ", $t0)
	sw	$t0, outheader + 0x12
	
	lw	$t0, OUTHEIGHT
	debug("New writed height: ", $t0)
	sw	$t0, outheader + 0x16
	
	storeToImg(outheader, 54)		# save to file parsed header
	
debugStr("<< OUTPUT HEADER PREPARATION")
debugStr("")

########################################## VARIABLES ##########################################
	.eqv		ps0		$ra
	.eqv		pd0		$fp
	.eqv		psStep		$t9
	.eqv		pdStep		$t8
	.eqv		sx1		$t7
	.eqv		sy1		$t6
	.eqv		sx2		$t5
	.eqv		sy2		$t4
	.eqv		x		$t3
	.eqv		y		$t2
	.eqv		i		$t1
	.eqv		jj		$t0
	.eqv		destwidth	$s7
	.eqv		destheight	$s6
	.eqv		destR		$s5
	.eqv		destG		$s4
	.eqv		destB		$s3
	.eqv		sRGB		$s2
	.eqv		fx		$s1
	.eqv		fy		$s0
	.eqv		fix		$a3
	.eqv		fiy		$ra
	.eqv		dyf		$fp
	.eqv		fxstep		$t9
	.eqv		fystep		$t8
	.eqv		dx		$t7
	.eqv		dy		$t6
	.eqv		color		$t5
	.eqv		pdy		$t4
	.eqv		pdx		$t3
	.eqv		psi		$t2
	.eqv		psj		$t1
	.eqv		AP		$t0
	.eqv		istart		$s7
	.eqv		iend		$s6
	.eqv		jstart		$s5
	.eqv		jend		$s4
	.eqv		devX1		$s3
	.eqv		devX2		$s2
	.eqv		devY1		$s1
	.eqv		devY2		$s0
	
	.data
	.align 2
ps0_fiy:		.space	4		
pd0_dyf:		.space	4		
psstep_fxstep:		.space	4		
pdstep_fystep:		.space	4		
sx1_dx:			.space	4		
sy1_dy:			.space	4		
sx2_color:		.space	4		
sy2_pdy:		.space	4		
x_pdx:			.space	4		
y_psi:			.space	4		
i_psj:			.space	4		
jj_AP:			.space	4
destwidth_istart:	.space	4		
destheight_iend:	.space	4		
destR_jstart:		.space	4		
destG_jend:		.space	4		
destB_devX1:		.space	4		
sRGB_devX2:		.space	4		
fx_devY1:		.space	4		
fy_devY2:		.space	4
	
	.text
	.macro setFirst(%first, %second, %buffer)
	lw	$v0, %buffer
	sw	%second, %buffer
	move	%first, $v0
	.end_macro
	
	.macro	ps0_from_ps0_fiy()
	setFirst(ps0, fiy, ps0_fiy)
	.end_macro																	
	.macro	pd0_from_pd0_dyf()
	setFirst(pd0, dyf, pd0_dyf)
	.end_macro																	
	.macro	psstep_from_psstep_fxstep()
	setFirst(psstep, fxstep, psstep_fxstep)
	.end_macro																	
	.macro	pdstep_from_pdstep_fystep()
	setFirst(pdstep, fystep, pdstep_fystep)
	.end_macro																	
	.macro	sx1_from_sx1_dx()
	setFirst(sx1, dx, sx1_dx)
	.end_macro																	
	.macro	sy1_from_sy1_dy()
	setFirst(sy1, dy, sy1_dy)
	.end_macro																	
	.macro	sx2_from_sx2_color()
	setFirst(sx2, color, sx2_color)
	.end_macro																	
	.macro	sy2_from_sy2_pdy()
	setFirst(sy2, pdy, sy2_pdy)
	.end_macro																	
	.macro	x_from_x_pdx()
	setFirst(x, pdx, x_pdx)
	.end_macro																	
	.macro	y_from_y_psi()
	setFirst(y, psi, y_psi)
	.end_macro																	
	.macro	i_from_i_psj()
	setFirst(i, psj, i_psj)
	.end_macro																	
	.macro	j_from_j_AP()
	setFirst(j, AP, j_AP)
	.end_macro																	
	.macro	destwidth_from_destwidth_istart()
	setFirst(destwidth, istart, destwidth_istart)
	.end_macro																	
	.macro	destheight_from_destheight_iend()
	setFirst(destheight, iend, destheight_iend)
	.end_macro																	
	.macro	destR_from_destR_jstart()
	setFirst(destR, jstart, destR_jstart)
	.end_macro																	
	.macro	destG_from_destG_jend()
	setFirst(destG, jend, destG_jend)
	.end_macro																	
	.macro	destB_from_destB_devX1()
	setFirst(destB, devX1, destB_devX1)
	.end_macro																	
	.macro	sRGB_from_sRGB_devX2()
	setFirst(sRGB, devX2, sRGB_devX2)
	.end_macro																	
	.macro	fx_from_fx_devY1()
	setFirst(fx, devY1, fx_devY1)
	.end_macro																	
	.macro	fy_from_fy_devY2()
	setFirst(fy, devY2, fy_devY2)
	.end_macro																	
																				
	.macro	fiy_from_ps0_fiy()
	setFirst(fiy, ps0, ps0_fiy)
	.end_macro																	
	.macro	dyf_from_pd0_dyf()
	setFirst(dyf, pd0, pd0_dyf)
	.end_macro																	
	.macro	fxstep_from_psstep_fxstep()
	setFirst(fxstep, psstep, psstep_fxstep)
	.end_macro																	
	.macro	fystep_from_pdstep_fystep()
	setFirst(fystep, pdstep, pdstep_fystep)
	.end_macro																	
	.macro	dx_from_sx1_dx()
	setFirst(dx, sx1, sx1_dx)
	.end_macro																	
	.macro	dy_from_sy1_dy()
	setFirst(dy, sy1, sy1_dy)
	.end_macro																	
	.macro	color_from_sx2_color()
	setFirst(color, sx2, sx2_color)
	.end_macro																	
	.macro	pdy_from_sy2_pdy()
	setFirst(pdy, sy2, sy2_pdy)
	.end_macro																	
	.macro	pdx_from_x_pdx()
	setFirst(pdx, x, x_pdx)
	.end_macro																	
	.macro	psi_from_y_psi()
	setFirst(psi, y, y_psi)
	.end_macro																	
	.macro	psj_from_i_psj()
	setFirst(psj, i, i_psj)
	.end_macro																	
	.macro	AP_from_j_AP()
	setFirst(AP, j, j_AP)
	.end_macro																	
	.macro	istart_from_destwidth_istart()
	setFirst(istart, destwidth, destwidth_istart)
	.end_macro																	
	.macro	iend_from_destheight_iend()
	setFirst(iend, destheight, destheight_iend)
	.end_macro																	
	.macro	jstart_from_destR_jstart()
	setFirst(jstart, destR, destR_jstart)
	.end_macro																	
	.macro	jend_from_destG_jend()
	setFirst(jend, destG, destG_jend)
	.end_macro																	
	.macro	devX1_from_destB_devX1()
	setFirst(devX1, destB, destB_devX1)
	.end_macro																	
	.macro	devX2_from_sRGB_devX2()
	setFirst(devX2, sRGB, sRGB_devX2)
	.end_macro																	
	.macro	devY1_from_fx_devY1()
	setFirst(devY1, fx, fx_devY1)
	.end_macro																	
	.macro	devY2_from_fy_devY2()
	setFirst(devY2, fy, fy_devY2)
	.end_macro
	
########################################## IMAGE PROCESSING ##########################################
debugStr(">>>>> IMAGE PROCESSING")
	


debugStr("<<<<< IMAGE PROCESSING")
debugStr("")

##################### EPILOGUE #####################
epilogue:
	closeInputImg()
	closeOutputImg()
	exit()





