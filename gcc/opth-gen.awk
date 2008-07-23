#  Copyright (C) 2003,2004,2005,2006,2007 Free Software Foundation, Inc.
#  Contributed by Kelley Cook, June 2004.
#  Original code from Neil Booth, May 2003.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation; either version 3, or (at your option) any
# later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; see the file COPYING3.  If not see
# <http://www.gnu.org/licenses/>.

# This Awk script reads in the option records generated from 
# opt-gather.awk, combines the flags of duplicate options and generates a
# C header file.
#
# This program uses functions from opt-functions.awk
# Usage: awk -f opt-functions.awk -f opth-gen.awk < inputfile > options.h

BEGIN {
	n_opts = 0
	n_langs = 0
	n_target_save = 0
	n_extra_masks = 0
	quote = "\042"
	comma = ","
	FS=SUBSEP
}

# Collect the text and flags of each option into an array
	{
		if ($1 == "Language") {
			langs[n_langs] = $2
			n_langs++;
		}
		else if ($1 == "TargetSave") {
			# Make sure the declarations are put in source order
			target_save_decl[n_target_save] = $2
			n_target_save++
		}
		else {
			name = opt_args("Mask", $1)
			if (name == "") {
				opts[n_opts]  = $1
				flags[n_opts] = $2
				help[n_opts]  = $3
				n_opts++;
			}
			else {
				extra_masks[n_extra_masks++] = name
			}
		}
	}

# Dump out an enumeration into a .h file.
# Combine the flags of duplicate options.
END {
print "/* This file is auto-generated by opth-gen.awk.  */"
print ""
print "#ifndef OPTIONS_H"
print "#define OPTIONS_H"
print ""
print "extern int target_flags;"
print "extern int target_flags_explicit;"
print ""

have_save = 0;

for (i = 0; i < n_opts; i++) {
	if (flag_set_p("Save", flags[i]))
		have_save = 1;

	name = var_name(flags[i]);
	if (name == "")
		continue;

	if (name in var_seen)
		continue;

	var_seen[name] = 1;
	print "extern " var_type(flags[i]) name ";"
}
print ""

# All of the optimization switches gathered together so they can be saved and restored.
# This will allow attribute((cold)) to turn on space optimization.

# Change the type of normal switches from int to unsigned char to save space.
# Also, order the structure so that pointer fields occur first, then int
# fields, and then char fields to provide the best packing.

print "#if !defined(GCC_DRIVER) && !defined(IN_LIBGCC2)"
print ""
print "/* Structure to save/restore optimization and target specific options.  */";
print "struct cl_optimization GTY(())";
print "{";

n_opt_char = 2;
n_opt_short = 0;
n_opt_int = 0;
n_opt_other = 0;
var_opt_char[0] = "unsigned char optimize";
var_opt_char[1] = "unsigned char optimize_size";

for (i = 0; i < n_opts; i++) {
	if (flag_set_p("Optimization", flags[i])) {
		name = var_name(flags[i])
		if(name == "")
			continue;

		if(name in var_opt_seen)
			continue;

		var_opt_seen[name]++;
		otype = var_type_struct(flags[i]);
		if (otype ~ "^((un)?signed +)?int *$")
			var_opt_int[n_opt_int++] = otype name;

		else if (otype ~ "^((un)?signed +)?short *$")
			var_opt_short[n_opt_short++] = otype name;

		else if (otype ~ "^((un)?signed +)?char *$")
			var_opt_char[n_opt_char++] = otype name;

		else
			var_opt_other[n_opt_other++] = otype name;
	}
}

for (i = 0; i < n_opt_other; i++) {
	print "  " var_opt_other[i] ";";
}

for (i = 0; i < n_opt_int; i++) {
	print "  " var_opt_int[i] ";";
}

for (i = 0; i < n_opt_short; i++) {
	print "  " var_opt_short[i] ";";
}

for (i = 0; i < n_opt_char; i++) {
	print "  " var_opt_char[i] ";";
}

print "};";
print "";

# Target and optimization save/restore/print functions.
print "/* Structure to save/restore selected target specific options.  */";
print "struct cl_target_option GTY(())";
print "{";

n_target_char = 0;
n_target_short = 0;
n_target_int = 0;
n_target_other = 0;

for (i = 0; i < n_target_save; i++) {
	if (target_save_decl[i] ~ "^((un)?signed +)?int +[_a-zA-Z0-9]+$")
		var_target_int[n_target_int++] = target_save_decl[i];

	else if (target_save_decl[i] ~ "^((un)?signed +)?short +[_a-zA-Z0-9]+$")
		var_target_short[n_target_short++] = target_save_decl[i];

	else if (target_save_decl[i] ~ "^((un)?signed +)?char +[_a-zA-Z0-9]+$")
		var_target_char[n_target_char++] = target_save_decl[i];

	else
		var_target_other[n_target_other++] = target_save_decl[i];
}

if (have_save) {
	for (i = 0; i < n_opts; i++) {
		if (flag_set_p("Save", flags[i])) {
			name = var_name(flags[i])
			if(name == "")
				name = "target_flags";

			if(name in var_save_seen)
				continue;

			var_save_seen[name]++;
			otype = var_type_struct(flags[i])
			if (otype ~ "^((un)?signed +)?int *$")
				var_target_int[n_target_int++] = otype name;

			else if (otype ~ "^((un)?signed +)?short *$")
				var_target_short[n_target_short++] = otype name;

			else if (otype ~ "^((un)?signed +)?char *$")
				var_target_char[n_target_char++] = otype name;

			else
				var_target_other[n_target_other++] = otype name;
		}
	}
} else {
	var_target_int[n_target_int++] = "int target_flags";
}

for (i = 0; i < n_target_other; i++) {
	print "  " var_target_other[i] ";";
}

for (i = 0; i < n_target_int; i++) {
	print "  " var_target_int[i] ";";
}

for (i = 0; i < n_target_short; i++) {
	print "  " var_target_short[i] ";";
}

for (i = 0; i < n_target_char; i++) {
	print "  " var_target_char[i] ";";
}

print "};";
print "";
print "";
print "/* Save optimization variables into a structure.  */"
print "extern void cl_optimization_save (struct cl_optimization *);";
print "";
print "/* Restore optimization variables from a structure.  */";
print "extern void cl_optimization_restore (struct cl_optimization *);";
print "";
print "/* Print optimization variables from a structure.  */";
print "extern void cl_optimization_print (FILE *, int, struct cl_optimization *);";
print "";
print "/* Save selected option variables into a structure.  */"
print "extern void cl_target_option_save (struct cl_target_option *);";
print "";
print "/* Restore selected option variables from a structure.  */"
print "extern void cl_target_option_restore (struct cl_target_option *);";
print "";
print "/* Print target option variables from a structure.  */";
print "extern void cl_target_option_print (FILE *, int, struct cl_target_option *);";
print "#endif";
print "";

for (i = 0; i < n_opts; i++) {
	name = opt_args("Mask", flags[i])
	vname = var_name(flags[i])
	mask = "MASK_"
	if (vname != "") {
		mask = "OPTION_MASK_"
	}
	if (name != "" && !flag_set_p("MaskExists", flags[i]))
		print "#define " mask name " (1 << " masknum[vname]++ ")"
}
for (i = 0; i < n_extra_masks; i++) {
	print "#define MASK_" extra_masks[i] " (1 << " masknum[""]++ ")"
}

for (var in masknum) {
	if (masknum[var] > 31) {
		if (var == "")
			print "#error too many target masks"
		else
			print "#error too many masks for " var
	}
}
print ""

for (i = 0; i < n_opts; i++) {
	name = opt_args("Mask", flags[i])
	vname = var_name(flags[i])
	macro = "OPTION_"
	mask = "OPTION_MASK_"
	if (vname == "") {
		vname = "target_flags"
		macro = "TARGET_"
		mask = "MASK_"
	}
	if (name != "" && !flag_set_p("MaskExists", flags[i]))
		print "#define " macro name \
		      " ((" vname " & " mask name ") != 0)"
}
for (i = 0; i < n_extra_masks; i++) {
	print "#define TARGET_" extra_masks[i] \
	      " ((target_flags & MASK_" extra_masks[i] ") != 0)"
}
print ""

for (i = 0; i < n_opts; i++) {
	opt = opt_args("InverseMask", flags[i])
	if (opt ~ ",") {
		vname = var_name(flags[i])
		macro = "OPTION_"
		mask = "OPTION_MASK_"
		if (vname == "") {
			vname = "target_flags"
			macro = "TARGET_"
			mask = "MASK_"
		}
		print "#define " macro nth_arg(1, opt) \
		      " ((" vname " & " mask nth_arg(0, opt) ") == 0)"
	}
}
print ""

for (i = 0; i < n_langs; i++) {
	macros[i] = "CL_" langs[i]
	gsub( "[^A-Za-z0-9_]", "X", macros[i] )
	s = substr("            ", length (macros[i]))
	print "#define " macros[i] s " (1 << " i ")"
    }
print "#define CL_LANG_ALL   ((1 << " n_langs ") - 1)"

print ""
print "enum opt_code"
print "{"
	
for (i = 0; i < n_opts; i++)
	back_chain[i] = "N_OPTS";

for (i = 0; i < n_opts; i++) {
	# Combine the flags of identical switches.  Switches
	# appear many times if they are handled by many front
	# ends, for example.
	while( i + 1 != n_opts && opts[i] == opts[i + 1] ) {
		flags[i + 1] = flags[i] " " flags[i + 1];
		i++;
	}

	len = length (opts[i]);
	enum = "OPT_" opts[i]
	if (opts[i] == "finline-limit=" || opts[i] == "Wlarger-than=")
		enum = enum "eq"
	gsub ("[^A-Za-z0-9]", "_", enum)

	# If this switch takes joined arguments, back-chain all
	# subsequent switches to it for which it is a prefix.  If
	# a later switch S is a longer prefix of a switch T, T
	# will be back-chained to S in a later iteration of this
	# for() loop, which is what we want.
	if (flag_set_p("Joined.*", flags[i])) {
		for (j = i + 1; j < n_opts; j++) {
			if (substr (opts[j], 1, len) != opts[i])
				break;
			back_chain[j] = enum;
		}
	}

	s = substr("                                     ", length (opts[i]))
	if (i + 1 == n_opts)
		comma = ""

	if (help[i] == "")
		hlp = "0"
	else
		hlp = "N_(\"" help[i] "\")";

	print "  " enum "," s "/* -" opts[i] " */"
}

print "  N_OPTS"
print "};"
print ""
print "#endif /* OPTIONS_H */"
}
