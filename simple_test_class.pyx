"""
Example of using NFFTPY from another Cython module.
(For an example of using NFFTPY from Python, see tests/test_nfftpy.py.)

This module is a modification of simple_test.pyx, and like it is a translation
of the nfft example program, simple_test.c. However, simple_test.pyx only uses
the NFFT library directly (via its Cython interface), whereas this module uses
the NFFTPY class wrapper of the nfft_plan structure. As such, it is an
intermediate stage towards accessing the library from Python, as is done in
the unit test module tests/test_nfftpy.py.

This module prints the same not very useful output as simple_test.c (and
.pyx), using the same nfft utility function. It also prints the same data
using numpy, both in a similar format (for comparison), and with full
precision.

Finally, it saves the input and output data arrays, in full precision, to text
files, for use (after moving to the tests directory) in tests/test_nfftpy.py.

"""
import time

import numpy as np
cimport numpy as np

from cnfft3 cimport fftw_complex, nfft_plan, np_cdef_float, \
    PRE_PHI_HUT, FG_PSI, PRE_LIN_PSI, PRE_FG_PSI, PRE_PSI, PRE_FULL_PSI, \
    MALLOC_X, MALLOC_F_HAT, MALLOC_F, FFT_OUT_OF_PLACE, FFTW_INIT, PRE_ONE_PSI,\
    FFTW_ESTIMATE, FFTW_DESTROY_INPUT

from cnfft3util cimport nfft_vrand_shifted_unit_double, \
    nfft_vrand_unit_complex, nfft_vpr_complex

from nfftpy import NfftPlanWrapper, dtype_int
from nfftpy cimport NfftPlanWrapper
from nfftpy cimport fftw_complex_array_to_numpy, float_array_to_numpy

def nfft_second():
    "replacing nfft timer with python timer"
    return time.time()

def printf(fstring, *vals):
    "replacing C print with python print"
    print fstring % vals


cdef nfft_vpr_complex2(fftw_complex *p, int n, title, n_elems=None):
    """
    Parameters:

        * p: a pointer to an array of fftw_complex
        * n: maximum number of elements to show
        * title: title string for printing
        * n_elems: if present, the actual number of elements  in the array.
    Print 'n' elements using both the native NFFT function and numpy.
    Return the numpy array.
    """
    nfft_vpr_complex(p, n, title)
    if n_elems is None:
        n_elems = n
    cdef np.ndarray[np.complex128_t] arr = \
        fftw_complex_array_to_numpy(p, n_elems)
    print "\n  With numpy:"
    for i in range(0,n,4):
        print "   %2i" % i,
        for j in range(i, min(n, i+4)):
            cx = arr[j]
            print ' %5.2f + %5.2fJ,' % (cx.real, cx.imag),
        print
    for x in arr[:n]:
        print repr(x)
    return arr

def save_arrays_to_file(filename, arrays):
    """
    Save each element of each 1D array to the specified file, one element
    per line. Precede the data from each array by a line which gives the
    length of that array.
    """
    with file(filename, 'w') as f:
        for _a in arrays:
            f.write(str(len(_a))+'\n')
            for _x in _a:
                f.write(repr(_x).strip('()') + '\n')


def simple_test_nfft_1d():
    cdef int N=14
    cdef int M=19

    # init an one dimensional plan
    cdef NfftPlanWrapper pw = NfftPlanWrapper.nfft_init_1d(N, M)
    cdef nfft_plan p = pw.plan

    # init pseudo random nodes
    nfft_vrand_shifted_unit_double(p.x, p.M_total)
    cdef np.ndarray[np_cdef_float] x_arr = float_array_to_numpy(p.x, p.M_total)
    print 'x values from numpy array:'
    for x in x_arr:
        print repr(x)

    # precompute psi, the entries of the matrix B
    if p.nfft_flags & PRE_ONE_PSI:
        pw.nfft_precompute_one_psi()
    # init pseudo random Fourier coefficients and show them
    nfft_vrand_unit_complex(p.f_hat, p.N_total)
    f_hat_arr = nfft_vpr_complex2(p.f_hat, p.N_total,
        "given Fourier coefficients, vector f_hat")

    # direct trafo and show the result
    t=nfft_second()
    pw.ndft_trafo()
    t=nfft_second() - t
    f_arr = nfft_vpr_complex2(p.f, p.M_total, "ndft, vector f")
    printf(" took %e seconds.", t)

    # approx. trafo and show the result
    pw.nfft_trafo()
    nfft_vpr_complex2(p.f, p.M_total, "nfft, vector f")

    # approx. adjoint and show the result
    pw.ndft_adjoint()
    f_hat_adj_arr = nfft_vpr_complex2(p.f_hat, p.N_total,
        "adjoint ndft, vector f_hat")

    # approx. adjoint and show the result
    pw.nfft_adjoint()
    nfft_vpr_complex2(p.f_hat, p.N_total, "adjoint nfft, vector f_hat")

    # finalise the one dimensional plan
    pw.nfft_finalize()

    # Save the input and output arrays for use in unit testing.
    # We don't save both f or both adjoint f_hat because they
    # should be almost equal (which is tested in the unit test.)
    save_arrays_to_file('simple_test_nfft_1d.txt',
                        [x_arr, f_hat_arr, f_arr, f_hat_adj_arr])


def simple_test_nfft_2d():
    cdef int K, k, M

    N = np.array([32, 14], dtype=dtype_int)
    n = np.array([64, 32], dtype=dtype_int)
    M=N[0]*N[1]
    K=16 # number of entries to show from each array

    t=nfft_second()
    # init a two dimensional plan
    cdef NfftPlanWrapper pw = \
        NfftPlanWrapper.nfft_init_guru(2, N, M, n, 7,
            PRE_PHI_HUT| PRE_FULL_PSI| MALLOC_F_HAT| MALLOC_X| MALLOC_F |
            FFTW_INIT| FFT_OUT_OF_PLACE,
            FFTW_ESTIMATE| FFTW_DESTROY_INPUT)
    cdef nfft_plan p = pw.plan

    # init pseudo random nodes
    num_x = p.d * p.M_total
    nfft_vrand_shifted_unit_double(p.x, num_x)
    cdef np.ndarray[np_cdef_float] x_arr = float_array_to_numpy(p.x, num_x)
    print 'x values from numpy array (first few entries):'
    for x in x_arr[:K]:
        print repr(x)

    # precompute psi, the entries of the matrix B
    if p.nfft_flags & PRE_ONE_PSI:
        pw.nfft_precompute_one_psi()

    # init pseudo random Fourier coefficients and show them
    nfft_vrand_unit_complex(p.f_hat, p.N_total)

    t=nfft_second()-t
    f_hat_arr = nfft_vpr_complex2(p.f_hat,K,
        "given Fourier coefficients, vector f_hat (first few entries)",
        p.N_total)
    printf(" ... initialisation took %e seconds.",t)

    # direct trafo and show the result
    t=nfft_second()
    pw.ndft_trafo()
    t=nfft_second()-t
    f_arr = nfft_vpr_complex2(p.f,K,"ndft, vector f (first few entries)",
        p.M_total)
    printf(" took %e seconds.",t)

    # approx. trafo and show the result
    t=nfft_second()
    pw.nfft_trafo()
    t=nfft_second()-t
    nfft_vpr_complex2(p.f,K,"nfft, vector f (first few entries)",
        p.M_total)
    printf(" took %e seconds.",t)

    # direct adjoint and show the result
    t=nfft_second()
    pw.ndft_adjoint()
    t=nfft_second()-t
    f_hat_adj_arr = nfft_vpr_complex2(p.f_hat,K,
        "adjoint ndft, vector f_hat (first few entries)", p.N_total)
    printf(" took %e seconds.",t)

    # approx. adjoint and show the result
    t=nfft_second()
    pw.nfft_adjoint()
    t=nfft_second()-t
    nfft_vpr_complex2(p.f_hat,K,
        "adjoint nfft, vector f_hat (first few entries)", p.N_total)
    printf(" took %e seconds.",t)

    # finalise the two dimensional plan
    pw.nfft_finalize()

    # Save the input and output arrays for use in unit testing.
    # We don't save both f or both adjoint f_hat because they
    # should be almost equal (which is tested in the unit test.)
    save_arrays_to_file('simple_test_nfft_2d.txt',
                        [x_arr, f_hat_arr, f_arr, f_hat_adj_arr])

def main():
    printf("\n\n1) computing a one dimensional ndft, nfft and adjoints")
    simple_test_nfft_1d()

    printf("\n\n2) computing a two dimensional ndft, nfft and adjoints");
    simple_test_nfft_2d()

main()
