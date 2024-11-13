.data
# Matrices with generous space allocation
output_matrix: .space 512    # 196 bytes needed, allocate 512
padded_matrix: .space 1024   # 324 bytes needed, allocate 1024  
kernel_matrix: .space 256    # 64 bytes needed, allocate 256
image_matrix: .space 512     # 196 bytes needed, allocate 512
buffer: .space 2048         # Generous buffer for file operations
temp: .space 100             # Temporary storage with extra space

# Pre-determined variables (word-aligned)
image: .word 0  # Base address for image matrix
kernel: .word 0 # Base address for kernel matrix
output: .word 0 # Base address for output matrix
padded: .word 0 # Base address for padded matrix

# Variables
N: .float 0.0
M: .float 0.0
p: .float 0.0
s: .float 0.0
zero: .float 0.0
one: .float 1.0
two: .float 2.0
three: .float 3.0
four: .float 4.0
seven: .float 7.0
ten: .float 10.0

# File names
input_file: .asciiz "input_matrix.txt"
output_file: .asciiz "output_matrix.txt"
header: .asciiz "--------RESULT--------\n"

# Output messages
result: .asciiz "The result is: \n"
image_msg: .asciiz "Image Matrix:\n"
kernel_msg: .asciiz "Kernel Matrix:\n"
output_msg: .asciiz "Output Matrix:\n"
padding_msg: .asciiz "Padded Matrix:\n"
space: .asciiz " "
newline: .asciiz "\n"

# Error messages
error_open: .asciiz "Error opening file\n"
error_parse: .asciiz "Error parsing file\n"
error_params: .asciiz "Invalid parameters\n"
padding_error: .asciiz "Invalid padding/stride parameters\n"
error_size: .asciiz "Error: size not match"

.text
main:
    # Save return address
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    # Open input file
    li $v0, 13
    la $a0, input_file
    li $a1, 0       # Read mode
    li $a2, 0
    syscall
    bltz $v0, file_error
    move $s0, $v0   # Save file descriptor

    # Read file
    li $v0, 14
    move $a0, $s0
    la $a1, buffer
    li $a2, 1024
    syscall
    bltz $v0, file_error
    move $s4, $v0   # Save bytes read

    # Add null terminator
    la $t0, buffer
    add $t0, $t0, $s4
    sb $zero, ($t0)

    # Close file
    li $v0, 16
    move $a0, $s0
    syscall

    # Initialize parsing
    la $s2, buffer  # Buffer pointer

parse_first_row:
    li $t0, 0      # Counter for parameters (N,M,p,s)

read_num:
    la $t3, temp   # Use $t3 instead of $s3

store_quantifier:
    lb $t2, ($s2)
    beq $t2, 32, convert_num  # Space
    beq $t2, 10, convert_num  # Newline
    beq $t2, 0, convert_num   # Null

    sb $t2, ($t3)
    addi $t3, $t3, 1    # Move temp pointer
    addi $s2, $s2, 1    # Move buffer pointer
    j store_quantifier

convert_num:
    la $a0, temp
    jal string_to_float

    beq $t0, 0, store_N
    beq $t0, 1, store_M
    beq $t0, 2, store_p
    beq $t0, 3, store_s
    j parse_error

store_N:
    l.s $f1, three
    l.s $f2, seven
    
    
    c.lt.s $f0, $f1
    bc1t params_error
    c.lt.s $f2, $f0
    bc1t params_error
    
    li $v0, 2
    mov.s $f12, $f0
    syscall
    li $v0, 4
    la $a0, newline
    syscall

    s.s $f0, N 
    j next_num

store_M:
    l.s $f1, two
    l.s $f2, four
    
    
    c.lt.s $f0, $f1
    bc1t params_error
    c.lt.s $f2, $f0
    bc1t params_error

    li $v0, 2
    mov.s $f12, $f0
    syscall
    li $v0, 4
    la $a0, newline
    syscall

    s.s $f0, M
    j next_num

store_p:
    l.s $f1, zero
    l.s $f2, four
    
    li $v0, 2
    mov.s $f12, $f0
    syscall
    li $v0, 4
    la $a0, newline
    syscall
    
    c.lt.s $f0, $f1
    bc1t params_error
    c.lt.s $f2, $f0
    bc1t params_error
    
    l.s $f3, N
    l.s $f4, two
    mul.s $f5, $f0, $f4
    add.s $f3, $f3, $f5     # N + 2p
    l.s $f6, M
    c.lt.s $f3, $f6     # Padd size is still < kernel size
    bc1t image_size_error

    s.s $f0, p
    j next_num

store_s:
    l.s $f1, one        # Load 1.0
    l.s $f2, three      # Load 3.0
    
    # If we get here, value is valid (1.0 <= s <= 3.0)
    # Debug print (optional)
    li $v0, 2
    mov.s $f12, $f0
    syscall
    li $v0, 4
    la $a0, newline
    syscall
    
    # Check if s < 1.0
    c.lt.s $f0, $f1
    bc1t params_error    # Branch if s < 1.0
    
    # Check if s > 3.0
    c.lt.s $f2, $f0
    bc1t params_error    # Branch if s > 3.0
    
    s.s $f0, s          # Store valid stride value
	j parse_matrices    # Move to the second and third rows

parse_matrices:
    # Initialize matrix pointers
    la $s5, image_matrix    # $s5 points to image matrix
    la $s6, kernel_matrix   # $s6 points to kernel matrix
    
    # Load N and M for bounds checking
    l.s $f6, N
    l.s $f7, M
    cvt.w.s $f6, $f6       # Convert N to integer
    cvt.w.s $f7, $f7       # Convert M to integer
    mfc1 $s7, $f6          # $s7 = N
    mfc1 $s3, $f7          # $s3 = M
    
    mul $s4, $s7, $s7      # $s4 = N*N (total elements in image)
    mul $t0, $s3, $s3      # $t0 = M*M (total elements in kernel)
    mtc1 $t0, $f8          # Move M*M to floating-point register $f8
    cvt.s.w $f8, $f8       # Convert M*M to float
    
    li $t0, 0              # Counter for image matrix elements
    addi $s2, $s2, 1       # Skip newline

parse_image:
    beq $t0, $s4, parse_kernel  # If done with image, start kernel
    la $t3, temp               # Reset temp buffer

read_image_num:
    lb $t2, ($s2)

    beq $t2, 32, convert_image_num  # Space
    beq $t2, 10, convert_image_num  # Newline
    beq $t2, 0, convert_image_num   # Null
    
    sb $t2, ($t3)
    addi $t3, $t3, 1
    addi $s2, $s2, 1
    j read_image_num

convert_image_num:
    la $a0, temp
    # add null terminator to temp buffer
    li $t2, 0
    sb $t2, ($t3)
    jal string_to_float

    # # Debug print (optional)
    # li $v0, 2
    # mov.s $f12, $f0
    # syscall
    # li $v0, 4
    # la $a0, newline
    # syscall

    s.s $f0, ($s5)         # Store in image matrix
    addi $s5, $s5, 4       # Next element
    addi $t0, $t0, 1       # Increment counter
    addi $s2, $s2, 1       # Skip delimiter
    
    j parse_image

parse_kernel:
    li $t0, 0              # Reset counter for kernel elements
    # addi $s2, $s2, 1       # Skip any remaining delimiter from image parsing

read_kernel_num:
    # Convert $t0 to float for comparison
    mtc1 $t0, $f9
    cvt.s.w $f9, $f9
    c.eq.s $f9, $f8
    bc1t done_parsing      # If finished M*M elements

    la $t3, temp           # Reset temp buffer
    
    # Clear temp buffer
    li $t4, 8              # Buffer size to clear
clear_kernel_temp:
    sb $zero, ($t3)        # Clear byte
    addi $t3, $t3, 1
    addi $t4, $t4, -1
    bnez $t4, clear_kernel_temp
    
    la $t3, temp           # Reset temp pointer for storing

store_kernel_num:
    lb $t2, ($s2)
    beq $t2, 32, convert_kernel_num  # Space
    beq $t2, 10, convert_kernel_num  # Newline
    beq $t2, 0, convert_kernel_num   # End of string
    sb $t2, ($t3)              # Store digit
    addi $t3, $t3, 1
    addi $s2, $s2, 1
    j store_kernel_num

convert_kernel_num:
    la $a0, temp
    jal string_to_float

    # # Debug print (optional)
    # li $v0, 2
    # mov.s $f12, $f0
    # syscall
    # li $v0, 4
    # la $a0, newline
    # syscall

    s.s $f0, ($s6)         # Store in kernel matrix
    addi $s6, $s6, 4       # Next element
    addi $t0, $t0, 1       # Increment counter
    addi $s2, $s2, 1       # Skip delimiter
    j read_kernel_num        # Continue with next number

next_num:
    addi $t0, $t0, 1    # increment parameter counter
    addi $s2, $s2, 1    # skip current space/newline
    
    # Skip any additional spaces
skip_spaces:
    lb $t1, ($s2)
    bne $t1, 32, read_num  # If not space, start reading next number
    addi $s2, $s2, 1    # Skip space
    j skip_spaces       # Check next character

done_parsing:
	j print_image_matrix

add_padding:
    # Initialize entire padded matrix with zeros
    la $s0, padded_matrix
    # Store base address of padded matrix into padded variable
    la $t0, padded
    sw $s0, 0($t0)

    # Load N and p
    l.s $f0, N
    l.s $f1, p
    
    # Calculate N + 2p for new size
    l.s $f2, two
    mul.s $f3, $f1, $f2    # 2p
    add.s $f4, $f0, $f3    # N + 2p
    
    # Convert to integer
    cvt.w.s $f5, $f4       # Convert padded size to integer
    cvt.w.s $f6, $f0       # Convert original N to integer
    cvt.w.s $f7, $f1       # Convert p to integer
    
    # Move to general registers
    mfc1 $t0, $f5          # $t0 = padded size (N + 2p)
    mfc1 $t1, $f6          # $t1 = original N
    mfc1 $t2, $f7          # $t2 = p
    
    mul $t3, $t0, $t0      # Total elements in padded matrix (N+2p)²

    # # p + N - 1
    # addi $t6, $t1, -1   # N - 1
    # add $t6, $t6, $t2   # N + p - 1
    
init_zeros:
    beqz $t3, start_copy
    l.s $f0, zero
    s.s $f0, ($s0)
    addi $s0, $s0, 4
    addi $t3, $t3, -1
    j init_zeros

start_copy:
    # Reset pointers
    la $s0, padded_matrix
    la $s1, image_matrix
    
    # Initialize row counter for padded matrix
    move $t3, $t2         # Start from p
    add $t7, $t1, $t2     # N + p

copy_row:
    bgt $t3, $t7, print_padded    # If beyond N + p rows
    
    move $t4, $t2              # Column counter for original matrix

copy_element:
    beq $t4, $t7, next_padding_row    # If done with N columns
    
    # Calculate padded matrix address based on $t3 and $t4
    mul $t5, $t3, $t0   # Row index * (N + 2p)
    add $t5, $t5, $t4   # Row index * (N + 2p) + column index
    mul $t5, $t5, 4     # Convert to byte offset
    add $t5, $s0, $t5   # Add base address

    # Copy value from original to padded
    l.s $f0, ($s1)
    s.s $f0, ($t5)    

    addi $s1, $s1, 4
    addi $t4, $t4, 1
    j copy_element

next_padding_row:
    
    addi $t3, $t3, 1      # Next row
    j copy_row

string_to_float:
    # Save return address
    addi $sp, $sp, -4
    sw $ra, 0($sp)

    li $t4, 0      # Integer part
    li $t5, 0      # Fraction part
    li $t6, 0      # Fraction digit count
    li $t7, 1      # Sign (1 for positive, -1 for negative)
    li $t8, 0      # Fraction flag
    move $t9, $a0  # Input string pointer

str_to_float_loop:
    lb $t1, ($t9)

    # Check for end of string or space
    beq $t1, 0, finish_float    # If null terminator, finish
    beq $t1, 32, finish_float   # If space, finish
    beq $t1, 46, decimal_point  # If '.', handle decimal point
    beq $t1, 45, negative_sign  # If '-', handle negative sign

    li $t2, 48     # ASCII '0'
    li $t3, 57     # ASCII '9'
    blt $t1, $t2, invalid_char
    bgt $t1, $t3, invalid_char
    sub $t1, $t1, $t2
    
    beq $t8, 0, handle_int_part
    j handle_frac_part

invalid_char:
    addi $t9, $t9, 1
    j str_to_float_loop

negative_sign:
    li $t7, -1     # Set sign to negative
    addi $t9, $t9, 1
    j str_to_float_loop

handle_int_part:
    mul $t4, $t4, 10
    add $t4, $t4, $t1
    addi $t9, $t9, 1
    j str_to_float_loop

decimal_point:
    li $t8, 1
    addi $t9, $t9, 1
    j str_to_float_loop

handle_frac_part:
    mul $t5, $t5, 10
    add $t5, $t5, $t1
    addi $t6, $t6, 1
    addi $t9, $t9, 1

    j str_to_float_loop

finish_float:
    # Convert integer part to float
    mtc1 $t4, $f0
    cvt.s.w $f0, $f0

    # Handle fraction part
    beqz $t6, apply_sign    # If no fraction, apply sign and return
    mtc1 $t5, $f2       # Convert fraction to float
    cvt.s.w $f2, $f2    # Convert to float
    
    li $t1, 1
    move $t2, $t6

pow_ten:
    beqz $t2, apply_fraction
    mul $t1, $t1, 10
    subi $t2, $t2, 1
    j pow_ten

apply_fraction:
    mtc1 $t1, $f4   # Convert to float
    cvt.s.w $f4, $f4    # Convert to float
    div.s $f2, $f2, $f4   # Divide fraction by 10^digit
    add.s $f0, $f0, $f2  # Add fraction to integer part

apply_sign:
    # Apply sign
    mtc1 $t7, $f6   # Convert sign to float
    cvt.s.w $f6, $f6    # Convert to float
    mul.s $f0, $f0, $f6 # Multiply integer part by sign

float_done:
    # Restore return address
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

file_error:
    j exit
    li $v0, 4
    la $a0, error_open
    syscall
    j exit

parse_error:
    li $v0, 4
    la $a0, error_parse
    syscall
    j exit

params_error:
    li $v0, 4
    la $a0, error_params
    syscall
    j exit

image_size_error:
    # Open output file
    li $v0, 13
    la $a0, output_file
    li $a1, 1
    li $a2, 0
    syscall
    move $s0, $v0

    # Write error message
    li $v0, 15
    move $a0, $s0
    la $a1, error_size
    li $a2, 21
    syscall
    j close_output_file

print_image_matrix:
    # Print header
    li $v0, 4
    la $a0, image_msg
    syscall
    
    # Initialize
    la $s5, image_matrix
    # Store base address of image matrix into image variable
    la $t0, image
    sw $s5, 0($t0)

    li $t0, 0          # Row counter
    li $t1, 0          # Column counter

print_image_loop:
    beq $t0, $s7, print_kernel_matrix   # If printed N rows, done
    
    # Print element
    l.s $f12, ($s5)
    li $v0, 2
    syscall
    
    # Print space
    li $v0, 4
    la $a0, space
    syscall
    
    # Update counters
    addi $t1, $t1, 1       # Increment column
    addi $s5, $s5, 4       # Move to next element
    
    # Check if row is complete
    beq $t1, $s7, new_image_row
    j print_image_loop

new_image_row:
    # Print newline
    li $v0, 4
    la $a0, newline
    syscall
    
    li $t1, 0              # Reset column counter
    addi $t0, $t0, 1       # Increment row counter
    j print_image_loop

print_kernel_matrix:
    # Print header
    li $v0, 4
    la $a0, kernel_msg
    syscall
    
    # Initialize
    la $s6, kernel_matrix
    # Store base address of kernel matrix into kernel variable
    la $t0, kernel
    sw $s6, 0($t0)
    li $t0, 0          # Row counter
    li $t1, 0          # Column counter

print_kernel_loop:
    beq $t0, $s3, done_printing  # If printed M rows, done
    
    # Print element
    l.s $f12, ($s6)
    li $v0, 2
    syscall
    
    # Print space
    li $v0, 4
    la $a0, space
    syscall
    
    # Update counters
    addi $t1, $t1, 1       # Increment column
    addi $s6, $s6, 4       # Move to next element
    
    # Check if row is complete
    beq $t1, $s3, new_kernel_row
    j print_kernel_loop

new_kernel_row:
    # Print newline
    li $v0, 4
    la $a0, newline
    syscall
    
    li $t1, 0              # Reset column counter
    addi $t0, $t0, 1       # Increment row counter
    j print_kernel_loop

done_printing:
    j add_padding

print_padded:
    # Print padding message
    li $v0, 4
    la $a0, padding_msg
    syscall
    
    # Print padded matrix
    la $s0, padded_matrix
    li $t4, 0              # Row counter
    
print_pad_loop:
    beq $t4, $t0, done_padding
    li $t5, 0              # Column counter
    
print_pad_row:
    beq $t5, $t0, print_pad_newline
    l.s $f12, ($s0)
    li $v0, 2
    syscall
    li $v0, 4
    la $a0, space
    syscall
    addi $s0, $s0, 4
    addi $t5, $t5, 1
    j print_pad_row
    
print_pad_newline:
    li $v0, 4
    la $a0, newline
    syscall
    addi $t4, $t4, 1
    j print_pad_loop

done_padding:
    j convo

convo:
    # If p is 0, no padding is needed, so use the original image matrix
    l.s $f0, p      # Load p
    l.s $f1, zero  # Load 0.0
    c.eq.s $f0, $f1    # Compare p to 0.0
    bc1t no_padding   # If p == 0, no padding needed

    # Use padded matrix
    lw $s5, padded
    j start_convolution

no_padding:
    # Use original image matrix
    lw $s5, image
    j start_convolution

start_convolution:
    # Load kernel matrix
    lw $s6, kernel
    # Load output matrix
    la $s2, output_matrix

    # Calculate output matrix size
    # ((N - M + 2p) / s + 1)
    l.s $f0, N      # $f0 = N
    l.s $f1, M      # $f1 = M
    l.s $f2, p      # $f2 = p
    l.s $f3, s      # $f3 = s
    # N - M + 2p
    sub.s $f4, $f0, $f1   # N - M
    l.s $f5, two          # Load 2.0
    mul.s $f6, $f2, $f5   # 2p
    add.s $f7, $f4, $f6   # N - M + 2p
    # N - M + 2p / s + 1
    div.s $f8, $f7, $f3   # (N - M + 2p) / s
    l.s $f9, one          # Load 1.0
    add.s $f10, $f8, $f9  # (N - M + 2p) / s + 1

    # N + 2p, N in $f0, p in $f2
    add.s $f14, $f0, $f6  # N + 2p

    # Convert to integer
    cvt.w.s $f10, $f10    # Convert to integer
    mfc1 $s3, $f10        # $s3 = output size

    # Convert M to integer
    cvt.w.s $f1, $f1       # Convert M to integer
    mfc1 $t4, $f1          # $t4 = M

    # Convert s to integer in t5
    cvt.w.s $f3, $f3       # Convert s to integer
    mfc1 $t5, $f3          # $t5 = s

    # Convert N + 2p to integer in t6
    cvt.w.s $f14, $f14     # Convert N + 2p to integer
    mfc1 $s7, $f14         # $t6 = N + 2p

do_convolution:
    li $t0, 0              # Row counter for output matrix
    li $t1, 0              # Column counter for output matrix
    li $t2, 0              # Row counter for kernel matrix
    
output_row:
    beq $t0, $s3, print_output_matrix   # If done with output matrix, print
    # Reset column counter
    li $t1, 0

output_col:
    beq $t1, $s3, next_output_row   # If done with output matrix row, move to next row
    
    # Reset sum
    l.s $f10, zero
    # Reset kernel row counter
    li $t2, 0

kernel_row:

    beq $t2, $t4, calculate_sum   # If done with kernel row, calculate sum
    # Reset kernel column counter
    li $t3, 0

kernel_col:
    # Compare kernel column counter to M ($f1)
    beq $t3, $t4, next_kernel_row   # If done with kernel column, move to next row

    # Calculate element index in image matrix
    # Image row index = Output row counter * stride($f3) + kernel row counter
    mul $t6, $t0, $t5   # Output row counter * s
    add $t6, $t6, $t2   # image row index

    # Image col index = Output col counter * stride($f3) + kernel col counter
    mul $t7, $t1, $t5   # Output col counter * s
    add $t7, $t7, $t3   # image col index

    # Calculate image matrix element address
    mul $t8, $t6, $s7   # Row index * N
    add $t8, $t8, $t7   # Add column index
    sll $t8, $t8, 2     # Multiply by 4 (word size)
    add $t8, $s5, $t8   # Add base address of image matrix

    # Calculate kernel matrix element address
    mul $t9, $t2, $t4   # Row index * M
    add $t9, $t9, $t3   # Add column index
    sll $t9, $t9, 2     # Multiply by 4 (word size)
    add $t9, $s6, $t9   # Add base address of kernel matrix

    # Load image element
    l.s $f11, ($t8)     # Load image element
    # Load kernel element
    l.s $f13, ($t9)     # Load kernel element

    # Multiply image element by kernel element
    mul.s $f11, $f11, $f13
    # Add to sum
    add.s $f10, $f10, $f11

    # Increment kernel column counter
    addi $t3, $t3, 1    # Next column
    j kernel_col

next_kernel_row:
    # Increment kernel row counter
    addi $t2, $t2, 1    # Next row
    j kernel_row

calculate_sum:
    l.s $f12, ten
    mul.s $f10, $f10, $f12
    round.w.s $f10, $f10
    cvt.s.w $f10, $f10
    div.s $f10, $f10, $f12

    # Store sum in output matrix
    s.s $f10, ($s2)    # Store sum in output matrix
    addi $s2, $s2, 4   # Move to next element in output matrix
    
    # Increment column counter
    addi $t1, $t1, 1     # Next column
    j output_col

next_output_row:    
    # Increment row counter
    addi $t0, $t0, 1    # Next row
    j output_row

print_output_matrix:
    # Print output matrix header
    li $v0, 4
    la $a0, output_msg
    syscall
    
    # Initialize
    la $s5, output_matrix  # Load output matrix address
    li $t0, 0             # Row counter
    li $t1, 0             # Column counter
    
print_output_loop:
    beq $t0, $s3, write_output    # If printed all rows, exit
    
print_output_row:
    beq $t1, $s3, new_output_row   # If row complete, go to next row
    
    # Print element
    l.s $f12, ($s5)
    li $v0, 2
    syscall
    
    # Print space
    li $v0, 4
    la $a0, space
    syscall
    
    # Update counters and pointer
    addi $t1, $t1, 1       # Next column
    addi $s5, $s5, 4       # Next element
    j print_output_row

new_output_row:
    # Print newline
    li $v0, 4
    la $a0, newline
    syscall
    
    li $t1, 0              # Reset column counter
    addi $t0, $t0, 1       # Next row
    j print_output_loop

write_output:
    # Open output file
    li $v0, 13
    la $a0, output_file
    li $a1, 1          # Write mode
    li $a2, 0          # Write permission
    syscall
    bltz $v0, file_error
    move $s0, $v0

    # Write output matrix to file
    la $s5, output_matrix
    li $t0, 0          # Row counter
    li $t1, 0          # Column counter
    la $s2, temp

write_output_row:
    beq $t0, $s3, close_output_file   # If done with output matrix, close file
    li $t1, 0       # Reset column counter

write_output_col:
    beq $t1, $s3, next_output_write_row   # If done with row, move to next row

    # Convert float to string and store in temp buffer
    l.s $f1, ($s5)        # Load float value
    l.s $f0, ten
    mul.s $f1, $f1, $f0
    cvt.w.s $f1, $f1
    mfc1 $t3, $f1

    li $t4, 10
    div $t3, $t4
    mflo $s6    # Quotient
    mfhi $s7    # Remainder

    la $t2, temp

    # Check for negative value
    bltz $t3, nega

done_negative:
    # Store quotient digit
    jal store_digit    # Convert and store quotient
    
    # Store decimal point
    li $s1, '.'        # ASCII for decimal point
    sb $s1, ($t2)      # Store in buffer
    addi $t2, $t2, 1   # Increment buffer pointer
    
    # Store remainder digit
    move $s6, $s7      # Move remainder to $s6 for conversion
    jal store_digit    # Convert and store remainder

    j write_to_file

nega:
    li $s4, -1
    mul $s6, $s6, $s4
    mul $s7, $s7, $s4
    li $t9, 45
    sb $t9, ($t2)
    addi $t2, $t2, 1
    j done_negative

# Function to convert and store multi-digit number
store_digit:
    move $t5, $s6          # Copy number to work with
    move $t6, $sp          # Save original stack pointer
    
    # Push digits onto stack (in reverse order)
push_loop:
    li $t7, 10            # Divisor
    div $t5, $t7          # Divide by 10
    mfhi $t8              # Get remainder (current digit)
    mflo $t5              # Get quotient for next iteration

    addi $t8, $t8, 48     # Convert digit to ASCII
    addi $sp, $sp, -4     # Adjust stack
    sw $t8, ($sp)         # Push digit onto stack
    
    bnez $t5, push_loop   # If quotient not zero, continue loop

    # Pop and store digits in buffer (in correct order)
pop_loop:
    lw $t8, ($sp)         # Get digit from stack
    addi $sp, $sp, 4      # Adjust stack pointer

    sb $t8, ($t2)         # Store digit in buffer
    addi $t2, $t2, 1      # Increment buffer pointer
    
    bne $sp, $t6, pop_loop # Continue until original stack pointer reached

    jr $ra                 # Return

write_to_file:
    sb $zero, ($t2)
    # Reset buffer pointer
    la $t2, temp
    li $t4, 0            # Initialize counter

count_loop:
    lb $t5, ($t2)        # Load byte from temp
    beqz $t5, done_count # If null terminator found, exit loop
    addi $t4, $t4, 1     # Increment counter
    addi $t2, $t2, 1     # Move to next byte
    j count_loop

done_count:
    move $s7, $t4        # Store length in $s7

    # Write temp buffer to file
    li $v0, 15            # Write to file syscall
    move $a0, $s0         # File descriptor
    la $a1, temp          # Use temp buffer as source
    move $a2, $s7            # Length of float string
    syscall
    bltz $v0, file_error

    # Write space after number
    li $v0, 15
    la $a1, space         # Space character
    li $a2, 1             # Write 1 byte
    syscall

    # Update counters and pointer
    addi $t1, $t1, 1       # Next column
    addi $s5, $s5, 4       # Next element
    la $t2, temp
    j write_output_col

next_output_write_row:
    # Write newline
    li $v0, 15
    la $a1, newline
    li $a2, 1
    syscall

    # Update counters and pointer
    addi $t0, $t0, 1       # Next row
    j write_output_row

close_output_file:
    # Close output file
    li $v0, 16
    move $a0, $s0
    syscall
    j exit

exit:
    li $v0, 10
    syscall