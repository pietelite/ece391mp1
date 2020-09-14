
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
	MISSILE_CHAR	  = 32



	EXPLOSION = 64       	# Character to draw for an explosion - '@'
	CROSSHAIRS = 43 		 	# Crosshair character - '+'
	EMPTY = 32  					# Space character for clearing - ' '

	MISSILE_SIZE = 33			# Byte size of missiles
	STATUS_SIZE = 4				# Byte size of status

	XY_BIT_OFFSET = 16		# Offset of x and y position to get text-video location
	X_MIN = 0							# The minimum value on screen in x direction
	X_MAX = 79						# The maximum value on screen in x direction
	Y_MIN = 0 						# The minimum value on screen in y direction
	Y_MAX = 24						# The maximum value on screen in y direction

	COLUMNS = 80 					# Total column count
	ROWS = 25 						# Total row count

	# The start text-video offset of all bases
	FIRST_BASE = 3716
	SECOND_BASE = 3756
	THIRD_BASE = 3796

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
	movl    vmem_base_addr(,1),%edx
	movb    %cl,(%edx,%eax,1)
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

	call update_missiles
	call draw_bases
	call draw_crosshairs 		# Redraw because they might have gotten overwritten

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

	movl 8(%esp), %eax  				# make eax the cmd

	cmpl $0, %eax								# Check if eax is out of range
	jl mp1_ioctl_error
	cmpl $4, %eax
	jg mp1_ioctl_error

	jmp *jump_table(, %eax, 4)  # Valid command!

	mp1_ioctl_error:						# cmd was invalid, return error
	movl $-1, %eax
	ret

# ----------------- Functions private to this file -------------------

# void update_missiles()
# Iterates through each missile in the linked list
# starting at mp1_missile_list and updates its state
# Inputs    : None
# Outputs   : None
# Registers : Standard C calling convention
# 					: ecx is a pointer to the current missile
update_missiles:

	# Build stack frame
	pushl %ebp
	movl %ebp, %esp

	movl mp1_missile_list, %edx  	# hold "current" missile in ecx

	# Walk down struct missile linked list
	update_missile_loop:
		# Check if we're done by checking if missile list is null pointer
		testl %edx, %edx
		jz update_missile_loop_done

		# Erase the missile in the current location
		pushl %edx
		call get_missile_location 		# eax now holds the location of missile
		popl %edx
		movb $EMPTY, %cl							# enter a blank space

		pushl %edx								# Make sure to save ecx
		call mp1_poke
		popl %edx

		cmpl $0, EXPLODED(%edx)		# Are we exploding?
		jne skip_update_xy 				# Jump if not 0, because we're exploding

		# Not exploding
		movl VX(%edx), %eax				# Move velocity
		addl %eax, X(%edx)				# Add to x component
		movl VY(%edx), %eax				# Same with y
		addl %eax, Y(%edx)

		skip_update_xy:

		# Three cases processing...
		# 1. If moved out of range call mp1_missile_remove
		movl X(%edx), %eax					# Move X component into eax
		shrl $XY_BIT_OFFSET, %eax		# Shift so we're using just upper 16 bits
		cmpl $X_MIN, %eax						# Are we below bounds?
		jl remove_this_missile
		cmpl $X_MAX, %eax						# Are we above bounds?
		jg remove_this_missile
		movl Y(%edx), %eax 					# Move Y component into eax
		shrl $XY_BIT_OFFSET, %eax		# Shift so we're using just upper 16 bits
		cmpl $Y_MIN, %eax						# Are we below bounds?
		jl remove_this_missile
		cmpl $Y_MAX, %eax						# Are we above bounds?
		jg remove_this_missile

		# We're in bounds!

	  # 2. Check if reached destination...
		movl X(%edx), %eax					# Move x into eax and get correct bits
		shrl $16, %eax
		cmpl %eax, DEST_X(%edx)			# If these aren't equal, we're not there
		jne not_at_destination
		movl Y(%edx), %eax					# Move y into eax and get correct bits
		shrl $16, %eax
		cmpl %eax, DEST_Y(%edx)			# If these aren't equal, we're not there
		jne not_at_destination

		# 	We're there! Call missile_explode with a pointer to the missile
		#   struct as an argument
		pushl %edx
		call missile_explode 						# eax now has result of explosion
		popl %edx

		cmpl $0, %eax 									# inform user if changes were made
		je nothing_hit
		pushl %edx											# Preserve edx
		call mp1_notify_user
		popl %edx
		nothing_hit:

		decl EXPLODED(%edx)
		cmpl $0, EXPLODED(%edx)					# If we're done exploding now,
																		# we can remove and continue
		je remove_this_missile

		# 	Finally, draw explosion character
		pushl %edx
		call get_missile_location
		popl %edx

		movb $EXPLOSION, %cl
		pushl %edx											# Make sure to save ecx
		call mp1_poke
		popl %edx
		jmp update_missile_loop_continue

		not_at_destination:
		# 3. Otherwise (simply still moving to its destination)...
		#   Draw the missile character
		pushl %edx
		call get_missile_location
		popl %edx
		movb MISSILE_CHAR(%edx), %cl
		pushl %edx										# Make sure to save ecx
		call mp1_poke
		popl %edx

		# TWO CONTINUE CASES:
		# 1.
		update_missile_loop_continue:
		movl NEXT(%edx), %edx						# Loads next missile
		jmp update_missile_loop

		# 2.
		remove_this_missile:
		pushl %edx
		call mp1_missile_remove
		popl %edx
		movl %eax, %edx 							# Loads the next missile into the loop
																	# (mp1_missile_remove gives me next)
		jmp update_missile_loop

	update_missile_loop_done:
	leave
	ret

# void draw_bases()
# Draw the bases successively by calling "draw_base"
# with corresponding text-video location and string
# Inputs    : None
# Outputs   : None
# Registers : Standard C calling convention
draw_bases:
	pushl %ebp
	movl %esp, %ebp

	# Draw the bases
	# Put appropriate alive/dead base into eax
	movl $base_pic, %eax
	testl $0x000000FF, base_alive
	jnz show_first_base_alive
	movl $dead_base_pic, %eax
	show_first_base_alive:

	pushl %eax
	pushl $FIRST_BASE # start of first base
	call draw_base
	addl $8, %esp

	# Put appropriate alive/dead base into eax
	movl $base_pic, %eax
	testl $0x0000FF00, base_alive
	jnz show_second_base_alive
	movl $dead_base_pic, %eax
	show_second_base_alive:

	pushl %eax
	pushl $SECOND_BASE # start of second base
	call draw_base
	addl $8, %esp

	# Put appropriate alive/dead base into eax
	movl $base_pic, %eax
	testl $0x00FF0000, base_alive
	jnz show_third_base_alive
	movl $dead_base_pic, %eax
	show_third_base_alive:

	pushl %eax
	pushl $THIRD_BASE # start of first base
	call draw_base
	addl $8, %esp

	leave
	ret

# void draw_base(int start, char* str_ptr)
# Draws a 5-character base starting at a text-video offset
# Inputs    : video int-offset
# Outputs   : pointer to beginning of string
# Registers : Standard C calling convention
draw_base:
	pushl %ebp
	movl %esp, %ebp

	movl 8(%ebp), %eax		# Storing int offset
	xorl %edx, %edx 			# Counter
	draw_base_loop:
		cmpl $5, %edx				# If we've done 5, we're done
		jge exit_base_loop

		movl 12(%ebp), %ecx   				# Load pointer
		movb (%ecx, %edx, 1), %cl			# Get correct char from string

		pushl %eax
		pushl %edx
		call mp1_poke									# Draw
		popl %edx
		popl %eax

		addl $2, %eax 			# Increase offset by 2 bytes, to next square
		incl %edx
		jmp draw_base_loop	# Reset

	exit_base_loop:
	leave
	ret

# void draw_crosshairs()
# Simply draws the crosshairs onto the screen
# designaged by crosshairs_x and crosshairs_y
# and the character in CROSSHAIRS
# Input     : None
# Output    : None
# Registers : Standard C calling convention
draw_crosshairs:
	pushl %ebp
	movl %esp, %ebp

	movl crosshairs_y, %eax				# Get total crosshair offset
	imull $COLUMNS, %eax
	addl crosshairs_x, %eax
	shll $1, %eax									# Multiply by 2 because 2 bytes per elem
	movb $CROSSHAIRS, %cl
	call mp1_poke

	leave
	ret

# int get_missile_location(struct* missile)
# Return the integer offset in the text-video screen
# for a given input missile
# Input     : missile pointer
# Output    : integer video offset
# Registers : Standard C calling convention
get_missile_location:
	pushl %ebp
	movl %esp, %ebp

	movl 8(%ebp), %ecx								# Load argument
	movl Y(%ecx), %eax								# Load y value
	shrl $16, %eax										# 16 right to get high bytes
	imull $COLUMNS, %eax 							# 80 columns (done with y)
	movl X(%ecx), %edx								# Load x value into another register
	shrl $16, %edx										# 16 right to get high bytes
	addl %edx, %eax										# Add x component
	shll $1, %eax 										# Multiply by 2 because 2 bytes per elem

	leave
	ret

# missile* mp1_missile_remove(missile* ptr)
# Removes a missile from the linked list at the given
# location and returns a pointer to the next one
# Inputs     : pointer to missile to remove
# Outputs    : pointer to next missile
# Registers  : Standard C calling convention
mp1_missile_remove:
	pushl %ebp
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
		jne mp1_missile_remove_walk 		# We haven't found it yet, keep going

	# Connect the list across the one to be removed
	movl NEXT(%eax), %edx 		# edx now holds pointer to next missile
	movl %edx, NEXT(%ecx)
	pushl %eax
	call mp1_free
	popl %eax
	movl %edx, %eax 					# return pointer to next missile

	leave
	ret

# int mp1_ioctl_startgame(unsigned long ignore)
# Starts the game. Declares all variables and sets the crosshairs
# Inputs      : Ignored long
# Outputs     : 0
# Registers   : Standard C calling convention
mp1_ioctl_startgame:
	push %ebp
	movl %esp, %ebp
	# Initialize all variables
	movl $0, mp1_missile_list
	movl $0, base_alive
	movl $0, mp1_score
	movl $40, crosshairs_x
	movl $12, crosshairs_y
	movl $0, %eax
	leave
	ret

# int mp1_ioctl_addmissile(struct missile* user_missile)
# Adds a missile to the game.
# Inputs      : A pointer to a missile struct
# Outputs     : -1 if the missile could not be added due to memory issues,
# 						: 0 otherwise
# Registers   : Standard C calling convention
mp1_ioctl_addmissile:
	pushl %ebp
	movl %esp, %ebp

	# Allocate EMPTY
	pushl $MISSILE_SIZE 	# Give argument
	call mp1_malloc				# Make memory
	addl $4, %esp					# Remove argument
	cmpl $0, %eax 				# See if memory allocation failed
	je addmissile_fail

	# Copy data

	pushl $MISSILE_SIZE		# push byte count
	pushl 8(%ebp)  				# push argument from ioctl as "from" location
	pushl %eax						# push result of memory allocation as "to" location
	call mp1_copy_from_user
	popl %ecx							# memory location now in ecx
	addl $8, %esp					# Restore stack

	cmpl $0, %eax					# If the result of copy is 0, it worked
	je missile_copy_success

	# Missile copy failure
	pushl %ecx						# Give arg to mp1_free
	call mp1_free
	addl $4, %esp					# Restore stack
												# And we failed
	addmissile_fail:
	movl $-1, %eax
	leave
	ret

	missile_copy_success:
	movl mp1_missile_list, %eax		# Insert the new struct at ecx into the start
	movl %eax, NEXT(%ecx)
	movl %ecx, mp1_missile_list		# Head pointer to ecx location
	movl $0, %eax					# Returns 0 to signify success
	leave
	ret

# int mp1_ioctl_movexhairs(unsigned long xhair_delta_packed)
# Move crosshairs. X is moved by lower 16 bits of input,
# and Y is moved by higher 16 bits of input.
# Ensure the crosshairs do not leave the screen.
# Inputs    : packed long with both x and y changes
# Outputs   : 0
# Registers : Standard C calling convention
mp1_ioctl_movexhairs:
	pushl %ebp
	movl %esp, %ebp

	# Clear crosshairs from screen (same as draw crosshairs with different char)
	movl crosshairs_y, %eax
	imull $COLUMNS, %eax
	addl crosshairs_x, %eax
	shll $1, %eax
	movb $EMPTY, %cl
	call mp1_poke

	movl 8(%ebp), %eax  								# get packaged data (X)
	addl %eax, crosshairs_x							# Add data to crosshairs (packed)
	andl $0x0000FFFF, crosshairs_x			# Unpack (remove high bits)

	movl crosshairs_x, %eax							# Check if out of bounds in x
	cmpl $X_MIN, %eax
	jge x_good_low											# Jump if we're high enough
	movl $X_MIN, crosshairs_x
	x_good_low:

	cmpl $X_MAX, %eax
	jle x_good_high											# Jump if we're low enough
	movl $X_MAX, crosshairs_x
	x_good_high:

	movl 8(%esp), %eax  								# get packaged data (Y)
	shrl $16, %eax											# Unpack (move high to low)
	addl %eax, crosshairs_y							# Add data to crosshairs
	andl $0x0000FFFF, crosshairs_y			# Ensure we're just dealing with low bits

	movl $crosshairs_x, %eax						# Check if out of bounds in y
	cmpl $Y_MIN, %eax
	jge y_good_low											# Jump if we're high enough
	movl $Y_MIN, crosshairs_y
	y_good_low:

	cmpl $Y_MAX, crosshairs_y
	jle y_good_high											# Jump if we're low enough
	movl $Y_MAX, crosshairs_y
	y_good_high:

	call draw_crosshairs								# Draw crosshairs in place
	movl $0, %eax												# Success

	leave
	ret

# int mp1_ioctl_getstatus(unsigned long* user_status)
mp1_ioctl_getstatus:
	pushl %ebp
	movl %esp, %ebp

	movl mp1_score, %ecx

	# Add bases
	testl $0x000000FF, base_alive
	jle dead_first
	addl $0x00010000, %ecx					# First is alive -> add first bit of high 16
	dead_first:
	testl $0x0000FF00, base_alive
	jle dead_second
	addl $0x00020000, %ecx					# Second is alive -> add second bit of high 16
	dead_second:
	testl $0x00FF0000, base_alive
	jle dead_third
	addl $0x00040000, %ecx					# Third is alive -> add third bit of high 16
	dead_third:

	# Need to allocate memory to store getstatus
	pushl $STATUS_SIZE							# It takes three bytes to store status info
	call mp1_malloc
	addl $4, %esp 									# Clean stack
	cmpl $0, %eax
	je getstatus_fail

	# Put the data in buffer location
	movl %ecx, (%eax)

	# Copy to user space
	pushl $STATUS_SIZE							# Status info is 3 bytes (19 bits)
	pushl %eax 											# Location of data 'from'
	pushl 8(%ebp)										#	Location of data 'to'
	call mp1_copy_to_user
	addl $4, %esp 									# Clean stack ...
	popl %edx 											# Save buffer location for clearing
	addl $4, %esp 									# Clean stack continued

	pushl %eax 											# Save return value from copy

	pushl %edx 											# Clear buffer
	call mp1_free
	addl $4, %esp

	popl %eax 											# Get return value from copy

	cmpl $0, %eax
	je getstatus_success						# If we got 0, copy was successful

	# Copy error
	getstatus_fail:
	movl $-1, %eax
	leave
	ret

	getstatus_success:
	movl $0, %eax
	leave
	ret

# int mp1_ioctl_endgame(unsigned long ignore)
# Free all memory, return success
# Inputs    : None
# Outputs   : 0
# Registers : Standard C calling convention
mp1_ioctl_endgame:
	pushl %ebp
	movl %esp, %ebp

	delete_missile_loop:
		movl mp1_missile_list, %eax 	# Get head
		cmpl $0, %eax									# Check if its null (done)
		je end_delete_missile_loop

		pushl %eax
		call mp1_missile_remove
		addl $4, %esp 						# pop

	end_delete_missile_loop:

	leave
	ret

jump_table:
.long mp1_ioctl_startgame, mp1_ioctl_addmissile, mp1_ioctl_movexhairs, mp1_ioctl_getstatus, mp1_ioctl_endgame
