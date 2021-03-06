"""
Unit tests for NFFTPY (cython wrapper for NFFT libraries)

This also serves as a simple example of using NFFTPY from Python.

In part, this is a python translation of NFFT's examples/nfft/simple_test.c.

However, for reproducibility, instead of using NFFT's pseudo-random data
generator here, we use the input and output arrays which were previously
generated and saved to files by simple_test_class.pyx, and were spot-checked
by hand against the data printed by NFFT's original simple_test.c.

These data files are different when generated on different systems, presumably
because of different pseudo-random number generation, but they should work on
any system. Here, for each of the 1d and 2d tests, we use two sets of files,
which were generated on 32 and 64-bit Ubuntu VMs.

FIXME: Need unit tests examining non-random data sampled from simple
functions with known transforms.

"""
import os
import numpy as np
from numpy.testing import assert_equal, assert_array_almost_equal, \
     assert_raises

from nfftpy import NfftPlanWrapper, \
    dtype_int, dtype_float, dtype_complex, \
    PRE_PHI_HUT, FG_PSI, PRE_LIN_PSI, PRE_FG_PSI, PRE_PSI, PRE_FULL_PSI, \
    MALLOC_X, MALLOC_F_HAT, MALLOC_F, FFT_OUT_OF_PLACE, FFTW_INIT, PRE_ONE_PSI,\
    FFTW_ESTIMATE, FFTW_DESTROY_INPUT

def read_sample_data(filename, pw):
    """
    Read a set of sample data which was written by simple_test_class.pyx. It
    consists of 4 concatenated arrays, each preceded by its number of elements.
    Validate the length of each array against the expected length, given the
    plan wrapper pw.

    Returns a list of 4 numpy arrays:
        x_data : dtype=float
        f_hat_data, f_data, adjoint_f_hat_data : dtype=complex
    """
    num_x = pw.d * pw.M_total
    data_filename = os.path.join(os.path.dirname(__file__), filename)
    data = np.loadtxt(data_filename, dtype=dtype_complex)
    data_divided = []
    i = 0
    corruption_msg = ('test data in %s is apparently corrupted at row %%i' %
                      data_filename)
    for expected_len in (num_x, pw.N_total, pw.M_total, pw.N_total):
        n_elem = int(round(data[i].real))
        if n_elem != expected_len:
            raise IOError(corruption_msg % i)
        i += 1
        next_elem = i + n_elem
        data_divided.append(data[i : next_elem])
        i += n_elem
    if next_elem != len(data):
        raise IOError(corruption_msg % i)
    data_divided[0] = data_divided[0].real.astype(dtype_float)
    return data_divided


def check_a_plan(pw, x_data, f_hat_data, f_data, adjoint_f_hat_data):
    """
    After a plan is initialized, feed it data, compute transforms,
    and check the results.
    """
    # init pseudo random nodes and check that their values took:
    pw.x = x_data
    _x = pw.x
    assert_array_almost_equal(_x, x_data)

    # precompute psi, the entries of the matrix B
    if pw.nfft_flags & PRE_ONE_PSI:
        pw.nfft_precompute_one_psi()

    # init pseudo random Fourier coefficients and check their values took:
    pw.f_hat = f_hat_data
    _f_hat = pw.f_hat
    assert_array_almost_equal(_f_hat, f_hat_data)

    # direct trafo and test the result
    pw.ndft_trafo()
    _f = pw.f
    assert_array_almost_equal(_f, f_data)

    # approx. trafo and check the result
    # first clear the result array to be sure that it is actually touched.
    pw.f = np.zeros_like(f_data)
    pw.nfft_trafo()
    _f2 = pw.f
    assert_array_almost_equal(_f2, f_data)

    # direct adjoint and check the result
    pw.ndft_adjoint()
    _f_hat2 = pw.f_hat
    assert_array_almost_equal(_f_hat2, adjoint_f_hat_data)

    # approx. adjoint and check the result.
    # first clear the result array to be sure that it is actually touched.
    pw.f_hat = np.zeros_like(f_hat_data)
    pw.nfft_adjoint()
    _f_hat3 = pw.f_hat
    assert_array_almost_equal(_f_hat3, adjoint_f_hat_data)

    # finalise (destroy) the 1D plan
    pw.nfft_finalize()

    # check that instance is no longer usable:
    assert_raises( RuntimeError, pw.nfft_finalize)
    assert_raises( RuntimeError, pw.nfft_trafo)
    assert_raises( RuntimeError, lambda : pw.M_total)


def read_and_check(pw, data_filename):
    sample_data_arrays = read_sample_data( data_filename, pw)
    check_a_plan(pw, *sample_data_arrays)


def simple_test_nfft_1d():
    """
    Reproduce and check the 1d case from examples/nfft/simple_test.c.
    """
    N=14
    M=19
    for data_file in ('simple_test_nfft_1d_32.txt',
                      'simple_test_nfft_1d_64.txt'):
        # init a one dimensional plan
        pw = NfftPlanWrapper.nfft_init_1d(N, M)
        assert_equal(pw.M_total, M)
        assert_equal(pw.N_total, N)
        assert_equal(pw.d, 1)
        read_and_check(pw, data_file)


def simple_test_nfft_2d():
    """
    Reproduce and check the 2d case from examples/nfft/simple_test.c.
    """
    N = np.array([32, 14], dtype=dtype_int)
    n = np.array([64, 32], dtype=dtype_int)
    M=N.prod()
    for data_file in ('simple_test_nfft_2d_32.txt',
                      'simple_test_nfft_2d_64.txt'):

        # init a two dimensional plan
        pw = NfftPlanWrapper.nfft_init_guru(2, N, M, n, 7,
                PRE_PHI_HUT| PRE_FULL_PSI| MALLOC_F_HAT| MALLOC_X| MALLOC_F |
                FFTW_INIT| FFT_OUT_OF_PLACE,
                FFTW_ESTIMATE| FFTW_DESTROY_INPUT)

        assert_equal(pw.M_total, M)
        assert_equal(pw.N_total, M)  # ???? True in this case, but why ????
        assert_equal(pw.d, 2)
        read_and_check(pw, data_file)


