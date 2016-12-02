########################################## DEFINES ##############################################################
		.eqv	BUFFER_SIZE	1600000
		.eqv	INWIDTH		$t9
		.eqv	INHEIGHT	$t8
		.eqv	INROWSIZE	$s7
		.eqv	OUTWIDTH	$s6
		.eqv	OUTHEIGHT	$s5
		.eqv	OUTROWSIZE	$s4
		
########################################## DATA ##############################################################
		.data
in_file_desc:	.space	4
out_file_desc:	.space	4
fin:		.asciiz	"/home/tgalecki/Projekty/bmpresizeASM/image.bmp"
fout:		.asciiz	"/home/tgalecki/Projekty/bmpresizeASM/image_scaled.bmp"
		.align 	4
in_img:		.space 	2		# for buffer shift
in_header:	.space 	BUFFER_SIZE	# 1,6 MB for input

out_img:	.space 	2		# for header shift
out_header:	.space 	BUFFER_SIZE

        .text
########################################## MACROS ##############################################################

	##################### COMMON MACROS #####################
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
	.macro for (%regIterator, %from, %bodyMacroName)
	add 	%regIterator, $zero, %from
Loop:	%bodyMacroName ()
	add 	%regIterator, %regIterator, -1
	bnez 	%regIterator, Loop
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
  	sw 	$v0, in_file_desc	# save the file descriptor 
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
########################################## MAIN PROGRAM ##############################################################

##################### FILE & HEADER LOAD ###############################
	openInputImg()
	openOutputImg()
	readFromImg(in_header, 54)	# load bmp and DIB header
  	
##################### HEADER PARSING #####################
#b header_parsing
	lw	$t0, in_header + 0x2
	printStr("BMP size: ")
	printInt($t0)
	printStr("\n")
	lw	$t0, in_header + 0x12
	printStr("Width: ")
	printInt($t0)
	printStr("\n")
	lw	$t0, in_header + 0x16
	printStr("Height: ")
	printInt($t0)
	printStr("\n")
	lw	$t0, in_header + 0x22
	printStr("IMG size: ")
	printInt($t0)
	printStr("\n")
	
header_parsing:
	
##################### EPILOG #####################
epilogue:
	closeInputImg()
	closeOutputImg()





