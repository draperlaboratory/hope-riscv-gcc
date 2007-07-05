/* Copyright (C) 2007  Free Software Foundation, Inc.

This file is part of GCC.

GCC is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free
Software Foundation; either version 2, or (at your option) any later
version.

In addition to the permissions in the GNU General Public License, the
Free Software Foundation gives you unlimited permission to link the
compiled version of this file into combinations with other programs,
and to distribute those combinations without any restriction coming
from the use of this file.  (The General Public License restrictions
do apply in other respects; for example, they cover modification of
the file, and distribution when not linked into a combine
executable.)

GCC is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
for more details.

You should have received a copy of the GNU General Public License
along with GCC; see the file COPYING.  If not, write to the Free
Software Foundation, 51 Franklin Street, Fifth Floor, Boston, MA
02110-1301, USA.  */

#include "bid_internal.h"

#define MAX_FORMAT_DIGITS     16
#define DECIMAL_EXPONENT_BIAS 398
#define MAX_DECIMAL_EXPONENT  767

#if DECIMAL_CALL_BY_REFERENCE

void
__bid64_quantize (UINT64 * pres, UINT64 * px,
		UINT64 *
		py _RND_MODE_PARAM _EXC_FLAGS_PARAM _EXC_MASKS_PARAM
		_EXC_INFO_PARAM) {
  UINT64 x, y;
#else

UINT64
__bid64_quantize (UINT64 x,
		UINT64 y _RND_MODE_PARAM _EXC_FLAGS_PARAM
		_EXC_MASKS_PARAM _EXC_INFO_PARAM) {
#endif
  UINT128 CT;
  UINT64 sign_x, sign_y, coefficient_x, coefficient_y, remainder_h, C64;
  UINT64 tmp, carry, res;
  int_float tempx;
  int exponent_x, exponent_y = 0, digits_x, extra_digits, amount, amount2;
  int expon_diff, total_digits, bin_expon_cx;
  unsigned rmode, status;

#if DECIMAL_CALL_BY_REFERENCE
#if !DECIMAL_GLOBAL_ROUNDING
  _IDEC_round rnd_mode = *prnd_mode;
#endif
  x = *px;
  y = *py;
#endif

  // unpack arguments, check for NaN or Infinity
  if (!unpack_BID64 (&sign_y, &exponent_y, &coefficient_y, y)) {
    // Inf. or NaN or 0
#ifdef SET_STATUS_FLAGS
    if ((x & SNAN_MASK64) == SNAN_MASK64)	// y is sNaN
      __set_status_flags (pfpsf, INVALID_EXCEPTION);
#endif

    // x=Inf, y=Inf?
    if (((x << 1) == 0xf000000000000000ull)
	&& ((y << 1) == 0xf000000000000000ull)) {
      res = x;
      BID_RETURN (res);
    }
    // Inf or NaN?
    if ((y & 0x7800000000000000ull) == 0x7800000000000000ull) {
#ifdef SET_STATUS_FLAGS
      if (((y & 0x7e00000000000000ull) == 0x7e00000000000000ull)	// sNaN
	  || (((y & 0x7c00000000000000ull) == 0x7800000000000000ull) &&	//Inf
	      ((x & 0x7c00000000000000ull) < 0x7800000000000000ull)))
	__set_status_flags (pfpsf, INVALID_EXCEPTION);
#endif
      res = 0x7c00000000000000ull;
      BID_RETURN (res);
    }
  }
  // unpack arguments, check for NaN or Infinity
  if (!unpack_BID64 (&sign_x, &exponent_x, &coefficient_x, x)) {
    // x is Inf. or NaN or 0

    // Inf or NaN?
    if ((x & 0x7800000000000000ull) == 0x7800000000000000ull) {
#ifdef SET_STATUS_FLAGS
      if (((x & 0x7e00000000000000ull) == 0x7e00000000000000ull)	// sNaN
	  || ((x & 0x7c00000000000000ull) == 0x7800000000000000ull))	//Inf 
	__set_status_flags (pfpsf, INVALID_EXCEPTION);
#endif
      res = 0x7c00000000000000ull;
      BID_RETURN (res);
    }

    res = very_fast_get_BID64_small_mantissa (sign_x, exponent_y, 0);
    BID_RETURN (res);
  }
  // get number of decimal digits in coefficient_x
  tempx.d = (float) coefficient_x;
  bin_expon_cx = ((tempx.i >> 23) & 0xff) - 0x7f;
  digits_x = __bid_estimate_decimal_digits[bin_expon_cx];
  if (coefficient_x >= __bid_power10_table_128[digits_x].w[0])
    digits_x++;

  expon_diff = exponent_x - exponent_y;
  total_digits = digits_x + expon_diff;

  // check range of scaled coefficient
  if ((UINT32) (total_digits + 1) <= 17) {
    if (expon_diff >= 0) {
      coefficient_x *= __bid_power10_table_128[expon_diff].w[0];
      res = very_fast_get_BID64 (sign_x, exponent_y, coefficient_x);
      BID_RETURN (res);
    }
    // must round off -expon_diff digits
    extra_digits = -expon_diff;
#ifndef IEEE_ROUND_NEAREST_TIES_AWAY
#ifndef IEEE_ROUND_NEAREST
    rmode = rnd_mode;
    if (sign_x && (unsigned) (rmode - 1) < 2)
      rmode = 3 - rmode;
#else
    rmode = 0;
#endif
#else
    rmode = 0;
#endif
    coefficient_x += __bid_round_const_table[rmode][extra_digits];

    // get P*(2^M[extra_digits])/10^extra_digits
    __mul_64x64_to_128 (CT, coefficient_x,
			__bid_reciprocals10_64[extra_digits]);

    // now get P/10^extra_digits: shift C64 right by M[extra_digits]-128
    amount = __bid_short_recip_scale[extra_digits];
    C64 = CT.w[1] >> amount;
#ifndef IEEE_ROUND_NEAREST_TIES_AWAY
#ifndef IEEE_ROUND_NEAREST
    if (rnd_mode == 0)
#endif
      if (C64 & 1) {
	// check whether fractional part of initial_P/10^extra_digits 
        // is exactly .5
	// this is the same as fractional part of 
	//   (initial_P + 0.5*10^extra_digits)/10^extra_digits is exactly zero

	// get remainder
	amount2 = 64 - amount;
	remainder_h = 0;
	remainder_h--;
	remainder_h >>= amount2;
	remainder_h = remainder_h & CT.w[1];

	// test whether fractional part is 0
	if (!remainder_h && (CT.w[0] < __bid_reciprocals10_64[extra_digits])) {
	  C64--;
	}
      }
#endif

#ifdef SET_STATUS_FLAGS
    status = INEXACT_EXCEPTION;
    // get remainder
    remainder_h = CT.w[1] << (64 - amount);
    switch (rmode) {
    case ROUNDING_TO_NEAREST:
    case ROUNDING_TIES_AWAY:
      // test whether fractional part is 0
      if ((remainder_h == 0x8000000000000000ull)
	  && (CT.w[0] < __bid_reciprocals10_64[extra_digits]))
	status = EXACT_STATUS;
      break;
    case ROUNDING_DOWN:
    case ROUNDING_TO_ZERO:
      if (!remainder_h && (CT.w[0] < __bid_reciprocals10_64[extra_digits]))
	status = EXACT_STATUS;
      //if(!C64 && rmode==ROUNDING_DOWN) sign_s=sign_y;
      break;
    default:
      // round up
      __add_carry_out (tmp, carry, CT.w[0],
		       __bid_reciprocals10_64[extra_digits]);
      if ((remainder_h >> (64 - amount)) + carry >=
	  (((UINT64) 1) << amount))
	status = EXACT_STATUS;
      break;
    }
    __set_status_flags (pfpsf, status);
#endif

    res = very_fast_get_BID64_small_mantissa (sign_x, exponent_y, C64);
    BID_RETURN (res);
  }

  if (total_digits < 0) {
#ifdef SET_STATUS_FLAGS
    __set_status_flags (pfpsf, INEXACT_EXCEPTION);
#endif
    C64 = 0;
#ifndef IEEE_ROUND_NEAREST_TIES_AWAY
#ifndef IEEE_ROUND_NEAREST
    rmode = rnd_mode;
    if (sign_x && (unsigned) (rmode - 1) < 2)
      rmode = 3 - rmode;
    if (rmode == ROUNDING_UP)
      C64 = 1;
#endif
#endif
    res = very_fast_get_BID64_small_mantissa (sign_x, exponent_y, C64);
    BID_RETURN (res);
  }
  // else  more than 16 digits in coefficient
#ifdef SET_STATUS_FLAGS
  __set_status_flags (pfpsf, INVALID_EXCEPTION);
#endif
  res = 0x7c00000000000000ull;
  BID_RETURN (res);

}
