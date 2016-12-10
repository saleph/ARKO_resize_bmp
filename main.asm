########################################## DEFINES ##############################################################
		.eqv	BUFFER_SIZE	1600000
		
########################################## DATA ##############################################################
		.data
inimg:		.space 	2		# for buffer shift
inheader:	.space 	BUFFER_SIZE	# 1,6 MB for input

		.align 	2
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
fin:		.asciiz	"image3.bmp"
fout:		.asciiz	"image_scaled.bmp"
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
  	add	$a2, $zero, %size	# max file size
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
	#printStr("[width]")
	#li	$v0, 5			# load int
	#syscall
	li	$v0, 101
	sw	$v0, OUTWIDTH
	multBy3($v0)
	sw	$v0, B_OUTWIDTH
	printStr("[height]")
	#li	$v0, 5			# load int
	#syscall
	li	$v0, 78
	sw	$v0, OUTHEIGHT		# copy height
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
	
	##########################################
	.macro fixedInversion (%dest, %source)
	li	$v0, 1
	fixedFromInt ($v0)
	fixedDiv (%dest, $v0, %source)
	.end_macro
	
	##########################################
	.macro fixedTrunc (%dest, %source)
	sra	%dest, %source, 16
	sll	%dest, %dest, 16
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
	.eqv		psstep		$t9
	.eqv		pdstep		$t8
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
	.eqv		sBGR		$s2
	.eqv		fx		$s1
	.eqv		fy		$s0
	.eqv		fix		$a3
	.eqv		fiy		$ra
	.eqv		dyf		$fp
	.eqv		fxstep		$t9
	.eqv		fystep		$t8
	.eqv		dx		$t7
	.eqv		dy		$t6
	.eqv		color		
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
sBGR_devX2:		.space	4		
fx_devY1:		.space	4		
fy_devY2:		.space	4

ps0_:	.space 4
pd0_:	.space 4
psstep_:	.space 4
pdstep_:	.space 4
sx1_:	.space 4
sy1_:	.space 4
sx2_:	.space 4
sy2_:	.space 4
x_:	.space 4
y_:	.space 4
i_:	.space 4
j_:	.space 4
destwidth_:	.space 4
destheight_:	.space 4
destR_:	.space 4
destG_:	.space 4
destB_:	.space 4
sRGB_:	.space 4
fx_:	.space 4
fy_:	.space 4
	
fiy_:	.space 4
dyf_:	.space 4
fxstep_:	.space 4
fystep_:	.space 4
dx_:	.space 4
dy_:	.space 4
color_:	.space 4
pdy_:	.space 4
pdx_:	.space 4
psi_:	.space 4
psj_:	.space 4
AP_:	.space 4
istart_:	.space 4
iend_:	.space 4
jstart_:	.space 4
jend_:	.space 4
devX1_:	.space 4
devX2_:	.space 4
devY1_:	.space 4
devY2_:	.space 4


	.text
	.macro setFirst(%first, %second, %firstaddr, %secondaddr)
	lw	$v0, %firstaddr
	sw	%second, %secondaddr
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
	.macro	jj_from_jj_AP()
	setFirst(jj, AP, jj_AP)
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
	.macro	sBGR_from_sBGR_devX2()
	setFirst(sBGR, devX2, sBGR_devX2)
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
	.macro	AP_from_jj_AP()
	setFirst(AP, jj, jj_AP)
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
	.macro	devX2_from_sBGR_devX2()
	setFirst(devX2, sBGR, sBGR_devX2)
	.end_macro																	
	.macro	devY1_from_fx_devY1()
	setFirst(devY1, fx, fx_devY1)
	.end_macro																	
	.macro	devY2_from_fy_devY2()
	setFirst(devY2, fy, fy_devY2)
	.end_macro
	
	
	################################
	.macro	ps0_from_ps0_fiy()
	setFirst(ps0, fiy, ps0_, fiy_)
	.end_macro
	.macro	pd0_from_pd0_dyf()	
	setFirst(pd0, dyf, pd0_, dyf_)
	.end_macro
	.macro	psstep_from_psstep_fxstep()	
	setFirst(psstep, fxstep, psstep_, fxstep_)
	.end_macro
	.macro	pdstep_from_pdstep_fystep()	
	setFirst(pdstep, fystep, pdstep_, fystep_)
	.end_macro
	.macro	sx1_from_sx1_dx()	
	setFirst(sx1, dx, sx1_, dx_)
	.end_macro
	.macro	sy1_from_sy1_dy()	
	setFirst(sy1, dy, sy1_, dy_)
	.end_macro
	.macro	sx2_from_sx2_color()	
	setFirst(sx2, color, sx2_, color_)
	.end_macro
	.macro	sy2_from_sy2_pdy()	
	setFirst(sy2, pdy, sy2_, pdy_)
	.end_macro
	.macro	x_from_x_pdx()	setFirst(x, pdx, x_, pdx_)
	.end_macro
	.macro	y_from_y_psi()	setFirst(y, psi, y_, psi_)
	.end_macro
	.macro	i_from_i_psj()	setFirst(i, psj, i_, psj_)
	.end_macro
	.macro	j_from_j_AP()	setFirst(j, AP, j_, AP_)
	.end_macro
	.macro	destwidth_from_destwidth_istart()	
	setFirst(destwidth, istart, destwidth_, istart_)
	.end_macro
	.macro	destheight_from_destheight_iend()	
	setFirst(destheight, iend, destheight_, iend_)
	.end_macro
	.macro	destR_from_destR_jstart()	
	setFirst(destR, jstart, destR_, jstart_)
	.end_macro
	.macro	destG_from_destG_jend()	setFirst(destG, jend, destG_, jend_)
	.end_macro
	.macro	destB_from_destB_devX1()	
	setFirst(destB, devX1, destB_, devX1_)
	.end_macro
	.macro	sRGB_from_sRGB_devX2()	
	setFirst(sRGB, devX2, sRGB_, devX2_)
	.end_macro
	.macro	fx_from_fx_devY1()	
	setFirst(fx, devY1, fx_, devY1_)
	.end_macro
	.macro	fy_from_fy_devY2()	
	setFirst(fy, devY2, fy_, devY2_)
	.end_macro
			
	.macro	fiy_from_ps0_fiy()	
	setFirst(fiy, ps0, fiy_, ps0_)
	.end_macro
	.macro	dyf_from_pd0_dyf()	
	setFirst(dyf, pd0, dyf_, pd0_)
	.end_macro
	.macro	fxstep_from_psstep_fxstep()	
	setFirst(fxstep, psstep, fxstep_, psstep_)
	.end_macro
	.macro	fystep_from_pdstep_fystep()	
	setFirst(fystep, pdstep, fystep_, pdstep_)
	.end_macro
	.macro	dx_from_sx1_dx()	
	setFirst(dx, sx1, dx_, sx1_)
	.end_macro
	.macro	dy_from_sy1_dy()	
	setFirst(dy, sy1, dy_, sy1_)
	.end_macro
	.macro	color_from_sx2_color()	
	setFirst(color, sx2, color_, sx2_)
	.end_macro
	.macro	pdy_from_sy2_pdy()	
	setFirst(pdy, sy2, pdy_, sy2_)
	.end_macro
	.macro	pdx_from_x_pdx()	
	setFirst(pdx, x, pdx_, x_)
	.end_macro
	.macro	psi_from_y_psi()	
	setFirst(psi, y, psi_, y_)
	.end_macro
	.macro	psj_from_i_psj()	
	setFirst(psj, i, psj_, i_)
	.end_macro
	.macro	AP_from_j_AP()	
	setFirst(AP, j, AP_, j_)
	.end_macro
	.macro	istart_from_destwidth_istart()	
	setFirst(istart, destwidth, istart_, destwidth_)
	.end_macro
	.macro	iend_from_destheight_iend()	
	setFirst(iend, destheight, iend_, destheight_)
	.end_macro
	.macro	jstart_from_destR_jstart()	
	setFirst(jstart, destR, jstart_, destR_)
	.end_macro
	.macro	jend_from_destG_jend()	setFirst(jend, destG, jend_, destG_)
	.end_macro
	.macro	devX1_from_destB_devX1()	
	setFirst(devX1, destB, devX1_, destB_)
	.end_macro
	.macro	devX2_from_sRGB_devX2()	
	setFirst(devX2, sRGB, devX2_, sRGB_)
	.end_macro
	.macro	devY1_from_fx_devY1()	
	setFirst(devY1, fx, devY1_, fx_)
	.end_macro
	.macro	devY2_from_fy_devY2()	
	setFirst(devY2, fy, devY2_, fy_)
	.end_macro
	
########################################## IMAGE PROCESSING ##########################################
debugStr(">>>>> IMAGE PROCESSING")
	
	# TODO: partial read process
	lw	$v0, INROWSIZE
	lw	$v1, INHEIGHT
	multu	$v0, $v1
	mflo	$v0
	readFromImg (inimg, $v0)
	lw	destwidth, OUTWIDTH
	lw	destheight, OUTHEIGHT
	lw	$v0, INWIDTH
	lw	$v1, INHEIGHT
	# convert to fixed point
	fixedFromInt (destwidth)
	fixedFromInt (destheight)
	fixedFromInt ($v0)
	fixedFromInt ($v1)
	# compute scalling factors
	fixedDiv (fx, $v0, destwidth)
	debug("Scalling factor x: ", fx)
	fixedDiv (fy, $v1, destheight)
	debug("Scalling factor y: ", fy)
	fixedAdd (destwidth, destwidth, -1)
	fixedAdd (destheight, destheight, -1)
	la	ps0, inimg
	lw	psstep, INROWSIZE
	la	pd0, outimg
	lw	pdstep, OUTROWSIZE
	#fixedFromInt (ps0)
	#fixedFromInt (psstep)
	#fixedFromInt (pd0)
	#fixedFromInt (pdstep)
	
		fiy_from_ps0_fiy()
	fixedInversion (fix, fx)
	fixedInversion (fiy, fy)
	li	$v0, 65529
		fxstep_from_psstep_fxstep()
		fystep_from_pdstep_fystep()
	fixedMult (fxstep, fx, $v0) 		# multiply fx by 0.9999
	fixedMult (fystep, fy, $v0)
	
		pdy_from_sy2_pdy()
		pd0_from_pd0_dyf()
	move	pdy, pd0
	
	
	############################ LOOPS #########################
		y_from_y_psi()
	li	y, 0
	#fixedFromInt (y)
vertical_dest:
		sy1_from_sy1_dy()
	fixedMult (sy1, fy, y)
	
		sy2_from_sy2_pdy()
		sy1_from_sy1_dy()
		fystep_from_pdstep_fystep()
	fixedAdd (sy2, sy1, fystep)
		jstart_from_destR_jstart()
	fixedTrunc (jstart, sy1)
		jend_from_destG_jend()
	fixedTrunc (jend, sy2)
	li	$v0, 1
	fixedFromInt ($v0)
		devY1_from_fx_devY1()
	fixedAdd (devY1, jstart, $v0)
	fixedSub (devY1, devY1, sy1)
	li	$v0, 1
	fixedFromInt ($v0)
		devY2_from_fy_devY2()
	fixedAdd (devY2, jend, $v0)
	fixedSub (devY2, devY2, sy2)
		pdx_from_x_pdx()
		pdy_from_sy2_pdy()
	move	pdx, pdy

		x_from_x_pdx()
	li	x, 0
	#fixedFromInt (x)
horizontal_dest:
		sx1_from_sx1_dx()
		fx_from_fx_devY1()
	fixedMult (sx1, fx, x)
		fxstep_from_psstep_fxstep()
	fixedAdd (sx2, sx1, fxstep)
	
		istart_from_destwidth_istart()
		iend_from_destheight_iend()
	#fixedTrunc (istart, sx1)
	move	istart, sx1
	fixedToInt (istart)
	#fixedTrunc (iend, sx2)
	move	iend, sx2
	fixedToInt (iend)
	li	$v0, 1
	fixedFromInt ($v0)
		devX1_from_destB_devX1()
	fixedFromInt (istart)
	fixedAdd (devX1, istart, $v0)
	fixedToInt (istart)
	fixedSub (devX1, devX1, sx1)
	li	$v0, 1
	fixedFromInt ($v0)
		devX2_from_sBGR_devX2()
	fixedAdd (devX2, iend, $v0)
	fixedSub (devX2, devX2, sx2)
		destR_from_destR_jstart()
		destG_from_destG_jend()
		destB_from_destB_devX1()
	li	destR, 0		# prepare colors acumulators
	li	destG, 0
	li	destB, 0
		psj_from_i_psj()
		jstart_from_destR_jstart()
		psstep_from_psstep_fxstep()
	#fixedMult (psj, jstart, psstep)
	multu	jstart, psstep
	mflo	psj
		ps0_from_ps0_fiy()
	#fixedSub (psj, ps0, psj)
	subu	psj, ps0, psj
		dy_from_sy1_dy()
		devY1_from_fx_devY1()
	move	dy, devY1
	
		jj_from_jj_AP()
		jstart_from_destR_jstart()
	move	jj, jstart
vertical_source:
		jend_from_destG_jend()
		dy_from_sy1_dy()
		devY2_from_fy_devY2()
	bne	jj, jend, if1
	fixedSub (dy, dy, devY2)	# if last pixel vert, norm the dy
if1:
		dyf_from_pd0_dyf()
		fiy_from_ps0_fiy()
	fixedMult (dyf, dy, fiy)
	li	$v0, 3
	#fixedFromInt ($v0)
		psi_from_y_psi()
		istart_from_destwidth_istart()
	#fixedMult (psi, istart, $v0)
	multu	istart, $v0
	mflo	psi
	################################	
	#fixedAdd (psi, psi, psj)
	addu	psi, psi, psj
		dx_from_sx1_dx()
		devX1_from_destB_devX1()
	move	dx, devX1

		i_from_i_psj()
	move	i, istart
horizontal_source:
		iend_from_destheight_iend()
		dx_from_sx1_dx()
		devY2_from_fy_devY2()
	bne	i, iend, if2
	fixedSub (dx, dx, devX2)
if2:
		AP_from_jj_AP()
		dyf_from_pd0_dyf()
	fixedMult (AP, dx, dyf)		# compute area factor
	fixedMult (AP, AP, fix)
		psi_from_y_psi()
	#fixedToInt (psi)		# switch pointer to int from fixed
	
	debug("Load adress: ", psi)
	lbu	$v0, (psi)		# load Blue
	fixedFromInt ($v0)
	fixedMult ($v0, $v0, AP)
		destB_from_destB_devX1()
	fixedAdd (destB, destB, $v0)
	
	lbu	$v0, 1(psi)		# load Green
	fixedFromInt ($v0)
	fixedMult ($v0, $v0, AP)
		destG_from_destG_jend()
	fixedAdd (destG, destG, $v0)
	
	lbu	$v0, 2(psi)		# load Red
	fixedFromInt ($v0)
	fixedMult ($v0, $v0, AP)
		destR_from_destR_jstart()
	fixedAdd (destR, destR, $v0)
	
	addiu	psi, psi, 3
	#fixedFromInt (psi)
	
	li	$v0, 1
	fixedFromInt ($v0)
		dx_from_sx1_dx()
	move	dx, $v0
		
		i_from_i_psj()
		iend_from_destheight_iend()
	ble	i, iend, horizontal_source

# vertical source
		psstep_from_psstep_fxstep()
		psj_from_i_psj()
	#fixedSub (psj, psj, psstep)
	subu	psj, psj, psstep
	li	$v0, 1
	fixedFromInt ($v0)
		dy_from_sy1_dy()
	move	dy, $v0			# set dy factor as default for 1 
		jj_from_jj_AP()
		jend_from_destG_jend()
	ble	jj, jend, vertical_source

# horizontal dest
		pdx_from_x_pdx()
	#fixedToInt (pdx)	# pdx cannot be fixed - it is too large
	# store pixel
		destB_from_destB_devX1()
	move	$v0, destB
	fixedToInt ($v0)
	sb	$v0, (pdx)
		destG_from_destG_jend()
	move	$v0, destG
	fixedToInt ($v0)
	sb	$v0, 1(pdx)
		destR_from_destR_jstart()
	move	$v0, destR
	fixedToInt ($v0)
	sb	$v0, 2(pdx)

		destwidth_from_destwidth_istart()
	addiu	pdx, pdx, 3
	#fixedFromInt (pdx)
		x_from_x_pdx()
	ble	x, destwidth, horizontal_dest
	
# vertical dest
		pdy_from_sy2_pdy()
		pdstep_from_pdstep_fystep()
	
	#fixedAdd (pdy, pdy, pdstep)
	add	pdy, pdy, pdstep
		y_from_y_psi()
		destheight_from_destheight_iend()
	ble	y, destheight, vertical_dest

debugStr("<<<<< IMAGE PROCESSING")
debugStr("")

##################### EPILOGUE #####################
epilogue:
	closeInputImg()
	closeOutputImg()
	exit()





