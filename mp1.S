
# mp1.S - missile-command version
# Good luck, and have fun!

.data

    # Constants for accessing the fields of a struct missile,
    # struct missile is defined in rtc.h and mp1.h

	NEXT 	  = 0
	X	  = 4
	Y	  = 8
	VX	  = 12
	VY	  = 16
	DEST_X	  = 20
	DEST_Y	  = 24
	EXPLODED  = 28
	C	  = 32

    # Character to draw for an explosion - '@'

	EXPLOSION = 64
	CROSSHAIRS = 43 #43
	EMPTY = 32 #32
	MISSILE_SIZE = 33

# Data shared between this file and rtc.c helper functions

# This '.globl' directive makes these symbols visible externally
.globl mp1_missile_list, base_alive, mp1_score

mp1_missile_list:	.long 0x0	# Head of list pointer
base_alive:		.long 0x0	# Array of 3 bytes, plus a padding byte
mp1_score:		.long 0x0	# Player's current score


# Data private to this  file

base_pic:     	    .string "/^^^\\"	# Picture of a live base
dead_base_pic: 	    .string "xxxxx"	# Picture of a dead base
crosshairs_x:		.long 0x0	# X-position of the crosshairs
crosshairs_y:		.long 0x0	# Y-position of the crosshairs

.text

# void mp1_poke(void);
# You can use this function to write to video memory.
#
# Interface: Register-based arguments (not C-style)
#    Inputs: %cl  - The byte you wish to write
#            %eax - Offset from the start of video memory that you wish
#                   to write to
#   Outputs: Text-mode video screen is written to at location %eax with
#            the byte in %cl
# Registers: Clobbers EDX

mp1_poke:
		movl    vmem_base_addr(,1),%ecx
		movb    %cl,(%ecx,%eax,1)
		ret

#   ----------------- Exported functions ---------------------

# void mp1_rtc_tasklet(unsigned long garbage);
# Performs three tasks:
#	(1) updates the list of missiles (implement this in update_missiles,
#           below, and call it from here).
#	(2) Redraw the bases - they may have been overwritten with missiles
#	(3) Redraw the crosshairs - it may have been overwritten with missiles
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention

.globl mp1_rtc_tasklet
mp1_rtc_tasklet:

		pushl %ebp
		movl %esp, %ebp

		#call update_missiles
		#call draw_bases
		#call draw_crosshairs

		leave
		ret

# removes struct missile at arg from list and memory
mp1_missile_remove:
		push %ebp
		movl %esp, %ebp

		# Keep previous as ecx, cur as eax, to_remove as edx

		# Quickly check if first one is to be removed
		movl 8(%ebp), %edx
		movl mp1_missile_list, %eax
		cmpl %eax, %edx
		# If it's equal, we just remove first elem
		# Otherwise, we have to walk through the list until we find it
		jne mp1_missile_remove_walk

		# It was the first one!
		movl NEXT(%eax), %ecx						# Make the first elem the next one
		movl %ecx, mp1_missile_list
		pushl %eax
		call mp1_free
		popl %eax
		leave
		ret

		mp1_missile_remove_walk:
			movl %eax, %ecx
			movl NEXT(%eax), %eax
			cmpl %edx, %eax
			je mp1_missile_remove_finish
			jmp mp1_missile_remove_walk

		mp1_missile_remove_finish:
		movl NEXT(%eax), %edx 	# Connect the list across the one to be removed
		movl %edx, NEXT(%ecx)
		pushl %eax
		call mp1_free
		popl %eax

		leave
		ret

# int mp1_ioctl(unsigned long arg, unsigned int cmd)
# The dispatch function for the MP1 ioctls - should use the cmd argument
# and a jumptable to execute one of the specific ioctls implemented below.
# Inputs   : unsigned long arg - parameter to the mp1_ioctl_....
#          : unsigned int cmd  - specifies which mp1_ioctl_... function
#          :                     to execute
# Outputs  : Returns an integer - depends on which ioctl() function is called
# Registers: Standard C calling convention

.globl mp1_ioctl
mp1_ioctl:

		# make eax the location of ioctl
		movl 8(%esp), %eax

		cmpl $0, %eax
		jl mp1_ioctl_error
		cmpl $4, %eax
		jg mp1_ioctl_error
		jmp *jump_table(, %eax, 4)

		mp1_ioctl_error:
		movl $-1, %eax
		ret

# ----------------- Functions private to this file -------------------

update_missiles:

		# Push registers
		pushl %ebp
		movl %ebp, %esp

		# Initialize registers
		movl mp1_missile_list, %ecx

		# Walk down struct missile linked list
		update_missile_loop:
			# Check if we're done by checking if missile list is null pointer
			testl %ecx, %ecx
			jz update_missile_loop_done

			# Erase the missile in the current location
			pushl %ecx
			call get_missile_location
			popl %ecx
			movb $EMPTY, %cl
			call mp1_poke

			# If not currently exploding, update x and y
			cmpl $0, EXPLODED(%ecx)
			jne skip_update_xy 			# Jump if not 0, because we're exploding
			movl VX(%ecx), %eax			# Move velocity
			addl %eax, X(%ecx)			# Add to x component
			movl VY(%ecx), %eax			# Same with y
			addl %eax, Y(%ecx)

			skip_update_xy:

			# Three cases processing...
			# 1. If moved out of range call mp1_missile_remove
			movl X(%ecx), %eax			# Move X comp into eax
			shrl $16, %eax					# Shift so we're using just upper 16 bits
			cmpl $0, %eax						# Are we below bounds?
			jl out_of_bounds
			cmpl $79, %eax					# Are we above bounds?
			jg out_of_bounds
			movl Y(%ecx), %eax 			# Move Y comp into eax
			shrl $16, %eax					# Shift so we're using just upper 16 bits
			cmpl $0, %eax						# Are we below bounds?
			jl out_of_bounds
			cmpl $24, %eax					# Are we above bounds?
			jg out_of_bounds
			jmp in_bounds # No worries! We're in bounds. Let's try other stuff!

			out_of_bounds:
			pushl %ecx
			call mp1_missile_remove
			popl %ecx
			jmp update_missile_loop_continue

			in_bounds:
		  # 2. Check if reached destination...
			movl X(%ecx), %eax
			shrl $16, %eax
			cmpl %eax, DEST_X(%ecx)
			jne not_at_destination
			movl Y(%ecx), %eax
			shrl $16, %eax
			cmpl %eax, DEST_Y(%ecx)
			jne not_at_destination

			# 	We're there! Call missile_explode with a pointer to the missile
			#   struct as an argumentx
			pushl %ecx
			call missile_explode 						# eax now has result
			popl %ecx

			cmpl $0, %eax 									# inform user about any changes
			je nothing_hit
			call mp1_notify_user
			nothing_hit:

			decl EXPLODED(%ecx)
			cmpl $0, EXPLODED(%ecx)
			jne not_finished_exploding
			pushl %ecx
			call mp1_missile_remove
			popl %ecx
			jmp update_missile_loop_continue

			not_finished_exploding:
			# 	Finally, draw explosion character
			pushl %ecx
			call get_missile_location
			popl %ecx
			movb $EXPLOSION, %cl
			jmp update_missile_loop_continue

			not_at_destination:
			# 3. Otherwise (simply still moving to its destination)...
			#   Draw the missile character
			pushl %ecx
			call get_missile_location
			popl %ecx
			movb C(%ecx), %cl

			update_missile_loop_continue:
			movl NEXT(%ecx), %ecx

		update_missile_loop_done:
		leave
		ret

draw_bases:

		pushl %ebp
		movl %esp, %ebp

		# Draw the bases
		# Decide whether first base is dead
		movl base_pic, %eax
		testl $0x00000011, base_alive
		jnz show_first_base_alive

		movl dead_base_pic, %eax
		show_first_base_alive:
		pushl %eax
		pushl $1938 # start of first base
		call draw_base
		addl $8, %esp

		# Decide whether second base is dead
		movl base_pic, %eax
		testl $0x00001100, base_alive
		jnz show_second_base_alive

		movl dead_base_pic, %eax
		show_second_base_alive:
		pushl %eax
		pushl $1958 # start of second base
		call draw_base
		addl $8, %esp

		# Decide whether first base is dead
		movl base_pic, %eax
		testl $0x00110000, base_alive
		jnz show_third_base_alive

		movl dead_base_pic, %eax
		show_third_base_alive:
		pushl %eax
		pushl $1978 # start of first base
		call draw_base
		addl $8, %esp

		leave
		ret

draw_crosshairs:
		movl crosshairs_y, %eax
		imull $160, %eax
		addl crosshairs_x, %eax
		addl crosshairs_x, %eax
		movb $CROSSHAIRS, %cl
		call mp1_poke

# Return the missile location in arg
# of the missile struct at ecx
# CLOBBERS EAX AND EDX
get_missile_location:
		pushl %ebp
		movl %esp, %ebp
		xorl %eax, %eax
		movl Y(%ecx), %eax
		shrl $16, %eax										# 16 right to get high bytes
		imull $160, %eax 									# 80 * 2 because 80 elems in row and 2 bytes
		movl X(%ecx), %edx
		shrl $16, %edx										# 16 right to get high bytes
		shll $1, %edx 										# Multiply by 2 because 2 bytes
		addl %edx, %eax
		leave
		ret

# void draw_base(int start, char* str_ptr)
draw_base:
		pushl %ebp
		movl %esp, %ebp
		movl 8(%ebp), %eax
		movb 12(%ebp), %cl
		xorl %ecx, %ecx
		base_loop:
			cmpl $5, %ecx
			jge exit_base_loop
			call mp1_poke
			incl %eax
			movb 12(%ebp, %eax, 1), %cl
			incl %ecx
			jmp base_loop

		exit_base_loop:
		leave
		ret

mp1_ioctl_startgame:
		push %ebp
		movl %esp, %ebp
		# Initialize all variables
		movl $0, mp1_missile_list
		movl $0, base_alive
		movl $0, mp1_score
		movl $40, crosshairs_x
		movl $12, crosshairs_y
		leave
		ret

# registers : ecx for counting incoming struct fields
mp1_ioctl_addmissile:
		pushl %ebp
		movl %esp, %ebp
		# Allocate EMPTY
		pushl $MISSILE_SIZE 	# Give argument
		call mp1_malloc				# Make memory
		addl $4, %esp					# Remove argument
		testl %eax, %eax 			# See if memory allocation failed
		jz addmissile_fail

		# Copy data

		pushl $MISSILE_SIZE		# push byte count
		pushl 8(%ebp)  				# push argument from ioctl as "from" location
		pushl %eax						# push result of memory allocation as "to" location
		call mp1_copy_from_user
		popl %ecx							# Restore stack, memory location now in ecx
		addl $8, %esp

		cmpl $0, %eax
		je missile_copy_success
		# Missile copy failure
		pushl %ecx
		call mp1_free 				# memory location of "to" is still in same place
		addl $4, %esp
		addmissile_fail:
		movl $-1, %eax
		leave
		ret

		missile_copy_success:
		movl mp1_missile_list, %eax
		movl %eax, NEXT(%ecx)
		movl %ecx, mp1_missile_list
		movl $0, %eax					# Returns 0 to signify success
		leave
		ret

mp1_ioctl_movexhairs:
		pushl %ebp
		movl %esp, %ebp
		# Clear crosshairs from screen
		movl crosshairs_y, %eax
		imull $160, %eax
		addl crosshairs_x, %eax
		addl crosshairs_x, %eax
		movb $EMPTY, %cl
		call mp1_poke

		movl 4(%esp), %eax  								# get packaged data
		addl %eax, crosshairs_x
		andl $0x0000FFFF, crosshairs_x
		movl $crosshairs_x, %eax

		cmpl $0, crosshairs_x
		jge x_good_low
		movl $0, crosshairs_x
		x_good_low:

		cmpl $79, crosshairs_x
		jle x_good_high
		movl $79, crosshairs_x
		x_good_high:

		movl 4(%esp), %eax  								# get packaged data
		shrl $16, %eax
		addl %eax, crosshairs_y
		andl $0x0000FFFF, crosshairs_y
		movl $crosshairs_x, %eax

		cmpl $0, crosshairs_y
		jge y_good_low
		movl $0, crosshairs_y
		y_good_low:

		cmpl $24, crosshairs_y
		jle y_good_high
		movl $24, crosshairs_y
		y_good_high:

		call draw_crosshairs
		
		leave
		ret

mp1_ioctl_getstatus:
		pushl %ebp
		movl %esp, %ebp
		xorl %eax, %eax

		# Add score
		addl mp1_score, %eax

		# Add bases
		testl $0x00000011, base_alive
		jle dead_first
		addl $0x00010000, %eax
		dead_first:
		testl $0x00001100, base_alive
		jle dead_second
		addl $0x00020000, %eax
		dead_second:
		testl $0x00110000, base_alive
		jle dead_third
		addl $0x00040000, %eax
		dead_third:
		leave
		ret

mp1_ioctl_endgame:
		pushl %ebp
		movl %esp, %ebp
		delete_missile_loop:
			cmpl $0, mp1_missile_list
			je end_delete_missile_loop

			movl $mp1_missile_list, %eax
			movl NEXT(%eax), %eax
			pushl mp1_missile_list
			call mp1_free
			addl $4, %esp # pop
			movl %eax, mp1_missile_list

		end_delete_missile_loop:
		leave
		ret

jump_table:
.long mp1_ioctl_startgame, mp1_ioctl_addmissile, mp1_ioctl_movexhairs, mp1_ioctl_getstatus, mp1_ioctl_endgame
